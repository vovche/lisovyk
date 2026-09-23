#!/bin/bash

# Загальний скрипт для встановлення додаткових варіантів клавіатурних розкладок
# на будь-якому ПК з Linux (GNOME / Wayland). Не потребує root-прав (sudo).
#
# Дані самих розкладок лежать у layouts/<назва>/ (layout.conf + keys.xkb).
# Щоб додати нову розкладку, достатньо додати нову теку в layouts/ —
# сам install.sh чіпати не потрібно.
#
# Використання:
#   ./install.sh              — встановити всі розкладки з layouts/
#   ./install.sh --uninstall  — видалити всі розкладки з layouts/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUTS_DIR="$SCRIPT_DIR/layouts"
XKB_DIR="$HOME/.config/xkb"

UNINSTALL=0
if [ "$1" = "--uninstall" ]; then
    UNINSTALL=1
fi

install_symbols() {
    local base_layout="$1" variant="$2" description="$3" keys_file="$4"
    local symbols_file="$XKB_DIR/symbols/$base_layout"

    if [ ! -f "$symbols_file" ]; then
        if [ -f "/usr/share/X11/xkb/symbols/$base_layout" ]; then
            echo "Копіюємо оригінальний файл розкладки '$base_layout'..."
            cp "/usr/share/X11/xkb/symbols/$base_layout" "$symbols_file"
        else
            echo "Помилка: не знайдено системний файл /usr/share/X11/xkb/symbols/$base_layout"
            return 1
        fi
    fi

    if grep -q "xkb_symbols \"$variant\"" "$symbols_file"; then
        echo "Конфігурація '$variant' вже є в $symbols_file, пропускаємо."
        return 0
    fi

    echo "Додаємо конфігурацію '$variant'..."
    {
        echo
        echo "// >>> BEGIN $variant (керується install.sh, не редагуйте вручну) <<<"
        echo "partial alphanumeric_keys"
        echo "xkb_symbols \"$variant\" {"
        echo "    // Базуємося на системній розкладці $base_layout, її варіанті unicode"
        echo "    include \"$base_layout(unicode)\""
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

    if [ -f "$symbols_file" ] && grep -q "xkb_symbols \"$variant\"" "$symbols_file"; then
        echo "Видаляємо блок '$variant' з $symbols_file..."
        sed -i "/^\/\/ >>> BEGIN $variant /,/^\/\/ >>> END $variant <<<\$/d" "$symbols_file"
    else
        echo "Блок '$variant' у $symbols_file не знайдено, пропускаємо."
    fi
}

install_rules() {
    local base_layout="$1" variant="$2"
    local rules_file="$XKB_DIR/rules/evdev"
    local rule_line
    rule_line="$(printf '  %s\t\t%s\t\t=\t+%s(%s)' "$base_layout" "$variant" "$base_layout" "$variant")"

    if [ -f "$rules_file" ] && grep -q "$variant" "$rules_file"; then
        echo "Правило '$variant' вже є в $rules_file, пропускаємо."
    elif [ -f "$rules_file" ]; then
        echo "Знайдено існуючий $rules_file, додаємо правило '$variant'..."
        if grep -q '^! include' "$rules_file"; then
            sed -i "/^! include/i\\${rule_line}" "$rules_file"
        else
            printf '%s\n' "$rule_line" >> "$rules_file"
        fi
    else
        echo "Записуємо правила 'evdev'..."
        {
            printf '! layout\tvariant\t\t=\tsymbols\n'
            printf '%s\n' "$rule_line"
            echo
            echo '! include %S/evdev'
        } > "$rules_file"
    fi
}

uninstall_rules() {
    local variant="$1"
    local rules_file="$XKB_DIR/rules/evdev"

    if [ -f "$rules_file" ] && grep -q "$variant" "$rules_file"; then
        echo "Видаляємо правило '$variant' з $rules_file..."
        sed -i "/$variant/d" "$rules_file"
    else
        echo "Правило '$variant' у $rules_file не знайдено, пропускаємо."
    fi
}

install_registry() {
    local base_layout="$1" variant="$2" description="$3"
    local rules_xml="$XKB_DIR/rules/evdev.xml"

    if [ -f "$rules_xml" ] && grep -q "<name>$variant</name>" "$rules_xml"; then
        echo "Розкладка '$variant' вже зареєстрована в $rules_xml, пропускаємо."
        return 0
    fi

    echo "Реєструємо '$variant' у $rules_xml..."
    if [ ! -f "$rules_xml" ]; then
        cat << 'EOF' > "$rules_xml"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xkbConfigRegistry SYSTEM "xkb.dtd">
<xkbConfigRegistry version="1.1">
  <layoutList>
  </layoutList>
</xkbConfigRegistry>
EOF
    fi

    # Вставляє <variant> у <layout>, чий <name> збігається з base_layout;
    # якщо такого <layout> ще немає у файлі — додає новий блок перед </layoutList>.
    awk -v base="$base_layout" -v variant="$variant" -v desc="$description" '
        /<layout>/ { in_layout=1; matched=0; buf=$0 "\n"; next }
        in_layout {
            buf = buf $0 "\n"
            if ($0 ~ "<name>" base "</name>") matched=1
            if ($0 ~ /<\/variantList>/ && matched && !inserted) {
                ins = "        <variant>\n          <configItem>\n            <name>" variant "</name>\n            <description>" desc "</description>\n          </configItem>\n        </variant>\n      </variantList>"
                sub(/<\/variantList>/, ins, buf)
                inserted = 1
            }
            if ($0 ~ /<\/layout>/) {
                printf "%s", buf
                in_layout = 0
            }
            next
        }
        /<\/layoutList>/ && !inserted {
            printf "    <layout>\n      <configItem>\n        <name>%s</name>\n      </configItem>\n      <variantList>\n        <variant>\n          <configItem>\n            <name>%s</name>\n            <description>%s</description>\n          </configItem>\n        </variant>\n      </variantList>\n    </layout>\n", base, variant, desc
            inserted = 1
        }
        { print }
    ' "$rules_xml" > "$rules_xml.tmp" && mv "$rules_xml.tmp" "$rules_xml"
}

uninstall_registry() {
    local variant="$1"
    local rules_xml="$XKB_DIR/rules/evdev.xml"

    if [ -f "$rules_xml" ] && grep -q "<name>$variant</name>" "$rules_xml"; then
        echo "Видаляємо variant '$variant' з $rules_xml..."
        awk -v variant="$variant" '
            /<variant>/ { buf=$0; in_variant=1; next }
            in_variant {
                buf = buf "\n" $0
                if ($0 ~ /<\/variant>/) {
                    in_variant = 0
                    if (buf !~ "<name>" variant "</name>") print buf
                    next
                }
                next
            }
            { print }
        ' "$rules_xml" > "$rules_xml.tmp" && mv "$rules_xml.tmp" "$rules_xml"
    else
        echo "Variant '$variant' у $rules_xml не знайдено, пропускаємо."
    fi
}

if [ ! -d "$LAYOUTS_DIR" ]; then
    echo "Помилка: не знайдено теку $LAYOUTS_DIR"
    exit 1
fi

mkdir -p "$XKB_DIR/symbols" "$XKB_DIR/rules"

INSTALLED_SOURCES=()
FOUND_ANY=0

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
    VARIANT=""
    DESCRIPTION=""
    . "$conf"

    if [ -z "$BASE_LAYOUT" ] || [ -z "$VARIANT" ] || [ -z "$DESCRIPTION" ]; then
        echo "Пропускаємо $name: layout.conf має задавати BASE_LAYOUT, VARIANT, DESCRIPTION"
        continue
    fi

    FOUND_ANY=1

    if [ "$UNINSTALL" -eq 1 ]; then
        echo "=== Видалення розкладки: $DESCRIPTION ($BASE_LAYOUT+$VARIANT) ==="
        uninstall_symbols "$BASE_LAYOUT" "$VARIANT"
        uninstall_rules "$VARIANT"
        uninstall_registry "$VARIANT"
    else
        echo "=== Встановлення розкладки: $DESCRIPTION ($BASE_LAYOUT+$VARIANT) ==="
        install_symbols "$BASE_LAYOUT" "$VARIANT" "$DESCRIPTION" "$keys_file" || continue
        install_rules "$BASE_LAYOUT" "$VARIANT"
        install_registry "$BASE_LAYOUT" "$VARIANT" "$DESCRIPTION"
        INSTALLED_SOURCES+=("('xkb', '$BASE_LAYOUT+$VARIANT')")
    fi
    echo
done

if [ "$FOUND_ANY" -eq 0 ]; then
    echo "Помилка: у $LAYOUTS_DIR не знайдено жодної коректної розкладки"
    exit 1
fi

echo "--------------------------------------------------------"
if [ "$UNINSTALL" -eq 1 ]; then
    echo "Видалення завершено."
    echo "Якщо потрібно, приберіть відповідні джерела вводу та зробіть Log Out і увійдіть знову, наприклад:"
    echo "   gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us')]\""
else
    echo "Встановлення завершено!"
    echo "Щоб GNOME побачив нову(і) розкладку(и):"
    echo "1. Зробіть Log Out (вихід із сесії) та увійдіть знову."
    if [ ${#INSTALLED_SOURCES[@]} -gt 0 ]; then
        joined=""
        for src in "${INSTALLED_SOURCES[@]}"; do
            if [ -z "$joined" ]; then
                joined="$src"
            else
                joined="$joined, $src"
            fi
        done
        echo "2. Після входу виконайте команду для активації розкладки(ок):"
        echo "   gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us'), $joined]\""
    fi
fi
echo "--------------------------------------------------------"
