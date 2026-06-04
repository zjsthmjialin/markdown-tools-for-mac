#!/bin/bash
# Assemble portable Tesseract OCR for bundling with the Electron app.
# Run this once before building the installer.
# Supports both macOS (Homebrew) and Windows.
set -euo pipefail

DEST_DIR="$(cd "$(dirname "$0")" && pwd)/tesseract-portable"
mkdir -p "$DEST_DIR/tessdata"

if [[ "$OSTYPE" == darwin* ]]; then
  # --- macOS: Use Homebrew tesseract ---
  TESSERACT_BIN=$(which tesseract 2>/dev/null || echo "")

  if [ -z "$TESSERACT_BIN" ]; then
    # Try common Homebrew paths directly
    for candidate in /opt/homebrew/bin/tesseract /usr/local/bin/tesseract /usr/bin/tesseract; do
      if [ -f "$candidate" ]; then
        TESSERACT_BIN="$candidate"
        break
      fi
    done
  fi

  if [ -z "$TESSERACT_BIN" ]; then
    echo "ERROR: tesseract not found. Please install via Homebrew:"
    echo "  brew install tesseract"
    echo "  brew install tesseract-lang  # for additional language data"
    exit 1
  fi

  echo "Using Tesseract from: $TESSERACT_BIN"

  # Create a symlink to the tesseract binary
  ln -sf "$TESSERACT_BIN" "$DEST_DIR/tesseract"

  # Copy tessdata from Homebrew location
  BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
  TESSDATA_DIR="$BREW_PREFIX/share/tessdata"

  if [ -d "$TESSDATA_DIR" ]; then
    echo "Copying tessdata from: $TESSDATA_DIR"
    for traineddata in "$TESSDATA_DIR"/*.traineddata; do
      cp -v "$traineddata" "$DEST_DIR/tessdata/" 2>/dev/null || true
    done
  fi

  # Copy pdf.ttf if present
  if [ -f "$TESSDATA_DIR/pdf.ttf" ]; then
    cp -v "$TESSDATA_DIR/pdf.ttf" "$DEST_DIR/tessdata/" 2>/dev/null || true
  fi

else
  # --- Windows: Original logic ---
  TESSERACT_DIR=""
  for candidate in \
    "/c/Program Files/Tesseract-OCR" \
    "/c/Program Files (x86)/Tesseract-OCR" \
    "C:/Program Files/Tesseract-OCR" \
    "C:/Program Files (x86)/Tesseract-OCR"; do
    if [ -f "$candidate/tesseract.exe" ]; then
      TESSERACT_DIR="$candidate"
      break
    fi
  done

  if [ -z "$TESSERACT_DIR" ]; then
    echo "ERROR: Tesseract OCR not found. Please install it first:"
    echo "  https://github.com/UB-Mannheim/tesseract/wiki"
    exit 1
  fi

  echo "Using Tesseract from: $TESSERACT_DIR"

  # --- Copy tesseract.exe ---
  cp -v "$TESSERACT_DIR/tesseract.exe" "$DEST_DIR/"

  # --- Copy all DLLs (exclude .exe training tools to keep size down) ---
  echo "Copying DLLs..."
  copied=0
  for dll in "$TESSERACT_DIR"/*.dll; do
    dll_name="$(basename "$dll")"
    cp -v "$dll" "$DEST_DIR/" 2>/dev/null && ((copied++)) || true
  done
  echo "Copied $copied DLL(s)"

  # --- Copy tessdata ---
  echo "Copying tessdata..."
  for traineddata in "$TESSERACT_DIR/tessdata/"*.traineddata; do
    cp -v "$traineddata" "$DEST_DIR/tessdata/"
  done

  # Copy pdf.ttf (needed by some Tesseract configs)
  if [ -f "$TESSERACT_DIR/tessdata/pdf.ttf" ]; then
    cp -v "$TESSERACT_DIR/tessdata/pdf.ttf" "$DEST_DIR/tessdata/"
  fi
fi

# --- Download chi_sim.traineddata if missing (both platforms) ---
if [ ! -f "$DEST_DIR/tessdata/chi_sim.traineddata" ]; then
  echo "Downloading chi_sim.traineddata (Chinese Simplified)..."
  curl -L -o "$DEST_DIR/tessdata/chi_sim.traineddata" \
    "https://github.com/tesseract-ocr/tessdata_fast/raw/main/chi_sim.traineddata"
  echo "Downloaded chi_sim.traineddata (fast)"
else
  echo "chi_sim.traineddata already present"
fi

# --- Report ---
echo ""
echo "=== Tesseract portable bundle assembled ==="
echo "Location: $DEST_DIR"
echo "Size: $(du -sh "$DEST_DIR" | cut -f1)"
echo "Files:"
ls -la "$DEST_DIR/tesseract" "$DEST_DIR/tessdata/" 2>/dev/null
