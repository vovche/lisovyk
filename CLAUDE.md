# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository installs custom keyboard layout variants on Linux (targeted at GNOME/Wayland, tested
on Fedora 44). It requires no root privileges. It's split into a generic installer, `install.sh`, and
per-layout data under `layouts/<name>/` — currently just `layouts/lisovyk/`, a Ukrainian variant called
"Lisovyk". `install.sh` is layout-agnostic: adding a new layout means adding a new `layouts/<name>/`
directory, not touching the script.

## Running / testing

There is no build system, package manifest, or test suite. To try it, run directly:

```bash
./install.sh              # install every layout found under layouts/
./install.sh --uninstall  # remove every layout found under layouts/
```

Verification is manual: after running the script, log out and back in, then activate a layout with:

```bash
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ua+lisovyk')]"
```

(`install.sh` prints the exact `gsettings` command for whatever it just installed, covering all
layouts in one call if there's more than one.)

## Layout data format (`layouts/<name>/`)

Each layout directory needs exactly two files:

- **`layout.conf`** — shell-sourced key/value metadata: `BASE_LAYOUT` (the system XKB layout to extend,
  e.g. `ua`), `VARIANT` (the variant's internal name), `DESCRIPTION` (the human-readable name shown in
  GNOME's input source picker).
- **`keys.xkb`** — just the body: `key <...> { [ ... ] };` lines (plus any comments), indented 4 spaces
  to match their position inside the generated `xkb_symbols` block. `install.sh` wraps this with the
  `partial alphanumeric_keys` / `xkb_symbols "$VARIANT" { include "$BASE_LAYOUT(unicode)"; name[Group1]=
  "$DESCRIPTION"; ... }` boilerplate — don't include that boilerplate in `keys.xkb` itself.

## Architecture

`install.sh` loops over every subdirectory of `layouts/`, sources its `layout.conf`, and for each one
writes/updates three XKB (X Keyboard extension) config files under `~/.config/xkb/` — the standard
user-level override location XKB consults before the system-wide `/usr/share/X11/xkb` tree:

1. **`~/.config/xkb/symbols/$BASE_LAYOUT`** — copied once from the system's
   `/usr/share/X11/xkb/symbols/$BASE_LAYOUT`, then appended with an `xkb_symbols "$VARIANT"` block
   generated from that layout's `keys.xkb`, wrapped in `// >>> BEGIN $VARIANT ... <<<` /
   `// >>> END $VARIANT <<<` marker comments (used to find and remove exactly that block on uninstall,
   regardless of what else is in the file).
2. **`~/.config/xkb/rules/evdev`** — a shared rules file (used by all layouts) mapping each
   `$BASE_LAYOUT` + `$VARIANT` combination to `+$BASE_LAYOUT($VARIANT)`, then including the system
   `evdev` ruleset for everything else.
3. **`~/.config/xkb/rules/evdev.xml`** — a shared XML registry (used by all layouts) so GNOME's input
   source picker can discover each variant. Insertion is layout-aware: an `awk` script finds the
   `<layout>` block whose `<name>` matches `$BASE_LAYOUT` and inserts the new `<variant>` into its
   `<variantList>`, or appends a whole new `<layout>` block if that base layout isn't registered yet —
   so multiple layouts with different base layouts merge correctly into one file.

Everything is idempotent and non-destructive: each step checks for its own variant's marker before
writing and skips if already present, and inserts into existing `rules/evdev` / `rules/evdev.xml`
content rather than truncating those (shared) files, so installing/uninstalling one layout doesn't
disturb another's entries.

`--uninstall` reverses all three writes per layout: it deletes the marker-delimited block from
`symbols/$BASE_LAYOUT`, removes the `$VARIANT` line from `rules/evdev`, and removes just the `<variant>`
element whose `<name>` is `$VARIANT` from `rules/evdev.xml` (via an `awk` script that buffers each
`<variant>...</variant>` element so it can drop only the matching one). It's safe to run when nothing
is installed (each step reports "not found" and continues).

The mechanism relies only on upstream, distro-agnostic behavior (`libxkbcommon`/`libxkbregistry`
reading `$XDG_CONFIG_HOME/xkb/...` and merging `rules/evdev.xml` with the system copy), not on any
Fedora-specific patches, so it's expected to work unmodified on other distros/GNOME versions (e.g.
Ubuntu) that ship a standard `xkeyboard-config`/GNOME stack.
