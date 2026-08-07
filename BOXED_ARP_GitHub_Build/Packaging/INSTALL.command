#!/bin/bash
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/BOXED ARP.app"
DEST="$HOME/Applications/BOXED ARP.app"

if [ ! -d "$APP" ]; then
  echo "BOXED ARP.app is missing from this folder."
  read -r -p "Press Return to close..."
  exit 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
/usr/bin/ditto "$APP" "$DEST"
/usr/bin/codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

APPEX="$DEST/Contents/PlugIns/BoxedArpAU.appex"
if [ -d "$APPEX" ]; then
  /usr/bin/pluginkit -a "$APPEX" >/dev/null 2>&1 || true
fi

killall -9 AudioComponentRegistrar >/dev/null 2>&1 || true
open "$DEST"

echo
echo "BOXED ARP was copied to $DEST"
echo "Open Logic Pro and look under MIDI FX > Audio Units > OPTC > BOXED ARP."
read -r -p "Press Return to close..."
