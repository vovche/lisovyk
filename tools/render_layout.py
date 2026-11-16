#!/usr/bin/env python3
"""Малює ілюстрації розкладок: по одному SVG на кожен із чотирьох рівнів, де
клавіші, що відрізняються від базової розкладки, виділено кольором.

  tools/render_layout.py              перемалювати ілюстрації всіх розкладок
  tools/render_layout.py --out ТЕКА   записати їх у ТЕКА/<назва>/ (для перевірки)

Файли називаються layouts/<назва>/<рівень>_<назва>.svg. Розкладку беремо не з
системи, а з репозиторію: install.sh запускається в тимчасовій теці замість
домашньої, після чого libxkbcommon компілює і нашу розкладку, і базову.
"""

import ctypes
import ctypes.util
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from xml.sax.saxutils import escape

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Розміри в умовних одиницях SVG.
UNIT = 60          # ширина звичайної клавіші разом із проміжком
GAP = 6
MARGIN = 24
TITLE_HEIGHT = 46
WIDTH = 15 * UNIT - GAP + 2 * MARGIN
HEIGHT = TITLE_HEIGHT + 5 * UNIT - GAP + 2 * MARGIN

COLOR_BACKGROUND = "#2b2b2b"
COLOR_KEY = "#474747"
COLOR_PRESSED = "#7a7a7a"   # модифікатори, які тримають на цьому рівні
COLOR_CHANGED = "#e95420"   # клавіші, що відрізняються від базової розкладки
COLOR_TEXT = "#ffffff"
COLOR_MUTED = "#b5b5b5"
FONT = "Noto Sans, DejaVu Sans, Liberation Sans, Arial, sans-serif"

# (назва клавіші XKB | підпис службової клавіші, ширина в одиницях)
ROWS = [
    [("TLDE", 1)] + [("AE%02d" % i, 1) for i in range(1, 13)] + [("⌫", 2)],
    [("Tab", 1.5)] + [("AD%02d" % i, 1) for i in range(1, 13)] + [("BKSL", 1.5)],
    [("Caps", 1.75)] + [("AC%02d" % i, 1) for i in range(1, 12)] + [("Enter", 2.25)],
    [("Shift", 2.25)] + [("AB%02d" % i, 1) for i in range(1, 11)] + [("Shift", 2.75)],
    [("Ctrl", 1.25), ("Super", 1.25), ("Alt", 1.25), ("", 6.25),
     ("AltGr", 1.25), ("Super", 1.25), ("Menu", 1.25), ("Ctrl", 1.25)],
]
KEY_NAME = re.compile(r"^(TLDE|BKSL|A[B-E]\d\d)$")

# Підпис рівня та модифікатори, які для нього тримають.
LEVELS = [
    ("1", set()),
    ("2 · Shift", {"Shift"}),
    ("3 · AltGr", {"AltGr"}),
    ("4 · AltGr + Shift", {"AltGr", "Shift"}),
]


class RuleNames(ctypes.Structure):
    _fields_ = [(k, ctypes.c_char_p) for k in ("rules", "model", "layout", "variant", "options")]


def load_xkbcommon():
    lib = ctypes.CDLL(ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0")
    u32, vp = ctypes.c_uint32, ctypes.c_void_p
    lib.xkb_context_new.restype = vp
    lib.xkb_context_new.argtypes = [ctypes.c_int]
    lib.xkb_keymap_new_from_names.restype = vp
    lib.xkb_keymap_new_from_names.argtypes = [vp, ctypes.POINTER(RuleNames), ctypes.c_int]
    lib.xkb_keymap_key_by_name.restype = u32
    lib.xkb_keymap_key_by_name.argtypes = [vp, ctypes.c_char_p]
    lib.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    lib.xkb_keymap_key_get_syms_by_level.argtypes = [
        vp, u32, u32, u32, ctypes.POINTER(ctypes.POINTER(u32))]
    lib.xkb_keysym_to_utf32.restype = u32
    lib.xkb_keysym_to_utf32.argtypes = [u32]
    return lib


def read_conf(path):
    conf = {"BASE_VARIANT": "basic"}
    for line in open(path, encoding="utf-8"):
        m = re.match(r'\s*(\w+)="?([^"\n]*)"?\s*$', line)
        if m:
            conf[m.group(1)] = m.group(2)
    return conf


def symbols(lib, layout, variant):
    """{назва клавіші: [символ рівня 1, ..., символ рівня 4]}; "" — рівень порожній."""
    ctx = lib.xkb_context_new(0)
    names = RuleNames(b"evdev", b"pc105", layout.encode(), variant.encode(), b"")
    keymap = lib.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
    if not keymap:
        sys.exit("Помилка: розкладка %s(%s) не компілюється" % (layout, variant))
    result = {}
    for row in ROWS:
        for name, _ in row:
            if not KEY_NAME.match(name):
                continue
            code = lib.xkb_keymap_key_by_name(keymap, name.encode())
            levels = []
            for level in range(4):
                syms = ctypes.POINTER(ctypes.c_uint32)()
                n = lib.xkb_keymap_key_get_syms_by_level(keymap, code, 0, level, ctypes.byref(syms))
                cp = lib.xkb_keysym_to_utf32(syms[0]) if n == 1 else 0
                levels.append(chr(cp) if cp else "")
            result[name] = levels
    return result


def label(char):
    if char and unicodedata.combining(char):
        return "◌" + char   # комбінований знак показуємо на пунктирному колі
    return char


def render(description, level, ours, base):
    title, held = LEVELS[level]
    out = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" '
        'font-family="%s" text-anchor="middle">' % (WIDTH, HEIGHT, WIDTH, HEIGHT, FONT),
        '<rect width="%d" height="%d" rx="18" fill="%s"/>' % (WIDTH, HEIGHT, COLOR_BACKGROUND),
        '<text x="%d" y="%d" font-size="20" font-weight="bold" fill="%s">%s — %s</text>'
        % (WIDTH // 2, MARGIN + 22, COLOR_TEXT, escape(description), escape(title)),
    ]
    for r, row in enumerate(ROWS):
        x = float(MARGIN)
        y = MARGIN + TITLE_HEIGHT + r * UNIT
        for name, units in row:
            w = units * UNIT - GAP
            h = UNIT - GAP
            if KEY_NAME.match(name):
                text = label(ours[name][level])
                changed = ours[name][level] != base[name][level]
                fill = COLOR_CHANGED if changed else COLOR_KEY
                size, color, weight = 24, COLOR_TEXT, "bold" if changed else "normal"
            else:
                text = name
                fill = COLOR_PRESSED if name in held else COLOR_KEY
                size, color, weight = 13, COLOR_TEXT if name in held else COLOR_MUTED, "normal"
            out.append('<rect x="%g" y="%g" width="%g" height="%g" rx="9" fill="%s"/>' % (x, y, w, h, fill))
            if text:
                out.append('<text x="%g" y="%g" font-size="%d" font-weight="%s" fill="%s">%s</text>'
                           % (x + w / 2, y + h / 2 + size * 0.36, size, weight, color, escape(text)))
            x += units * UNIT
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main(argv):
    out_root = None
    if len(argv) == 3 and argv[1] == "--out":
        out_root = argv[2]
    elif len(argv) != 1:
        sys.exit(__doc__)

    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, HOME=home)
        env.pop("XDG_CONFIG_HOME", None)
        done = subprocess.run(["bash", os.path.join(REPO_DIR, "install.sh")], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if done.returncode != 0:
            sys.exit("Помилка: install.sh не спрацював:\n" + done.stdout)
        os.environ["HOME"] = home
        os.environ.pop("XDG_CONFIG_HOME", None)

        lib = load_xkbcommon()
        layouts_dir = os.path.join(REPO_DIR, "layouts")
        for name in sorted(os.listdir(layouts_dir)):
            conf_path = os.path.join(layouts_dir, name, "layout.conf")
            if not os.path.isfile(conf_path):
                continue
            conf = read_conf(conf_path)
            ours = symbols(lib, conf["BASE_LAYOUT"], conf["VARIANT"])
            base = symbols(lib, conf["BASE_LAYOUT"], conf["BASE_VARIANT"])
            target = os.path.join(out_root, name) if out_root else os.path.join(layouts_dir, name)
            os.makedirs(target, exist_ok=True)
            for level in range(4):
                path = os.path.join(target, "%d_%s.svg" % (level + 1, name))
                with open(path, "w", encoding="utf-8") as f:
                    f.write(render(conf["DESCRIPTION"], level, ours, base))
                print(path)


if __name__ == "__main__":
    main(sys.argv)
