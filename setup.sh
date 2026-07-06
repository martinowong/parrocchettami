#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
MODELS_DIR="$SCRIPT_DIR/models"

PARAKEET_VERSION="v0.3.2"
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
    BINARY_SHA256="665cc533f504e3ee1b887a42492176ce0aecdd38f692f5bbaefcab669471c035"
elif [ "$ARCH" = "x86_64" ]; then
    BINARY_ARCHIVE="parakeet-$PARAKEET_VERSION-bin-macos-cpu-x64.tar.gz"
    BINARY_SHA256="04ff73ed21b29bb9e05c5475c42128a523c399e084de312219b9fce1f6f4e179"
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
if [ -f "$CLI_PATH" ] && [ -x "$CLI_PATH" ]; then
    echo "parakeet-cli already installed. Skipping."
else
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
    echo "parakeet-cli installed."
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
