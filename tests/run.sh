#!/bin/bash

# Тести для install.sh. Кожен тест працює у власній тимчасовій теці, що
# підставляється замість HOME, тому справжній ~/.config/xkb не зачіпається.
#
#   tests/run.sh            — запустити всі тести
#   tests/run.sh назва ...  — запустити лише вказані (назви без префікса test_)
#   SKIP_TESTS="назва ..."  — змінна оточення: ці тести пропустити
#
# Потрібні: bash, python3, libxkbcommon та libxkbregistry (версії 1.0.0+),
# системні дані xkeyboard-config. shellcheck — за наявності.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
XKBCHECK="$TESTS_DIR/xkbcheck.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Оточення не повинно впливати на результат.
unset XDG_CONFIG_HOME XDG_SESSION_TYPE XKB_CONFIG_ROOT XKB_CONFIG_EXTRA_PATH
unset XKB_DEFAULT_RULES XKB_DEFAULT_MODEL XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT XKB_DEFAULT_OPTIONS
export LC_ALL=C.UTF-8

# Справжній gsettings змінює налаштування GNOME поточного користувача незалежно
# від HOME, тому тести підставляють замість нього заглушку, що зберігає
# значення у файлах $GSETTINGS_STUB_DIR.
export GSETTINGS_STUB_DIR="$WORK/gsettings"
mkdir -p "$GSETTINGS_STUB_DIR" "$WORK/bin"
cat > "$WORK/bin/gsettings" << 'STUB'
#!/bin/bash
file="$GSETTINGS_STUB_DIR/$2.$3"
case "$1" in
    get) cat "$file" 2> /dev/null || echo "@a(ss) []" ;;
    set) printf '%s\n' "$4" > "$file" ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/gsettings"
export PATH="$WORK/bin:$PATH"

FAILED_CHECKS=0

fail() {
    echo "    НЕ ПРОЙДЕНО: $*"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

# check ОПИС КОМАНДА... — команда має завершитись успішно.
check() {
    local what="$1" out
    shift
    if ! out="$("$@" 2>&1)"; then
        fail "$what"
        [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/      /'
    fi
}

# check_not ОПИС КОМАНДА... — команда має завершитись помилкою.
check_not() {
    local what="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        fail "$what"
    fi
}

# xkb ДІМ АРГУМЕНТИ... — запускає xkbcheck.py з підставленим HOME.
xkb() {
    local home="$1" out status
    shift
    out="$(HOME="$home" python3 "$XKBCHECK" "$@" 2>&1)"
    status=$?
    if [ "$status" -eq 77 ]; then
        echo "    ПРОПУЩЕНО: $out"
        return 0
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
    return "$status"
}

# install ДІМ [АРГУМЕНТИ...] — запускає install.sh репозиторію з підставленим HOME.
install() {
    local home="$1"
    shift
    HOME="$home" bash "$REPO_DIR/install.sh" "$@"
}

new_home() {
    local home="$WORK/$1/home"
    mkdir -p "$home"
    printf '%s\n' "$home"
}

same_tree() {
    diff -r "$1" "$2"
}

system_symbols() {
    local root
    for root in /usr/share/xkeyboard-config-2 /usr/share/X11/xkb; do
        if [ -f "$root/symbols/$1" ]; then
            printf '%s\n' "$root/symbols/$1"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------

test_syntax() {
    check "install.sh має коректний синтаксис bash" bash -n "$REPO_DIR/install.sh"
    check "tests/run.sh має коректний синтаксис bash" bash -n "$TESTS_DIR/run.sh"
    if command -v shellcheck > /dev/null 2>&1; then
        check "shellcheck не має зауважень до install.sh" shellcheck -x -e SC1090 "$REPO_DIR/install.sh"
        check "shellcheck не має зауважень до tools/build_site.sh" shellcheck "$REPO_DIR/tools/build_site.sh"
    else
        echo "    ПРОПУЩЕНО: shellcheck не встановлено"
    fi
}

test_layout_data() {
    local dir found=0
    for dir in "$REPO_DIR"/layouts/*/; do
        found=1
        check "$(basename "$dir") має layout.conf" test -f "$dir/layout.conf"
        check "$(basename "$dir") має keys.xkb" test -f "$dir/keys.xkb"
        check_not "keys.xkb у $(basename "$dir") не містить обгортки xkb_symbols" \
            grep -q 'xkb_symbols' "$dir/keys.xkb"
    done
    check "у layouts/ є хоча б одна розкладка" test "$found" -eq 1
    check_not "у репозиторії немає назв файлів із пробілами" \
        sh -c "find '$REPO_DIR' -path '$REPO_DIR/.git' -prune -o -name '* *' -print | grep -q ."
}

test_arguments() {
    local home status
    home="$(new_home arguments)"

    install "$home" --help > /dev/null 2>&1
    check "--help завершується з кодом 0" test $? -eq 0

    install "$home" --bogus > /dev/null 2>&1
    status=$?
    check "невідомий аргумент дає код 2" test "$status" -eq 2

    install "$home" --uninstall extra > /dev/null 2>&1
    status=$?
    check "зайвий аргумент дає код 2" test "$status" -eq 2

    check_not "довідка й помилки аргументів нічого не пишуть на диск" test -e "$home/.config"
}

test_fresh_install() {
    local home xkbdir
    home="$(new_home fresh)"
    xkbdir="$home/.config/xkb"

    check "встановлення завершується успішно" install "$home"
    check "створено symbols/ua" test -f "$xkbdir/symbols/ua"
    check "створено rules/evdev.xml" test -f "$xkbdir/rules/evdev.xml"
    check_not "rules/evdev не створюється" test -e "$xkbdir/rules/evdev"
    check_not "symbols/ua не містить копії системного файла" grep -q 'xkb_symbols "unicode"' "$xkbdir/symbols/ua"
    check "у symbols/ua рівно один блок lisovyk" \
        test "$(grep -c 'xkb_symbols "lisovyk"' "$xkbdir/symbols/ua")" -eq 1

    check "розкладка ua(lisovyk) компілюється" xkb "$home" compile ua lisovyk
    check "клавіші дають символи з keys.xkb" xkb "$home" keys ua lisovyk "$REPO_DIR/layouts/lisovyk/keys.xkb"
    check "те саме, коли lisovyk — друга розкладка (us,ua)" \
        xkb "$home" keys us,ua ,lisovyk "$REPO_DIR/layouts/lisovyk/keys.xkb"
    check "варіант видно в реєстрі з правильним описом" xkb "$home" registry ua lisovyk "Ukrainian (Lisovyk)"
    check "системна розкладка ua лишається доступною" xkb "$home" compile ua ""
}

# Встановлення не має змінювати жодну системну розкладку: ні типову "ua"
# (вона береться з першої секції файла symbols/ua, а наш файл має ту саму
# назву), ні її інші варіанти, ні ua як другу розкладку в списку.
test_base_layout_untouched() {
    local home clean spec layout variant
    home="$(new_home base-installed)"
    clean="$(new_home base-clean)"
    install "$home" > /dev/null 2>&1

    for spec in "ua:" "ua:legacy" "ua:homophonic" "us,ua:," "us:"; do
        layout="${spec%%:*}"
        variant="${spec#*:}"
        if ! xkb "$clean" dump "$layout" "$variant" > "$WORK/base-clean/dump" 2>&1; then
            echo "    ПРОПУЩЕНО: у системі немає розкладки $layout($variant)"
            continue
        fi
        xkb "$home" dump "$layout" "$variant" > "$WORK/base-installed/dump" 2>&1
        check "розкладка $layout($variant) така сама, як без встановлення" \
            cmp "$WORK/base-clean/dump" "$WORK/base-installed/dump"
    done

    # Те саме, коли у файлі користувача вже є його власний варіант без позначки default.
    home="$(new_home base-foreign)"
    mkdir -p "$home/.config/xkb/symbols"
    printf 'partial alphanumeric_keys\nxkb_symbols "mine" {\n    include "ua(unicode)"\n    key <AE01> { [ 1, exclam, U2020, U2021 ] };\n};\n' \
        > "$home/.config/xkb/symbols/ua"
    install "$home" > /dev/null 2>&1
    xkb "$clean" dump ua "" > "$WORK/base-clean/dump" 2>&1
    xkb "$home" dump ua "" > "$WORK/base-foreign/dump" 2>&1
    check "типова ua така сама й поруч із варіантом користувача" \
        cmp "$WORK/base-clean/dump" "$WORK/base-foreign/dump"
}

test_idempotent() {
    local home
    home="$(new_home idempotent)"

    install "$home" > /dev/null 2>&1
    cp -r "$home/.config/xkb" "$WORK/idempotent/first"
    check "повторне встановлення завершується успішно" install "$home"
    check "повторне встановлення нічого не змінює" same_tree "$WORK/idempotent/first" "$home/.config/xkb"
}

test_uninstall_clean() {
    local home
    home="$(new_home uninstall)"

    install "$home" > /dev/null 2>&1
    check "видалення завершується успішно" install "$home" --uninstall
    check_not "після видалення ~/.config/xkb не лишається" test -e "$home/.config/xkb"
    check "ua(lisovyk) більше не компілюється" xkb "$home" nocompile ua lisovyk
    check "варіанта більше немає в реєстрі" xkb "$home" noregistry ua lisovyk
}

test_uninstall_nothing() {
    local home
    home="$(new_home nothing)"

    check "видалення без встановлення завершується успішно" install "$home" --uninstall
    check_not "видалення без встановлення нічого не створює" test -e "$home/.config"
}

test_update() {
    local repo="$WORK/update/repo" home
    home="$(new_home update)"
    mkdir -p "$repo"
    cp -r "$REPO_DIR/install.sh" "$REPO_DIR/layouts" "$repo/"

    HOME="$home" bash "$repo/install.sh" > /dev/null 2>&1
    printf '    key <AE01> { [ 1, exclam, U2020, U2021 ] };\n' >> "$repo/layouts/lisovyk/keys.xkb"
    check "встановлення після правки keys.xkb завершується успішно" env HOME="$home" bash "$repo/install.sh"
    check "блок lisovyk лишається один" \
        test "$(grep -c 'xkb_symbols "lisovyk"' "$home/.config/xkb/symbols/ua")" -eq 1
    check "у реєстрі лишається один запис lisovyk" \
        test "$(grep -c '<name>lisovyk</name>' "$home/.config/xkb/rules/evdev.xml")" -eq 1
    check "нова клавіша набула чинності" xkb "$home" keys ua lisovyk "$repo/layouts/lisovyk/keys.xkb"
}

# Чужі (не наші) записи користувача мають пережити встановлення та видалення.
test_preserves_foreign() {
    local home xkbdir
    home="$(new_home foreign)"
    xkbdir="$home/.config/xkb"
    mkdir -p "$xkbdir/symbols" "$xkbdir/rules"

    cat > "$xkbdir/symbols/ua" << 'EOF'
// власний варіант користувача
partial alphanumeric_keys
xkb_symbols "mine" {
    include "ua(unicode)"
    name[Group1]= "Ukrainian (mine)";
    key <AE01> { [ 1, exclam, U2020, U2021 ] };
};
EOF
    cat > "$xkbdir/rules/evdev.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xkbConfigRegistry SYSTEM "xkb.dtd">
<xkbConfigRegistry version="1.1">
  <layoutList>
    <layout>
      <configItem>
        <name>de</name>
      </configItem>
      <variantList>
        <variant>
          <configItem>
            <name>lisovyk</name>
            <description>German (same variant name, other layout)</description>
          </configItem>
        </variant>
      </variantList>
    </layout>
    <layout>
      <configItem>
        <name>ua</name>
      </configItem>
      <variantList>
        <variant>
          <configItem>
            <name>mine</name>
            <description>Ukrainian (mine)</description>
          </configItem>
        </variant>
      </variantList>
    </layout>
  </layoutList>
</xkbConfigRegistry>
EOF
    printf '! option\t=\tsymbols\n  custom:opt\t=\t+custom(opt)\n\n! include %%S/evdev\n' > "$xkbdir/rules/evdev"
    cp -r "$xkbdir" "$WORK/foreign/before"

    check "встановлення поруч із чужими записами завершується успішно" install "$home"
    check "наш варіант компілюється" xkb "$home" keys ua lisovyk "$REPO_DIR/layouts/lisovyk/keys.xkb"
    check "варіант користувача компілюється" xkb "$home" compile ua mine
    check "наш варіант є в реєстрі" xkb "$home" registry ua lisovyk "Ukrainian (Lisovyk)"
    check "варіант користувача є в реєстрі" xkb "$home" registry ua mine "Ukrainian (mine)"
    check "однойменний варіант іншої розкладки не зачеплено" \
        xkb "$home" registry de lisovyk "German (same variant name, other layout)"
    check "rules/evdev користувача не змінено" cmp "$WORK/foreign/before/rules/evdev" "$xkbdir/rules/evdev"

    check "видалення завершується успішно" install "$home" --uninstall
    check "після видалення файли користувача такі самі, як були" same_tree "$WORK/foreign/before" "$xkbdir"
}

# Стан, який лишали старі версії скрипта: повна копія системного symbols/ua,
# власне правило в rules/evdev.
make_legacy_state() {
    local xkbdir="$1" sys_ua="$2"
    mkdir -p "$xkbdir/symbols" "$xkbdir/rules"
    cp "$sys_ua" "$xkbdir/symbols/ua"
    {
        echo
        echo "// >>> BEGIN lisovyk (керується install.sh, не редагуйте вручну) <<<"
        echo "partial alphanumeric_keys"
        echo "xkb_symbols \"lisovyk\" {"
        echo "    include \"ua(unicode)\""
        echo "    name[Group1]= \"Ukrainian (Lisovyk)\";"
        echo "    key <AE01> { [ 1, exclam, U2020, U2021 ] };"
        echo "};"
        echo "// >>> END lisovyk <<<"
    } >> "$xkbdir/symbols/ua"
    printf '! layout\tvariant\t\t=\tsymbols\n  ua\t\tlisovyk\t\t=\t+ua(lisovyk)\n\n! include %%S/evdev\n' \
        > "$xkbdir/rules/evdev"
    cat > "$xkbdir/rules/evdev.xml" << 'EOF'
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
            <description>Ukrainian (old description)</description>
          </configItem>
        </variant>
      </variantList>
    </layout>
  </layoutList>
</xkbConfigRegistry>
EOF
}

test_legacy_migration() {
    local sys_ua home fresh
    if ! sys_ua="$(system_symbols ua)"; then
        echo "    ПРОПУЩЕНО: не знайдено системний symbols/ua"
        return 0
    fi

    home="$(new_home legacy)"
    make_legacy_state "$home/.config/xkb" "$sys_ua"
    fresh="$(new_home legacy-fresh)"
    install "$fresh" > /dev/null 2>&1

    check "встановлення поверх старого стану завершується успішно" install "$home"
    check "старий стан зводиться до того самого, що й чисте встановлення" \
        same_tree "$fresh/.config/xkb" "$home/.config/xkb"

    home="$(new_home legacy-uninstall)"
    make_legacy_state "$home/.config/xkb" "$sys_ua"
    check "видалення старого стану завершується успішно" install "$home" --uninstall
    check_not "після видалення старого стану ~/.config/xkb не лишається" test -e "$home/.config/xkb"
}

test_xdg_config_home() {
    local home cfg
    home="$(new_home xdg)"
    cfg="$WORK/xdg/cfg"

    check "встановлення з XDG_CONFIG_HOME завершується успішно" \
        env HOME="$home" XDG_CONFIG_HOME="$cfg" bash "$REPO_DIR/install.sh"
    check "файли записано в \$XDG_CONFIG_HOME/xkb" test -f "$cfg/xkb/symbols/ua"
    check_not "у ~/.config нічого не записано" test -e "$home/.config"
    check "libxkbcommon бачить розкладку" \
        env XDG_CONFIG_HOME="$cfg" bash -c "HOME='$home' python3 '$XKBCHECK' compile ua lisovyk; s=\$?; [ \$s -eq 0 ] || [ \$s -eq 77 ]"
}

# Кілька розкладок із різними базовими розкладками; некоректна має бути пропущена.
test_multiple_layouts() {
    local repo="$WORK/multi/repo" home
    home="$(new_home multi)"
    mkdir -p "$repo/layouts/second" "$repo/layouts/broken"
    cp -r "$REPO_DIR/install.sh" "$repo/"
    cp -r "$REPO_DIR/layouts/lisovyk" "$repo/layouts/"
    rm -f "$repo"/layouts/lisovyk/*.png

    printf 'BASE_LAYOUT="us"\nVARIANT="second"\nDESCRIPTION="English (A & B <test>)"\n' > "$repo/layouts/second/layout.conf"
    printf '    key <AE01> { [ 1, exclam, U2020, U2021 ] };\n' > "$repo/layouts/second/keys.xkb"
    printf 'BASE_LAYOUT="us"\nVARIANT="bad name/.*"\nDESCRIPTION="Broken"\n' > "$repo/layouts/broken/layout.conf"
    printf '    key <AE01> { [ 1 ] };\n' > "$repo/layouts/broken/keys.xkb"

    check "встановлення двох розкладок завершується успішно" env HOME="$home" bash "$repo/install.sh"
    check "перша розкладка працює" xkb "$home" keys ua lisovyk "$repo/layouts/lisovyk/keys.xkb"
    check "друга розкладка працює" xkb "$home" keys us second "$repo/layouts/second/keys.xkb"
    check "перша є в реєстрі" xkb "$home" registry ua lisovyk "Ukrainian (Lisovyk)"
    check "опис зі спецсимволами XML збережено дослівно" xkb "$home" registry us second "English (A & B <test>)"
    check_not "некоректну розкладку пропущено" grep -rq 'bad name' "$home/.config/xkb"

    check "видалення двох розкладок завершується успішно" env HOME="$home" bash "$repo/install.sh" --uninstall
    check_not "після видалення ~/.config/xkb не лишається" test -e "$home/.config/xkb"
}

# Ілюстрації в репозиторії мають відповідати поточним keys.xkb.
test_illustrations() {
    local out="$WORK/illustrations" dir name
    if ! python3 "$REPO_DIR/tools/render_layout.py" --out "$out" > /dev/null 2>&1; then
        fail "tools/render_layout.py завершується успішно"
        return
    fi
    for dir in "$out"/*/; do
        name="$(basename "$dir")"
        check "ілюстрації $name актуальні (інакше запустіть tools/render_layout.py)" \
            sh -c "cd '$dir' && for f in *.svg; do cmp \"\$f\" '$REPO_DIR/layouts/$name/'\"\$f\" || exit 1; done"
    done
}

# Видалення має прибрати розкладку і зі списків джерел вводу GNOME.
test_gnome_sources() {
    local home schema="org.gnome.desktop.input-sources"
    home="$(new_home gnome)"
    install "$home" > /dev/null 2>&1

    gsettings set "$schema" sources "[('xkb', 'us'), ('xkb', 'ua+lisovyk'), ('xkb', 'de+lisovyk'), ('xkb', 'ua+lisovyk2')]"
    gsettings set "$schema" mru-sources "[('xkb', 'ua+lisovyk'), ('xkb', 'us')]"
    install "$home" > /dev/null 2>&1
    check "встановлення не змінює джерела вводу" \
        test "$(gsettings get "$schema" mru-sources)" = "[('xkb', 'ua+lisovyk'), ('xkb', 'us')]"
    install "$home" --uninstall > /dev/null 2>&1
    check "з sources прибрано лише нашу розкладку" \
        test "$(gsettings get "$schema" sources)" = "[('xkb', 'us'), ('xkb', 'de+lisovyk'), ('xkb', 'ua+lisovyk2')]"
    check "з mru-sources прибрано нашу розкладку" \
        test "$(gsettings get "$schema" mru-sources)" = "[('xkb', 'us')]"

    gsettings set "$schema" sources "[('xkb', 'us'), ('xkb', 'ua+lisovyk')]"
    install "$home" --uninstall > /dev/null 2>&1
    check "розкладку прибрано з кінця списку" test "$(gsettings get "$schema" sources)" = "[('xkb', 'us')]"

    gsettings set "$schema" sources "[('xkb', 'ua+lisovyk')]"
    install "$home" --uninstall > /dev/null 2>&1
    check "єдину розкладку прибрано, список порожній" test "$(gsettings get "$schema" sources)" = "@a(ss) []"

    gsettings set "$schema" sources "[('xkb', 'us'), ('xkb', 'ua')]"
    install "$home" --uninstall > /dev/null 2>&1
    check "чужі джерела вводу не змінено" test "$(gsettings get "$schema" sources)" = "[('xkb', 'us'), ('xkb', 'ua')]"
}

# Самодостатній інсталятор із сайту: запуск через канал, як із curl.
test_standalone() {
    local out="$WORK/standalone/site" home size
    home="$(new_home standalone)"

    check "tools/build_site.sh завершується успішно" bash "$REPO_DIR/tools/build_site.sh" "$out"
    check "зібрано index.html" test -f "$out/index.html"
    check "зібрано ілюстрації" test -f "$out/3_lisovyk.svg"
    [ -f "$out/install.sh" ] || { fail "зібрано install.sh"; return; }

    check "встановлення через канал завершується успішно" sh -c "HOME='$home' bash < '$out/install.sh'"
    check "розкладка працює" xkb "$home" keys ua lisovyk "$REPO_DIR/layouts/lisovyk/keys.xkb"
    check "варіант є в реєстрі" xkb "$home" registry ua lisovyk "Ukrainian (Lisovyk)"
    check "видалення через канал завершується успішно" \
        sh -c "HOME='$home' bash -s -- --uninstall < '$out/install.sh'"
    check_not "після видалення ~/.config/xkb не лишається" test -e "$home/.config/xkb"

    # Обірване завантаження не має нічого встановити.
    home="$(new_home standalone-truncated)"
    size="$(wc -c < "$out/install.sh")"
    head -c "$((size / 2))" "$out/install.sh" > "$WORK/standalone/half.sh"
    HOME="$home" bash < "$WORK/standalone/half.sh" > /dev/null 2>&1
    check_not "половина скрипта нічого не встановлює" test -e "$home/.config"
    head -c "$((size - 20))" "$out/install.sh" > "$WORK/standalone/almost.sh"
    HOME="$home" bash < "$WORK/standalone/almost.sh" > /dev/null 2>&1
    check_not "скрипт без останнього рядка нічого не встановлює" test -e "$home/.config"
}

# ---------------------------------------------------------------------------

ALL_TESTS=(
    syntax layout_data arguments fresh_install base_layout_untouched idempotent uninstall_clean uninstall_nothing
    update preserves_foreign legacy_migration xdg_config_home multiple_layouts gnome_sources illustrations standalone
)

if [ $# -gt 0 ]; then
    SELECTED=("$@")
else
    SELECTED=("${ALL_TESTS[@]}")
fi

FAILED_TESTS=()
for name in "${SELECTED[@]}"; do
    case " ${SKIP_TESTS-} " in
        *" $name "*) echo "== $name: пропущено (SKIP_TESTS)"; continue ;;
    esac
    if ! declare -F "test_$name" > /dev/null; then
        echo "Невідомий тест: $name (є: ${ALL_TESTS[*]})" >&2
        exit 2
    fi
    FAILED_CHECKS=0
    echo "== $name"
    "test_$name"
    if [ "$FAILED_CHECKS" -gt 0 ]; then
        FAILED_TESTS+=("$name")
    fi
done

echo
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "НЕ ПРОЙДЕНО: ${FAILED_TESTS[*]}"
    exit 1
fi
echo "Усі тести пройдено (${#SELECTED[@]})."
