#!/bin/bash
# Assemble portable Tesseract OCR for bundling with the Electron app.
# Run this once before building the installer.
# Supports both macOS (Homebrew) and Windows.
set -euo pipefail

DEST_DIR="$(cd "$(dirname "$0")" && pwd)/tesseract-portable"
mkdir -p "$DEST_DIR/tessdata"

if [[ "$OSTYPE" == darwin* ]]; then
  # --- macOS: Bundle Homebrew tesseract binary + dylibs ---
  TESSERACT_BIN=$(which tesseract 2>/dev/null || echo "")

  if [ -z "$TESSERACT_BIN" ]; then
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

  # Copy the actual binary (not a symlink)
  cp -v "$TESSERACT_BIN" "$DEST_DIR/tesseract"

  # Homebrew library search paths for resolving @rpath references
  BREW_LIB_DIRS=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
  LIB_SEARCH_DIRS=(
    "$BREW_LIB_DIRS/lib"
    "$BREW_LIB_DIRS/opt/tesseract/lib"
    "$BREW_LIB_DIRS/opt/leptonica/lib"
    "$BREW_LIB_DIRS/opt/libarchive/lib"
    "$BREW_LIB_DIRS/opt/libpng/lib"
    "$BREW_LIB_DIRS/opt/jpeg-turbo/lib"
    "$BREW_LIB_DIRS/opt/giflib/lib"
    "$BREW_LIB_DIRS/opt/libtiff/lib"
    "$BREW_LIB_DIRS/opt/webp/lib"
    "$BREW_LIB_DIRS/opt/openjpeg/lib"
    "$BREW_LIB_DIRS/opt/xz/lib"
    "$BREW_LIB_DIRS/opt/zstd/lib"
    "$BREW_LIB_DIRS/opt/lz4/lib"
    "$BREW_LIB_DIRS/opt/libb2/lib"
  )

  # Recursively collect and copy all non-system dylibs
  collect_and_copy() {
    local binary="$1"
    otool -L "$binary" 2>/dev/null | grep -v '/usr/lib/' | grep -v '/System/' | while read -r line; do
      # Extract the library path (handle both absolute and @rpath/@loader_path)
      libpath=$(echo "$line" | awk '{print $1}')
      libname=$(basename "$libpath")

      # Skip if already in bundle
      [ -f "$DEST_DIR/$libname" ] && continue

      # If @rpath or @loader_path, resolve by searching Homebrew lib dirs
      if [[ "$libpath" == @rpath/* ]] || [[ "$libpath" == @loader_path/* ]]; then
        for dir in "${LIB_SEARCH_DIRS[@]}"; do
          if [ -f "$dir/$libname" ]; then
            cp -v "$dir/$libname" "$DEST_DIR/$libname"
            collect_and_copy "$DEST_DIR/$libname"
            break
          fi
        done
      else
        # Absolute path - copy directly
        if [ -f "$libpath" ]; then
          cp -v "$libpath" "$DEST_DIR/$libname"
          collect_and_copy "$DEST_DIR/$libname"
        fi
      fi
    done
  }

  echo ""
  echo "Bundling dylibs..."
  collect_and_copy "$DEST_DIR/tesseract"

  # Fix ALL non-system library references to use @executable_path
  echo ""
  echo "Fixing library paths (@executable_path)..."
  for binary in "$DEST_DIR/tesseract" "$DEST_DIR"/*.dylib; do
    [ -f "$binary" ] || continue
    # Process both absolute paths and @rpath/@loader_path references
    otool -L "$binary" 2>/dev/null | grep -v '/usr/lib/' | grep -v '/System/' | while read -r line; do
      old_ref=$(echo "$line" | awk '{print $1}')
      # Skip self-references (e.g. libfoo.dylib -> /opt/.../libfoo.dylib)
      if basename "$old_ref" == "$(basename "$binary")" && [[ "$old_ref" != @rpath/* ]] && [[ "$old_ref" != @loader_path/* ]]; then
        install_name_tool -id "@executable_path/$(basename "$binary")" "$binary" 2>/dev/null || true
      fi
      libname=$(basename "$old_ref")
      # Change to @executable_path
      install_name_tool -change "$old_ref" "@executable_path/$libname" "$binary" 2>/dev/null || true
    done
  done

  # Ad-hoc sign all binaries
  echo ""
  echo "Code signing..."
  for f in "$DEST_DIR/tesseract" "$DEST_DIR"/*.dylib; do
    [ -f "$f" ] || continue
    codesign --force -s - "$f" 2>/dev/null || true
  done

  # Copy tessdata from Homebrew location
  BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
  TESSDATA_DIR="$BREW_PREFIX/share/tessdata"

  if [ -d "$TESSDATA_DIR" ]; then
    echo ""
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
ls -la "$DEST_DIR/tesseract" "$DEST_DIR"/*.dylib 2>/dev/null
echo "Tessdata files: $(ls "$DEST_DIR/tessdata/" | wc -l | tr -d ' ')"
