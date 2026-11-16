#!/usr/bin/env python3
"""Перевірки розкладки через libxkbcommon / libxkbregistry (ті самі бібліотеки,
якими користуються композитори Wayland та GNOME). Читає користувацькі файли з
$XDG_CONFIG_HOME/xkb або ~/.config/xkb, як і вони.

  xkbcheck.py compile  LAYOUT VARIANT              розкладка компілюється
  xkbcheck.py nocompile LAYOUT VARIANT             розкладка НЕ компілюється
  xkbcheck.py keys     LAYOUT VARIANT KEYS.XKB     клавіші дають символи з keys.xkb
  xkbcheck.py dump     LAYOUT VARIANT              надрукувати скомпільовану розкладку
  xkbcheck.py registry BASE VARIANT DESCRIPTION    варіант є в реєстрі з цим описом
  xkbcheck.py noregistry BASE VARIANT              варіанта в реєстрі немає

LAYOUT і VARIANT можуть бути списками через кому ("us,ua" ",lisovyk"); тоді
keys перевіряє останню групу.
"""

import ctypes
import ctypes.util
import os
import re
import sys

c_void_p, c_char_p, c_int, c_uint32 = ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_uint32


def load(name):
    path = ctypes.util.find_library(name) or "lib%s.so.0" % name
    try:
        return ctypes.CDLL(path)
    except OSError:
        print("SKIP: не знайдено бібліотеку lib%s" % name)
        sys.exit(77)


class RuleNames(ctypes.Structure):
    _fields_ = [(k, c_char_p) for k in ("rules", "model", "layout", "variant", "options")]


def xkb():
    lib = load("xkbcommon")
    lib.xkb_context_new.restype = c_void_p
    lib.xkb_context_new.argtypes = [c_int]
    lib.xkb_keymap_new_from_names.restype = c_void_p
    lib.xkb_keymap_new_from_names.argtypes = [c_void_p, ctypes.POINTER(RuleNames), c_int]
    lib.xkb_keymap_key_by_name.restype = c_uint32
    lib.xkb_keymap_key_by_name.argtypes = [c_void_p, c_char_p]
    lib.xkb_keymap_key_get_syms_by_level.restype = c_int
    lib.xkb_keymap_key_get_syms_by_level.argtypes = [
        c_void_p, c_uint32, c_uint32, c_uint32, ctypes.POINTER(ctypes.POINTER(c_uint32))]
    lib.xkb_keymap_num_layouts.restype = c_uint32
    lib.xkb_keymap_num_layouts.argtypes = [c_void_p]
    lib.xkb_keymap_get_as_string.restype = c_char_p
    lib.xkb_keymap_get_as_string.argtypes = [c_void_p, c_int]
    lib.xkb_keysym_from_name.restype = c_uint32
    lib.xkb_keysym_from_name.argtypes = [c_char_p, c_int]
    return lib


def compile_keymap(lib, layout, variant):
    # Повідомлення про помилки компіляції libxkbcommon пише в stderr; для
    # перевірки nocompile вони очікувані, тому глушимо їх.
    saved = os.dup(2)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 2)
    try:
        ctx = lib.xkb_context_new(0)
        names = RuleNames(b"evdev", b"pc105", layout.encode(), variant.encode(), b"")
        return lib.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
    finally:
        os.dup2(saved, 2)
        os.close(devnull)
        os.close(saved)


def cmd_compile(layout, variant, expect=True):
    ok = bool(compile_keymap(xkb(), layout, variant))
    if ok != expect:
        print("розкладка %s(%s) %s" % (layout, variant, "компілюється" if ok else "не компілюється"))
        return 1
    return 0


def cmd_dump(layout, variant):
    lib = xkb()
    keymap = compile_keymap(lib, layout, variant)
    if not keymap:
        print("розкладка %s(%s) не компілюється" % (layout, variant))
        return 1
    sys.stdout.write(lib.xkb_keymap_get_as_string(keymap, 1).decode())
    return 0


def cmd_keys(layout, variant, keys_file):
    lib = xkb()
    keymap = compile_keymap(lib, layout, variant)
    if not keymap:
        print("розкладка %s(%s) не компілюється" % (layout, variant))
        return 1
    group = lib.xkb_keymap_num_layouts(keymap) - 1
    text = re.sub(r"//[^\n]*", "", open(keys_file, encoding="utf-8").read())
    entries = re.findall(r"key\s*<(\w+)>\s*\{\s*\[([^\]]*)\]\s*\}\s*;", text)
    if not entries:
        print("у %s не знайдено жодної клавіші" % keys_file)
        return 1
    failures = 0
    for key, body in entries:
        code = lib.xkb_keymap_key_by_name(keymap, key.encode())
        if code == 0xFFFFFFFF:
            print("клавіші <%s> немає в розкладці" % key)
            failures += 1
            continue
        for level, name in enumerate(s.strip() for s in body.split(",")):
            want = lib.xkb_keysym_from_name(name.encode(), 0)
            if want == 0:
                print("<%s> рівень %d: невідома назва символу %r" % (key, level + 1, name))
                failures += 1
                continue
            syms = ctypes.POINTER(c_uint32)()
            n = lib.xkb_keymap_key_get_syms_by_level(keymap, code, group, level, ctypes.byref(syms))
            got = [syms[i] for i in range(n)]
            if got != [want]:
                print("<%s> рівень %d: очікували %s (0x%x), маємо %s"
                      % (key, level + 1, name, want, [hex(g) for g in got]))
                failures += 1
    return 1 if failures else 0


def registry_description(base, variant):
    lib = load("xkbregistry")
    for fn in ("rxkb_context_new", "rxkb_layout_first", "rxkb_layout_next"):
        getattr(lib, fn).restype = c_void_p
    lib.rxkb_context_new.argtypes = [c_int]
    lib.rxkb_context_parse_default_ruleset.argtypes = [c_void_p]
    lib.rxkb_context_parse_default_ruleset.restype = ctypes.c_bool
    lib.rxkb_layout_first.argtypes = [c_void_p]
    lib.rxkb_layout_next.argtypes = [c_void_p]
    for fn in ("rxkb_layout_get_name", "rxkb_layout_get_variant", "rxkb_layout_get_description"):
        getattr(lib, fn).restype = c_char_p
        getattr(lib, fn).argtypes = [c_void_p]
    ctx = lib.rxkb_context_new(0)
    if not lib.rxkb_context_parse_default_ruleset(ctx):
        print("libxkbregistry не зміг прочитати реєстр")
        sys.exit(1)
    layout = lib.rxkb_layout_first(ctx)
    while layout:
        if (lib.rxkb_layout_get_name(layout) == base.encode()
                and lib.rxkb_layout_get_variant(layout) == variant.encode()):
            return (lib.rxkb_layout_get_description(layout) or b"").decode()
        layout = lib.rxkb_layout_next(layout)
    return None


def cmd_registry(base, variant, description):
    got = registry_description(base, variant)
    if got != description:
        print("реєстр: для %s+%s очікували опис %r, маємо %r" % (base, variant, description, got))
        return 1
    return 0


def cmd_noregistry(base, variant):
    got = registry_description(base, variant)
    if got is not None:
        print("реєстр: %s+%s досі зареєстровано (%r)" % (base, variant, got))
        return 1
    return 0


def main(argv):
    commands = {
        "compile": (cmd_compile, 2),
        "nocompile": (lambda l, v: cmd_compile(l, v, expect=False), 2),
        "keys": (cmd_keys, 3),
        "dump": (cmd_dump, 2),
        "registry": (cmd_registry, 3),
        "noregistry": (cmd_noregistry, 2),
    }
    if len(argv) < 2 or argv[1] not in commands or len(argv) - 2 != commands[argv[1]][1]:
        print(__doc__)
        return 2
    return commands[argv[1]][0](*argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
