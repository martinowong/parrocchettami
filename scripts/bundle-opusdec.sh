#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <AppBundle.app> [--required]" >&2
    exit 2
fi

APP_BUNDLE="$1"
REQUIRED="${2:-}"
if [[ "$REQUIRED" != "" && "$REQUIRED" != "--required" ]]; then
    echo "Usage: $0 <AppBundle.app> [--required]" >&2
    exit 2
fi

OPUSDEC_SOURCE="${OPUSDEC_SOURCE:-}"
if [[ -z "$OPUSDEC_SOURCE" ]]; then
    OPUSDEC_SOURCE="$(command -v opusdec || true)"
fi

if [[ -z "$OPUSDEC_SOURCE" || ! -x "$OPUSDEC_SOURCE" ]]; then
    if [[ "$REQUIRED" == "--required" ]]; then
        echo "ERROR: opusdec not found. Install it with: brew install opus-tools" >&2
        exit 1
    fi
    echo "WARNING: opusdec not found; OPUS/WhatsApp audio will require a system opusdec." >&2
    exit 0
fi

if [[ ! -d "$APP_BUNDLE/Contents/Resources" ]]; then
    echo "ERROR: app bundle resources directory not found: $APP_BUNDLE" >&2
    exit 1
fi

BIN_DIR="$APP_BUNDLE/Contents/Resources/bin"
LIB_DIR="$APP_BUNDLE/Contents/Resources/lib"
mkdir -p "$BIN_DIR" "$LIB_DIR"

is_system_dependency() {
    local dep="$1"
    [[ "$dep" == /usr/lib/* || "$dep" == /System/* || "$dep" == @* ]]
}

macho_dependencies() {
    local file="$1"
    otool -L "$file" \
        | tail -n +2 \
        | awk '{ print $1 }' \
        | while read -r dep; do
            if [[ -n "$dep" ]] && ! is_system_dependency "$dep"; then
                printf '%s\n' "$dep"
            fi
        done
}

copy_library_closure() {
    local source="$1"
    local dep base dest nested

    macho_dependencies "$source" | while read -r dep; do
        base="$(basename "$dep")"
        dest="$LIB_DIR/$base"
        if [[ ! -e "$dest" ]]; then
            /bin/cp -X -L "$dep" "$dest"
            chmod 755 "$dest"
            while read -r nested; do
                copy_library_closure "$nested"
            done < <(macho_dependencies "$dest")
        fi
    done
}

rewrite_dependency_paths() {
    local target="$1"
    local prefix="$2"
    local dep base

    macho_dependencies "$target" | while read -r dep; do
        base="$(basename "$dep")"
        install_name_tool -change "$dep" "$prefix/$base" "$target" 2>/dev/null || true
    done
}

OPUSDEC_DEST="$BIN_DIR/opusdec"
/bin/cp -X -L "$OPUSDEC_SOURCE" "$OPUSDEC_DEST"
chmod 755 "$OPUSDEC_DEST"

copy_library_closure "$OPUSDEC_DEST"
rewrite_dependency_paths "$OPUSDEC_DEST" "@executable_path/../lib"

for lib in "$LIB_DIR"/*.dylib; do
    [[ -e "$lib" ]] || continue
    install_name_tool -id "@loader_path/$(basename "$lib")" "$lib" 2>/dev/null || true
done

for lib in "$LIB_DIR"/*.dylib; do
    [[ -e "$lib" ]] || continue
    rewrite_dependency_paths "$lib" "@loader_path"
done

echo "Bundled opusdec from $OPUSDEC_SOURCE"
