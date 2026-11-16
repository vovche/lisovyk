# AGENTS.md

Guidance for coding agents working in this repository.

## Overview

This repository installs custom keyboard layout variants on Linux without root privileges. It works
wherever the keymap is compiled by `libxkbcommon` 1.0.0+, i.e. Wayland compositors (tested on Fedora
44 and on Ubuntu 26.04 with GNOME 50). It does not work in X11 sessions: the X server compiles
keymaps with `xkbcomp` from the system directory and never reads the user directory.

It's split into a generic installer, `install.sh`, and per-layout data under `layouts/<name>/` —
currently just `layouts/lisovyk/`, a Ukrainian variant called "Lisovyk". `install.sh` is
layout-agnostic: adding a new layout means adding a new `layouts/<name>/` directory, not touching the
script.

`README.md` is the main README and is in Ukrainian; `README.en.md` is its English translation. Keep
the two in sync. Messages printed by `install.sh` and the tests are in Ukrainian.

## Running / testing

```bash
./install.sh              # install or update every layout found under layouts/
./install.sh --uninstall  # remove every layout found under layouts/
tests/run.sh              # run all tests
tests/run.sh NAME...      # run only the named tests (names without the test_ prefix)
tools/render_layout.py    # regenerate the illustrations layouts/<name>/<level>_<name>.svg
tools/build_site.sh DIR   # build the landing page and the standalone installer into DIR
```

`site/` holds the static landing page published at https://vovche.github.io/lisovyk/ (Ukrainian,
deliberately short: benefits and illustrations only, no trade-offs — those live in
`layouts/lisovyk/README.md`). `tools/build_site.sh DIR` assembles what gets published: the page, the
illustrations, and a self-contained `install.sh` for `curl ... | bash`, which is the repository's
`install.sh` plus the layout data embedded as heredocs and wrapped in a function called on the last
line (so a truncated download runs nothing). `.github/workflows/site.yml` runs the tests on every
push and deploys the site to GitHub Pages from `main`. The published `install.sh` URL is a public
interface: keep it and its `--uninstall` argument working.

The illustrations are generated, never hand-edited: `tools/render_layout.py` compiles each layout and
its base with `libxkbcommon` and draws one SVG per level, colouring the keys that differ from the
base. Re-run it after any change to `keys.xkb` or `layout.conf`; the `illustrations` test fails when
the committed SVGs are stale. That test compares against the system's base layout, so a different
`xkeyboard-config` version can legitimately change the output.

Run `tests/run.sh` after every change to `install.sh` or to anything under `layouts/`. The tests run
`install.sh` with `HOME` pointed at a temporary directory, so they never touch the real
`~/.config/xkb`, and put a stub `gsettings` first in `PATH`, because the real one changes the current
user's GNOME settings regardless of `HOME`. `tests/xkbcheck.py` checks the result through `libxkbcommon` (the keymap compiles and
every key in `keys.xkb` yields the listed keysyms) and `libxkbregistry` (the variant is discoverable
with the right description). They need `python3`, `libxkbcommon` and `libxkbregistry`; `shellcheck`
runs when installed. A test that cannot load a library reports it as skipped rather than failed.

When you change installer behaviour, add or update a test in `tests/run.sh` that would fail without
the change.

To use a freshly installed layout in a real session, log out and back in, then enable it in the
desktop's keyboard settings (`install.sh` prints the GNOME `gsettings` command; `README.md` has the
Hyprland, niri and Sway snippets).

## Layout data format (`layouts/<name>/`)

Each layout directory needs exactly two files (file names must not contain spaces). It may also hold
the generated illustrations and a `README.md` / `README.en.md` pair explaining the layout's design
decisions; when `keys.xkb` changes, update that rationale (its "what it costs" list is derived from
the diff against the base layout).

- **`layout.conf`** — shell-sourced key/value metadata: `BASE_LAYOUT` (the system XKB layout to
  extend, e.g. `ua`), `BASE_VARIANT` (the variant of it to build on, e.g. `unicode`; defaults to
  `basic`), `VARIANT` (the new variant's internal name), `DESCRIPTION` (the human-readable name shown
  in input source pickers). `BASE_LAYOUT`, `BASE_VARIANT` and `VARIANT` may contain only Latin
  letters, digits, `_` and `-`; a layout that breaks this is skipped.
- **`keys.xkb`** — just the body: `key <...> { [ ... ] };` lines (plus any comments), indented 4
  spaces to match their position inside the generated `xkb_symbols` block. `install.sh` wraps this
  with the `partial alphanumeric_keys` / `xkb_symbols "$VARIANT" { include
  "$BASE_LAYOUT($BASE_VARIANT)"; name[Group1]= "$DESCRIPTION"; ... }` boilerplate — don't include that
  boilerplate in `keys.xkb` itself.

A key definition overrides the base layout level by level: levels a key line does not list keep the
base layout's symbols.

## Architecture

`install.sh` loops over every subdirectory of `layouts/`, sources its `layout.conf`, and for each one
writes two files under `$XDG_CONFIG_HOME/xkb/` (`~/.config/xkb/` when the variable is unset) — the
user-level location `libxkbcommon` consults before the system-wide tree:

1. **`symbols/$BASE_LAYOUT`** — contains only this repository's variants, each an `xkb_symbols
   "$VARIANT"` block generated from `keys.xkb` and wrapped in `// >>> BEGIN $VARIANT ... <<<` /
   `// >>> END $VARIANT <<<` marker comments. The system file is deliberately not copied: when a
   section is missing from the user file, `libxkbcommon` keeps looking in the system file of the same
   name, so `include "ua(unicode)"` and the other stock variants still resolve to the system copy
   and pick up its updates. The layout without a variant (`ua`) is different: it is taken from the
   default section of the first file found, and without an explicit `default` that is the first
   section — ours. So the file also carries a `// >>> BEGIN @default ... <<<` block: a `default`
   section named `system-default` that only includes the system file's default section (found by
   parsing the system file). `sync_default_block` adds it whenever the file has our variants and no
   `default` section of its own, and removes it when our last variant goes. Without it the stock
   Ukrainian layout silently becomes Lisovyk; the `base_layout_untouched` test guards this by
   comparing compiled keymaps with and without the install.
2. **`rules/evdev.xml`** — a shared XML registry so input source pickers (GNOME's, via
   `libxkbregistry`) can discover each variant. An `awk` script finds the `<layout>` block whose own
   `<name>` matches `$BASE_LAYOUT` and inserts the `<variant>` into its `<variantList>`, or appends a
   new `<layout>` block if that base layout isn't registered yet. The description is XML-escaped.

No `rules/evdev` file is written: the system rules already turn layout `ua` + variant `lisovyk` into
`ua(lisovyk)`, including when it is the second layout in a list such as `us,ua`.

Installing is idempotent and doubles as updating: an existing block or registry entry for the variant
is removed and written again, so re-running after editing `keys.xkb` applies the change and running
twice changes nothing. Content that isn't ours (the user's own variants, other layouts' registry
entries, a user's `rules/evdev`) is left byte-for-byte intact.

`--uninstall` reverses both writes, removes the layout from GNOME's input source lists (`sources` and
`mru-sources` in `org.gnome.desktop.input-sources`, via `gsettings` when present — otherwise Settings
keeps showing a dangling `ua+lisovyk` entry), then deletes what it left empty: a `symbols/` file with nothing
but whitespace, a `<layout>` entry with no variants and no description, a registry file equal to the
bare skeleton, and the `symbols/`, `rules/` and `xkb/` directories if empty.

Older versions of the script copied the whole system `symbols/$BASE_LAYOUT` and wrote a rule line into
`rules/evdev`. Both install and uninstall clean that up: a `symbols/` file that, minus our block, is
identical to the system file is removed, and the exact legacy rule line is deleted (along with the
rules file if nothing else is in it).

The `awk` scripts assume one XML tag per line, which is how `install.sh` itself writes the registry.
