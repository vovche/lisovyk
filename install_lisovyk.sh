#!/bin/bash

# Скрипт для встановлення розкладки Ukrainian (Lisovyk) на будь-якому ПК з Linux (GNOME / Wayland)
# Не потребує root-прав (sudo).

echo "=== Початок встановлення розкладки Ukrainian (Lisovyk) ==="

# 1. Створюємо необхідні директорії
XKB_DIR="$HOME/.config/xkb"
mkdir -p "$XKB_DIR/symbols"
mkdir -p "$XKB_DIR/rules"

# 2. Скопіюємо системний файл розкладки 'ua' та додамо наш варіант 'lisovyk'
if [ -f "/usr/share/X11/xkb/symbols/ua" ]; then
    echo "Копіюємо оригінальний файл розкладки 'ua'..."
    cp "/usr/share/X11/xkb/symbols/ua" "$XKB_DIR/symbols/ua"
else
    echo "Помилка: не знайдено системний файл /usr/share/X11/xkb/symbols/ua"
    exit 1
fi

echo "Додаємо конфігурацію 'lisovyk'..."
cat << 'EOF' >> "$XKB_DIR/symbols/ua"

// Custom Ukrainian variant (Lisovyk)
partial alphanumeric_keys
xkb_symbols "lisovyk" {
    // Базуємося на системній розкладці ua, її варіанті unicode
    include "ua(unicode)"

    name[Group1]= "Ukrainian (Lisovyk)";

    // 1. Модифікована поведінка клавіші tlde:
    key <TLDE> { [ U02BC, asciitilde, grave, U0301 ] };

    // 2. Для <AD05> на 3 рівні має бути Cyrillic_e (э), на 4 рівні — Cyrillic_E (Э)
    key <AD05> { [ Cyrillic_ie, Cyrillic_IE, Cyrillic_e, Cyrillic_E ] };

    // 3. Для <AD11> (літера Х) та <AD12> (літера Ї) на 3,4 рівні ставимо дужки:
    key <AD11> { [ Cyrillic_ha, Cyrillic_HA, bracketleft, braceleft ] };
    key <AD12> { [ Ukrainian_yi, Ukrainian_YI, bracketright, braceright ] };

    // 4. Для <AB07> на 3,4 рівні поставити ъЪ
    key <AB07> { [ Cyrillic_softsign, Cyrillic_SOFTSIGN, Cyrillic_hardsign, Cyrillic_HARDSIGN ] };

    // 5. З <AC02> ыЫ перемістити на відповідні місця <AB05>
    key <AC02> { [ Ukrainian_i, Ukrainian_I ] };
    key <AB05> { [ Cyrillic_i, Cyrillic_I, Cyrillic_yeru, Cyrillic_YERU ] };

    // 6. Переміщення backslash (\) та bar (|) на 1-2й рівні, а літери ґ/Ґ — на 3-4й рівні (для клавіші <BKSL>):
    key <BKSL> { [ backslash, bar, Ukrainian_ghe_with_upturn, Ukrainian_GHE_WITH_UPTURN ] };

    // 7. Для кнопок 2 та 3 на 3 рівні ставимо @ та # (замість ² та §):
    key <AE02> { [ 2, quotedbl, at, U2019 ] };
    key <AE03> { [ 3, numerosign, numbersign, U20B4 ] };

    // 8. 3-4 рівень для кнопок ж (AC10) та є (AC11) як 1-2 рівні на US:
    key <AC10> { [ Cyrillic_zhe, Cyrillic_ZHE, semicolon, colon ] };
    key <AC11> { [ Ukrainian_ie, Ukrainian_IE, apostrophe, quotedbl ] };

    // 9. 3-4 рівень для кнопок б (AB08) та ю (AB09) як 1-2 рівні на US:
    key <AB08> { [ Cyrillic_be, Cyrillic_BE, comma, less ] };
    key <AB09> { [ Cyrillic_yu, Cyrillic_YU, period, greater ] };

    // 10. 3 рівень для 6 (AE06), 7 (AE07), 8 (AE08) як 2й рівень на US:
    key <AE06> { [ 6, colon, asciicircum, less ] };
    key <AE07> { [ 7, question, ampersand, greater ] };
    key <AE08> { [ 8, asterisk, asterisk, enfilledcircbullet ] };
};
EOF

# 3. Створюємо правила реєстрації
echo "Записуємо правила 'evdev'..."
cat << 'EOF' > "$XKB_DIR/rules/evdev"
! layout	variant		=	symbols
  ua		lisovyk		=	+ua(lisovyk)

! include %S/evdev
EOF

# 4. Створюємо XML-реєстратуру для GNOME
echo "Записуємо XML-реєстратуру..."
cat << 'EOF' > "$XKB_DIR/rules/evdev.xml"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xkbConfigRegistry SYSTEM "xkb.dtd">
<xkbConfigRegistry version="1.1">
  <layoutList>
    <layout>
      <configItem>
        <name>ua</name>
      </configItem>
      <variantList>
        <variant>
          <configItem>
            <name>lisovyk</name>
            <description>Ukrainian (Lisovyk)</description>
          </configItem>
        </variant>
      </variantList>
    </layout>
  </layoutList>
</xkbConfigRegistry>
EOF

echo "Конфігураційні файли успішно записано."
echo "--------------------------------------------------------"
echo "УВАГА: Для того, щоб GNOME побачив нову розкладку:"
echo "1. Зробіть Log Out (вихід із сесії) та увійдіть знову."
echo "2. Після входу виконайте команду для активації розкладки:"
echo "   gsettings set org.gnome.desktop.input-sources sources \"[('xkb', 'us'), ('xkb', 'ua+lisovyk')]\""
echo "--------------------------------------------------------"
echo "Встановлення завершено!"
