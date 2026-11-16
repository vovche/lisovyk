#!/bin/bash

# Загальний скрипт для встановлення додаткових варіантів клавіатурних розкладок
# на ПК з Linux (композитори Wayland: GNOME, KDE, Hyprland, niri, Sway...).
# Не потребує root-прав (sudo).
#
# Дані самих розкладок лежать у layouts/<назва>/ (layout.conf + keys.xkb).
# Щоб додати нову розкладку, достатньо додати нову теку в layouts/ —
# сам install.sh чіпати не потрібно.

usage() {
    cat << 'EOF'
Використання:
  ./install.sh              — встановити (або оновити) всі розкладки з layouts/
  ./install.sh --uninstall  — видалити всі розкладки з layouts/
  ./install.sh --help       — показати цю довідку
EOF
}

if [ $# -gt 1 ]; then
    usage >&2
    exit 2
fi

case "${1-}" in
    "") UNINSTALL=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
        echo "Помилка: невідомий аргумент '$1'" >&2
        usage >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUTS_DIR="$SCRIPT_DIR/layouts"

# libxkbcommon шукає користувацькі файли в $XDG_CONFIG_HOME/xkb,
# а якщо змінну не задано — у ~/.config/xkb.
XKB_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/xkb"

REGISTRY_SKELETON='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xkbConfigRegistry SYSTEM "xkb.dtd">
<xkbConfigRegistry version="1.1">
  <layoutList>
  </layoutList>
</xkbConfigRegistry>'

# Спільна awk-функція: повертає вміст першого <name>...</name> у рядку.
AWK_NAME_OF='
    function name_of(s) {
        if (match(s, /<name>[^<]*<\/name>/)) return substr(s, RSTART + 6, RLENGTH - 13)
        return ""
    }
'

# Друкує шлях до системного файла symbols/<base>, якщо він є.
system_symbols_file() {
    local base_layout="$1" root
    for root in "${XKB_CONFIG_ROOT-}" /usr/share/xkeyboard-config-2 /usr/share/X11/xkb /usr/local/share/X11/xkb; do
        if [ -n "$root" ] && [ -f "$root/symbols/$base_layout" ]; then
            printf '%s\n' "$root/symbols/$base_layout"
            return 0
        fi
    done
    return 1
}

# Прибирає з файла блок варіанта (між маркерами BEGIN/END) разом із порожнім
# рядком перед ним. Якщо після цього у файлі лишилась тільки копія системного
# файла (так робили старі версії скрипта) або нічого — видаляє файл.
remove_symbols_block() {
    local base_layout="$1" variant="$2"
    local symbols_file="$XKB_DIR/symbols/$base_layout" sys_file

    [ -f "$symbols_file" ] || return 1
    grep -q "^// >>> BEGIN $variant " "$symbols_file" || return 1

    X_BEGIN="// >>> BEGIN $variant " X_END="// >>> END $variant <<<" awk '
        function flush() { if (have) { print held; have = 0 } }
        index($0, ENVIRON["X_BEGIN"]) == 1 { have = 0; skip = 1; next }
        skip { if ($0 == ENVIRON["X_END"]) skip = 0; next }
        { flush(); if ($0 == "") { held = $0; have = 1 } else print }
        END { flush() }
    ' "$symbols_file" > "$symbols_file.tmp" && mv "$symbols_file.tmp" "$symbols_file"

    if ! grep -q '[^[:space:]]' "$symbols_file"; then
        rm -f "$symbols_file"
    elif sys_file="$(system_symbols_file "$base_layout")" && cmp -s "$symbols_file" "$sys_file"; then
        echo "Прибираємо зайву копію системного файла $symbols_file..."
        rm -f "$symbols_file"
    fi
    return 0
}

install_symbols() {
    local base_layout="$1" variant="$2" description="$3" keys_file="$4" base_variant="$5"
    local symbols_file="$XKB_DIR/symbols/$base_layout"

    if remove_symbols_block "$base_layout" "$variant"; then
        echo "Оновлюємо блок '$variant' у $symbols_file..."
    else
        echo "Додаємо блок '$variant' у $symbols_file..."
    fi

    # Файл містить лише наші варіанти: решту секцій (зокрема ту, яку ми
    # включаємо) libxkbcommon бере із системного файла з такою самою назвою.
    {
        [ -s "$symbols_file" ] && echo
        echo "// >>> BEGIN $variant (керується install.sh, не редагуйте вручну) <<<"
        echo "partial alphanumeric_keys"
        echo "xkb_symbols \"$variant\" {"
        echo "    // Базуємося на системній розкладці $base_layout, її варіанті $base_variant"
        echo "    include \"$base_layout($base_variant)\""
        echo
        echo "    name[Group1]= \"$description\";"
        echo
        cat "$keys_file"
        echo "};"
        echo "// >>> END $variant <<<"
    } >> "$symbols_file"
}

uninstall_symbols() {
    local base_layout="$1" variant="$2"
    local symbols_file="$XKB_DIR/symbols/$base_layout"

    if remove_symbols_block "$base_layout" "$variant"; then
        echo "Видалено блок '$variant' з $symbols_file."
    else
        echo "Блок '$variant' у $symbols_file не знайдено, пропускаємо."
    fi
}

# Старі версії скрипта писали власне правило в rules/evdev. Воно не потрібне:
# системні правила самі перетворюють "ua" + "lisovyk" на ua(lisovyk).
# Прибираємо рівно той рядок, який писали ми, і сам файл, якщо в ньому більше
# нічого немає.
cleanup_legacy_rules() {
    local base_layout="$1" variant="$2"
    local rules_file="$XKB_DIR/rules/evdev"
    local rule_line

    [ -f "$rules_file" ] || return 0
    rule_line="$(printf '  %s\t\t%s\t\t=\t+%s(%s)' "$base_layout" "$variant" "$base_layout" "$variant")"
    grep -Fxq -- "$rule_line" "$rules_file" || return 0

    echo "Прибираємо застаріле правило '$variant' з $rules_file..."
    grep -Fxv -- "$rule_line" "$rules_file" > "$rules_file.tmp"
    mv "$rules_file.tmp" "$rules_file"

    if ! grep -Evq "^(! layout	variant		=	symbols|! include %S/evdev|[[:space:]]*)\$" "$rules_file"; then
        rm -f "$rules_file"
    fi
}

# Прибирає <variant> з назвою variant з того <layout>, чия назва — base_layout.
# Якщо в цьому <layout> після того не лишилось ні варіантів, ні опису, прибирає
# і його. Повертає 0, якщо файл змінився.
remove_registry_variant() {
    local base_layout="$1" variant="$2"
    local rules_xml="$XKB_DIR/rules/evdev.xml"

    [ -f "$rules_xml" ] || return 1

    X_BASE="$base_layout" X_VARIANT="$variant" awk "$AWK_NAME_OF"'
        function emit(   i, j, lname, t, m, inv, vn, vname, found, hasv, hasd) {
            lname = ""
            for (i = 1; i <= n; i++) { lname = name_of(lines[i]); if (lname != "") break }
            if (lname != ENVIRON["X_BASE"]) { for (i = 1; i <= n; i++) print lines[i]; return }
            m = 0; inv = 0
            for (i = 1; i <= n; i++) {
                if (!inv && lines[i] ~ /<variant>/) { inv = 1; vn = 0; vname = ""; found = 0 }
                if (inv) {
                    vb[++vn] = lines[i]
                    if (!found) { t = name_of(lines[i]); if (t != "") { vname = t; found = 1 } }
                    if (lines[i] ~ /<\/variant>/) {
                        inv = 0
                        if (vname != ENVIRON["X_VARIANT"]) for (j = 1; j <= vn; j++) out[++m] = vb[j]
                    }
                    continue
                }
                out[++m] = lines[i]
            }
            hasv = 0; hasd = 0
            for (i = 1; i <= m; i++) {
                if (out[i] ~ /<variant>/) hasv = 1
                if (out[i] ~ /<description>/) hasd = 1
            }
            if (!hasv && !hasd) return
            for (i = 1; i <= m; i++) print out[i]
        }
        /<layout>/ { inl = 1; n = 0 }
        inl { lines[++n] = $0; if ($0 ~ /<\/layout>/) { inl = 0; emit() } next }
        { print }
    ' "$rules_xml" > "$rules_xml.tmp" || { rm -f "$rules_xml.tmp"; return 1; }

    if cmp -s "$rules_xml" "$rules_xml.tmp"; then
        rm -f "$rules_xml.tmp"
        return 1
    fi
    mv "$rules_xml.tmp" "$rules_xml"
    return 0
}

install_registry() {
    local base_layout="$1" variant="$2" description="$3"
    local rules_xml="$XKB_DIR/rules/evdev.xml"
    local xml_description

    xml_description="$(printf '%s' "$description" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"

    remove_registry_variant "$base_layout" "$variant"

    echo "Реєструємо '$variant' у $rules_xml..."
    if [ ! -f "$rules_xml" ]; then
        printf '%s\n' "$REGISTRY_SKELETON" > "$rules_xml"
    fi

    # Вставляє <variant> у <layout>, чия назва збігається з base_layout;
    # якщо такого <layout> ще немає у файлі — додає новий блок перед </layoutList>.
    if X_BASE="$base_layout" X_VARIANT="$variant" X_DESC="$xml_description" awk "$AWK_NAME_OF"'
        function variant_block() {
            print "        <variant>"
            print "          <configItem>"
            print "            <name>" ENVIRON["X_VARIANT"] "</name>"
            print "            <description>" ENVIRON["X_DESC"] "</description>"
            print "          </configItem>"
            print "        </variant>"
        }
        /<layout>/ { inl = 1; lname = ""; gotname = 0 }
        inl && !gotname { t = name_of($0); if (t != "") { lname = t; gotname = 1 } }
        inl && !done && lname == ENVIRON["X_BASE"] && /<\/variantList>/ { variant_block(); done = 1 }
        inl && /<\/layout>/ {
            if (!done && lname == ENVIRON["X_BASE"]) {
                print "      <variantList>"
                variant_block()
                print "      </variantList>"
                done = 1
            }
            inl = 0
        }
        /<\/layoutList>/ && !done {
            print "    <layout>"
            print "      <configItem>"
            print "        <name>" ENVIRON["X_BASE"] "</name>"
            print "      </configItem>"
            print "      <variantList>"
            variant_block()
            print "      </variantList>"
            print "    </layout>"
            done = 1
        }
        { print }
        END { if (!done) exit 1 }
    ' "$rules_xml" > "$rules_xml.tmp"; then
        mv "$rules_xml.tmp" "$rules_xml"
    else
        rm -f "$rules_xml.tmp"
        echo "Помилка: у $rules_xml не знайдено </layoutList>, розкладку '$variant' не зареєстровано." >&2
        return 1
    fi
}

uninstall_registry() {
    local base_layout="$1" variant="$2"
    local rules_xml="$XKB_DIR/rules/evdev.xml"

    if remove_registry_variant "$base_layout" "$variant"; then
        echo "Видалено '$variant' з $rules_xml."
        if [ "$(cat "$rules_xml")" = "$REGISTRY_SKELETON" ]; then
            rm -f "$rules_xml"
        fi
    else
        echo "Запис '$variant' у $rules_xml не знайдено, пропускаємо."
    fi
}

if [ ! -d "$LAYOUTS_DIR" ]; then
    echo "Помилка: не знайдено теку $LAYOUTS_DIR" >&2
    exit 1
fi

if [ "${XDG_CONFIG_HOME+set}" = set ] && [ -z "$XDG_CONFIG_HOME" ]; then
    echo "Увага: XDG_CONFIG_HOME задано порожнім; libxkbcommon у такому разі не читає $XKB_DIR." >&2
fi

if [ "$UNINSTALL" -eq 0 ]; then
    mkdir -p "$XKB_DIR/symbols" "$XKB_DIR/rules" || exit 1
fi

ACTIVE_SOURCES=""
if command -v gsettings > /dev/null 2>&1; then
    ACTIVE_SOURCES="$(gsettings get org.gnome.desktop.input-sources sources 2> /dev/null)"
fi

INSTALLED_SOURCES=()
STILL_ACTIVE=()
FOUND_ANY=0
FAILED=0

for layout_dir in "$LAYOUTS_DIR"/*/; do
    [ -d "$layout_dir" ] || continue
    layout_dir="${layout_dir%/}"
    name="$(basename "$layout_dir")"
    conf="$layout_dir/layout.conf"
    keys_file="$layout_dir/keys.xkb"

    if [ ! -f "$conf" ] || [ ! -f "$keys_file" ]; then
        echo "Пропускаємо $name: не знайдено layout.conf або keys.xkb"
        continue
    fi

    BASE_LAYOUT=""
    BASE_VARIANT="basic"
    VARIANT=""
    DESCRIPTION=""
    . "$conf"

    if [ -z "$BASE_LAYOUT" ] || [ -z "$VARIANT" ] || [ -z "$DESCRIPTION" ]; then
        echo "Пропускаємо $name: layout.conf має задавати BASE_LAYOUT, VARIANT, DESCRIPTION"
        continue
    fi

    if [[ ! "$BASE_LAYOUT" =~ ^[A-Za-z0-9_-]+$ ]] || [[ ! "$VARIANT" =~ ^[A-Za-z0-9_-]+$ ]] \
        || [[ ! "$BASE_VARIANT" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Пропускаємо $name: BASE_LAYOUT, BASE_VARIANT і VARIANT можуть містити лише латинські літери, цифри, '_' та '-'"
        continue
    fi

    if [[ "$DESCRIPTION" == *'"'* ]] || [[ "$DESCRIPTION" == *$'\n'* ]]; then
        echo "Пропускаємо $name: DESCRIPTION не може містити лапки чи перенесення рядка"
        continue
    fi

    FOUND_ANY=1

    if [ "$UNINSTALL" -eq 1 ]; then
        echo "=== Видалення розкладки: $DESCRIPTION ($BASE_LAYOUT+$VARIANT) ==="
        uninstall_symbols "$BASE_LAYOUT" "$VARIANT"
        cleanup_legacy_rules "$BASE_LAYOUT" "$VARIANT"
        uninstall_registry "$BASE_LAYOUT" "$VARIANT"
        case "$ACTIVE_SOURCES" in
            *"'$BASE_LAYOUT+$VARIANT'"*) STILL_ACTIVE+=("$BASE_LAYOUT+$VARIANT") ;;
        esac
    else
        echo "=== Встановлення розкладки: $DESCRIPTION ($BASE_LAYOUT+$VARIANT) ==="
        if ! system_symbols_file "$BASE_LAYOUT" > /dev/null; then
            echo "Увага: не знайдено системну розкладку '$BASE_LAYOUT'; без неї '$VARIANT' не запрацює." >&2
        fi
        if install_symbols "$BASE_LAYOUT" "$VARIANT" "$DESCRIPTION" "$keys_file" "$BASE_VARIANT" \
            && install_registry "$BASE_LAYOUT" "$VARIANT" "$DESCRIPTION"; then
            INSTALLED_SOURCES+=("('xkb', '$BASE_LAYOUT+$VARIANT')")
        else
            FAILED=1
        fi
        cleanup_legacy_rules "$BASE_LAYOUT" "$VARIANT"
    fi
    echo
done

if [ "$FOUND_ANY" -eq 0 ]; then
    echo "Помилка: у $LAYOUTS_DIR не знайдено жодної коректної розкладки" >&2
    exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
    # Прибираємо теки, якщо вони спорожніли (rmdir не чіпає непорожні).
    rmdir "$XKB_DIR/symbols" "$XKB_DIR/rules" "$XKB_DIR" 2> /dev/null
fi

echo "--------------------------------------------------------"
if [ "$UNINSTALL" -eq 1 ]; then
    echo "Видалення завершено."
    if [ ${#STILL_ACTIVE[@]} -gt 0 ]; then
        echo "Увага: ці розкладки досі є серед джерел вводу GNOME: ${STILL_ACTIVE[*]}"
        echo "Приберіть їх у «Параметри → Клавіатура → Джерела вводу»."
    fi
    echo "Зміни набудуть чинності після виходу із сесії та повторного входу."
else
    if [ "$FAILED" -eq 1 ]; then
        echo "Встановлення завершено з помилками, див. повідомлення вище."
    else
        echo "Встановлення завершено!"
    fi
    if [ "${XDG_SESSION_TYPE-}" = "x11" ]; then
        echo "Увага: це сесія X11. X-сервер не читає $XKB_DIR, тому розкладка тут"
        echo "не запрацює; потрібна сесія Wayland."
    fi
    if [ ${#INSTALLED_SOURCES[@]} -gt 0 ]; then
        joined=""
        for src in "${INSTALLED_SOURCES[@]}"; do
            if [ -z "$joined" ]; then
                joined="$src"
            else
                joined="$joined, $src"
            fi
        done
        echo "1. Вийдіть із сесії (Log Out) та увійдіть знову."
        echo "2. GNOME: додайте розкладку в «Параметри → Клавіатура → Джерела вводу»"
        echo "   або виконайте команду (вона ЗАМІНЮЄ весь список джерел вводу):"
        echo "   gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us'), $joined]\""
        echo "   Інші середовища (KDE, Hyprland, niri, Sway): див. README.md."
    fi
fi
echo "--------------------------------------------------------"

exit "$FAILED"
