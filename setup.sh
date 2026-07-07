#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
MODELS_DIR="$SCRIPT_DIR/models"

PARAKEET_VERSION="v0.4.0"
PARAKEET_VERSION_NUMBER="${PARAKEET_VERSION#v}"
MODEL_FILE="tdt-0.6b-v3-q5_k.gguf"
MODEL_URL="https://huggingface.co/mudler/parakeet-cpp-gguf/resolve/main/$MODEL_FILE"
MODEL_SHA256="5ebd1d55609b5ad9dac1c457eeb87a9904f199d6fbbb738453182d010646c2e4"

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"

    if [ "$actual" != "$expected" ]; then
        echo "ERROR: Checksum verification failed for $(basename "$file")." >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    fi
}

is_expected_parakeet_version() {
    local output="$1"
    printf "%s" "$output" | grep -Eq "(^|[^0-9])v?${PARAKEET_VERSION_NUMBER}([^0-9]|$)"
}

echo "====== Parrocchettami Setup ======"
echo ""

mkdir -p "$BIN_DIR" "$MODELS_DIR"

ARCH="$(uname -m)"
OS="$(uname -s)"

if [ "$OS" != "Darwin" ]; then
    echo "ERROR: macOS only."
    exit 1
fi

if [ "$ARCH" = "arm64" ]; then
    BINARY_ARCHIVE="parakeet-$PARAKEET_VERSION-bin-macos-metal-arm64.tar.gz"
    BINARY_SHA256="e607d8700bec29c5bf8fa2e8155adfbf92d4433d98608a9dd866633ea7d01767"
elif [ "$ARCH" = "x86_64" ]; then
    BINARY_ARCHIVE="parakeet-$PARAKEET_VERSION-bin-macos-cpu-x64.tar.gz"
    BINARY_SHA256="6f985e7a7185646e97a2d4fa7953b2019327ad56ad677f0602c666745d036a8d"
else
    echo "ERROR: Unsupported architecture: $ARCH" >&2
    exit 1
fi

BINARY_URL="https://github.com/mudler/parakeet.cpp/releases/download/$PARAKEET_VERSION/$BINARY_ARCHIVE"
DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/parrocchettami-setup.XXXXXX")"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

echo "Architecture: $ARCH"
echo ""

# --- Download parakeet-cli ---
CLI_PATH="$BIN_DIR/parakeet-cli"
INSTALL_CLI=1
if [ -f "$CLI_PATH" ] && [ -x "$CLI_PATH" ]; then
    CLI_VERSION_OUTPUT="$("$CLI_PATH" --version 2>&1 || true)"
    if is_expected_parakeet_version "$CLI_VERSION_OUTPUT"; then
        echo "parakeet-cli $PARAKEET_VERSION already installed. Skipping."
        INSTALL_CLI=0
    else
        echo "Existing parakeet-cli is not $PARAKEET_VERSION; updating."
        echo "Current version output: ${CLI_VERSION_OUTPUT:-unknown}"
    fi
fi

if [ "$INSTALL_CLI" -eq 1 ]; then
    echo "--- Downloading parakeet-cli $PARAKEET_VERSION ---"
    ARCHIVE_PATH="$DOWNLOAD_DIR/$BINARY_ARCHIVE"
    EXTRACT_DIR="$DOWNLOAD_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"

    curl --fail --location --progress-bar -o "$ARCHIVE_PATH" "$BINARY_URL"
    verify_sha256 "$ARCHIVE_PATH" "$BINARY_SHA256"
    echo "Checksum verified."
    echo "Extracting..."
    tar xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
    CLI_CANDIDATE="$(find "$EXTRACT_DIR" -name "parakeet-cli" -type f -print -quit)"
    if [ -z "$CLI_CANDIDATE" ]; then
        echo "ERROR: The verified archive does not contain parakeet-cli." >&2
        exit 1
    fi
    install -m 755 "$CLI_CANDIDATE" "$CLI_PATH"
    xattr -dr com.apple.quarantine "$CLI_PATH" 2>/dev/null || true
    CLI_VERSION_OUTPUT="$("$CLI_PATH" --version 2>&1 || true)"
    if ! is_expected_parakeet_version "$CLI_VERSION_OUTPUT"; then
        echo "ERROR: Installed parakeet-cli does not report $PARAKEET_VERSION." >&2
        echo "Version output: ${CLI_VERSION_OUTPUT:-unknown}" >&2
        exit 1
    fi
    echo "parakeet-cli $PARAKEET_VERSION installed."
fi

# --- Download GGUF model ---
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
if [ -f "$MODEL_PATH" ]; then
    echo "Verifying existing model..."
    verify_sha256 "$MODEL_PATH" "$MODEL_SHA256"
    echo "Model checksum verified."
else
    echo ""
    echo "--- Downloading model: $MODEL_FILE ---"
    echo "Size: ~707MB, this may take a few minutes..."
    MODEL_TEMP="$DOWNLOAD_DIR/$MODEL_FILE"
    curl --fail --location --progress-bar -o "$MODEL_TEMP" "$MODEL_URL"
    verify_sha256 "$MODEL_TEMP" "$MODEL_SHA256"
    mv "$MODEL_TEMP" "$MODEL_PATH"
    echo "Model downloaded and verified."
fi

echo ""
echo "====== Setup Complete ======"
echo ""
echo "Run the app:"
echo "  ./run.sh"
echo ""
echo "Or manually:"
echo "  cd Parrocchettami && PARROCCHETTAMI_HOME=\"$SCRIPT_DIR\" swift run"
echo ""
