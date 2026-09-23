# lisovyk

Custom keyboard layout variants for Linux (GNOME/Wayland, tested on Fedora 44), installed without
root privileges. Split into a generic installer, `install.sh`, and per-layout data under
`layouts/<name>/` — currently just `layouts/lisovyk/`, a Ukrainian variant called "Lisovyk".

## Lineage

`lisovyk` is a derivative of the default Ukrainian XKB layout (`ua`), which is itself effectively the
[Ukrainian Unicode](https://r2u.org.ua/wiki/keyboard/UkrainianUnicode) layout by r2u.org.ua. `lisovyk`
only overrides a handful of keys on top of that base — see `layouts/lisovyk/keys.xkb` for the exact
diffs.

## Installing

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

Adding a new layout means adding a new `layouts/<name>/` directory — `install.sh` is layout-agnostic
and doesn't need to change.
