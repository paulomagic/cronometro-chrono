#!/bin/bash
cd "$(dirname "$0")" || exit 1
APP="./CHRONO HUD.app"
BIN="./CHRONO HUD.app/Contents/MacOS/CHRONO HUD"

if [ ! -d "$APP" ]; then
  echo "App nao encontrado: $APP"
  exit 1
fi

if [ ! -x "$BIN" ]; then
  echo "Executavel nao encontrado: $BIN"
  exit 1
fi

exec "$BIN"
