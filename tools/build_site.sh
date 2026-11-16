#!/bin/bash

# Збирає те, що публікується на GitHub Pages:
#   ТЕКА/index.html та решта файлів із site/
#   ТЕКА/<рівень>_<назва>.svg — ілюстрації розкладок
#   ТЕКА/install.sh — самодостатній інсталятор для `curl ... | bash`
#
#   tools/build_site.sh ТЕКА
#
# Самодостатній інсталятор — це звичайний install.sh разом із даними розкладок,
# загорнуті в один файл: під час запуску він розпаковує їх у тимчасову теку
# й запускає install.sh звідти. Увесь код лежить у функції, яку викликає
# останній рядок, тому обірване завантаження нічого не виконає.

set -eu

if [ $# -ne 1 ]; then
    echo "Використання: tools/build_site.sh ТЕКА" >&2
    exit 2
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$1"
MARK="LISOVYK_EMBEDDED_FILE_END"

mkdir -p "$OUT"
cp -r "$REPO_DIR/site/." "$OUT/"

# Друкує команди, які відтворять файл $1 за шляхом $2 усередині тимчасової теки.
embed() {
    local src="$1" dest="$2"
    if grep -qx "$MARK" "$src"; then
        echo "Помилка: $src містить рядок-розділювач $MARK" >&2
        exit 1
    fi
    # shellcheck disable=SC2016  # $tmp має розкритись у згенерованому скрипті, а не тут
    printf '    mkdir -p "$tmp/%s"\n' "$(dirname "$dest")"
    printf "    cat > \"\$tmp/%s\" << '%s'\n" "$dest" "$MARK"
    cat "$src"
    printf '%s\n' "$MARK"
}

{
    cat << 'EOF'
#!/bin/bash

# Встановлення розкладок Lisovyk без root-прав:
#   curl -fsSL https://vovche.github.io/lisovyk/install.sh | bash
#   curl -fsSL https://vovche.github.io/lisovyk/install.sh | bash -s -- --uninstall
#
# Цей файл згенеровано з https://github.com/vovche/lisovyk (tools/build_site.sh).

lisovyk_main() {
    local tmp status
    tmp="$(mktemp -d)" || exit 1
    trap 'rm -rf "$tmp"' EXIT

EOF
    embed "$REPO_DIR/install.sh" "install.sh"
    found=0
    for dir in "$REPO_DIR"/layouts/*/; do
        name="$(basename "$dir")"
        if [ -f "$dir/layout.conf" ] && [ -f "$dir/keys.xkb" ]; then
            embed "$dir/layout.conf" "layouts/$name/layout.conf"
            embed "$dir/keys.xkb" "layouts/$name/keys.xkb"
            cp "$dir"/[0-9]_*.svg "$OUT/" 2> /dev/null || true
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        echo "Помилка: у layouts/ не знайдено жодної розкладки" >&2
        exit 1
    fi
    cat << 'EOF'

    bash "$tmp/install.sh" "$@"
    status=$?
    rm -rf "$tmp"
    trap - EXIT
    exit "$status"
}

lisovyk_main "$@"
EOF
} > "$OUT/install.sh"

bash -n "$OUT/install.sh"
echo "Зібрано: $OUT"
