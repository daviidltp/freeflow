#!/bin/bash
# Compila FreeFlow desde el código fuente e instala la app en /Applications.
# Al compilarla en tu propio Mac, macOS no la bloquea (no hace falta firmarla ni notarizarla).
set -euo pipefail

cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Faltan las herramientas de desarrollo de Apple. Instálalas con:  xcode-select --install"
    exit 1
fi

APP_NAME="FreeFlow"
BUNDLE_ID="com.zachlatta.freeflow"
DEST="/Applications/$APP_NAME.app"

echo "Compilando $APP_NAME para $(uname -m)..."
make clean >/dev/null
make ARCH="$(uname -m)" APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" CODESIGN_IDENTITY=-

osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true

echo "Instalando en $DEST..."
rm -rf "$DEST"
cp -R "build/$APP_NAME.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Listo. Abriendo $APP_NAME..."
open "$DEST"
