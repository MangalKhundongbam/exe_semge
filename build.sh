#!/bin/bash
set -e

# Force system Python - bypass conda entirely
PYTHON=/usr/bin/python3
PIP="$PYTHON -m pip"
PYINSTALLER="$PYTHON -m PyInstaller"

echo "🔍 Verifying environment..."
$PYTHON --version
$PYTHON -c "import sys; print('Python path:', sys.executable)"

echo "🚀 Step 1: Installing all dependencies..."
$PIP install --break-system-packages \
  pyinstaller \
  staticx \
  setuptools \
  uvicorn \
  fastapi \
  starlette \
  python-multipart \
  pymupdf \
  pillow \
  python-docx \
  python-jose \
  tinydb \
  pytesseract \
  pdf2image

echo "🔍 Verifying key imports..."
$PYTHON -c "import uvicorn; print('uvicorn OK:', uvicorn.__file__)"
$PYTHON -c "import fastapi; print('fastapi OK:', fastapi.__file__)"
$PYTHON -c "import fitz; print('pymupdf OK:', fitz.__file__)"
$PYTHON -c "import PIL; print('pillow OK:', PIL.__file__)"

echo "📁 Step 2: Preparing Tesseract data locally..."
mkdir -p tessdata
cp -r /usr/share/tesseract-ocr/5/tessdata/* ./tessdata/

echo "🔧 Step 3: Patching PyMuPDF and Pillow .so files for StaticX..."

export SITE_PACKAGES=$($PYTHON -c "import site; print(site.getusersitepackages())")
echo "Site packages: $SITE_PACKAGES"

SO_FILES=$(find "$SITE_PACKAGES" -type f -name "*.so*" \
  \( -path "*/pymupdf*" -o -path "*/fitz*" -o -path "*/pillow*" -o -path "*/Pillow*" -o -path "*/PIL*" \) \
  ! -name "*.bak" 2>/dev/null)

echo "Found .so files to patch:"
echo "$SO_FILES"

echo "$SO_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  cp "$f" "$f.bak"
  echo "  Patching: $f"
  patchelf --remove-rpath "$f" || echo "  ⚠️  patchelf failed on $f (skipping)"
done

PYMUPDF_DIR=$(find "$SITE_PACKAGES" -type d -name "pymupdf" | head -n 1)
PILLOW_LIBS=$(find "$SITE_PACKAGES" -type d -iname "pillow.libs" | head -n 1)
export LD_LIBRARY_PATH="${PYMUPDF_DIR:+$PYMUPDF_DIR:}${PILLOW_LIBS:+$PILLOW_LIBS:}$LD_LIBRARY_PATH"

echo "📦 Step 4: Building dynamic executable with PyInstaller..."
$PYINSTALLER --onefile \
  --collect-all uvicorn \
  --collect-all fastapi \
  --collect-all starlette \
  --collect-all docx \
  --collect-all fitz \
  --collect-all jose \
  --collect-all tinydb \
  --collect-all pdf2image \
  --hidden-import "uvicorn.logging" \
  --hidden-import "uvicorn.loops" \
  --hidden-import "uvicorn.loops.auto" \
  --hidden-import "uvicorn.protocols" \
  --hidden-import "uvicorn.protocols.http.auto" \
  --hidden-import "uvicorn.protocols.websockets.auto" \
  --hidden-import "uvicorn.lifespan.on" \
  --hidden-import "uvicorn.lifespan.off" \
  --hidden-import "multipart" \
  --hidden-import "python_multipart" \
  --add-data "templates:templates" \
  --add-data "static:static" \
  --add-data "tessdata:tessdata" \
  --add-binary "/usr/bin/tesseract:bin" \
  --add-binary "/usr/bin/pdftoppm:bin" \
  --add-binary "/usr/bin/pdftocairo:bin" \
  --add-binary "/usr/bin/pdfinfo:bin" \
  main.py

echo "🛡️ Step 5: Compiling to fully static binary with StaticX..."
$PYTHON -m staticx dist/main dist/DocuSearch_Backend

echo "🩹 Step 6: Restoring original libraries..."
find "$SITE_PACKAGES" -type f -name "*.so.bak" \
  \( -path "*/pymupdf*" -o -path "*/fitz*" -o -path "*/pillow*" -o -path "*/Pillow*" -o -path "*/PIL*" \) \
  -exec bash -c 'mv "$1" "${1%.bak}"' _ {} \;
echo "    Restore complete."

echo "✅ Build Complete! Your portable app is at: dist/DocuSearch_Backend"