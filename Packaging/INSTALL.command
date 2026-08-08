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

# GitHub builds are ad-hoc signed. Re-sign after copying in case macOS adjusts metadata.
/usr/bin/codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

MIDI_APPEX="$DEST/Contents/PlugIns/BoxedArpMIDIAU.appex"
INST_APPEX="$DEST/Contents/PlugIns/BoxedArpInstrumentAU.appex"

for APPEX in "$MIDI_APPEX" "$INST_APPEX"; do
  if [ -d "$APPEX" ]; then
    /usr/bin/pluginkit -a "$APPEX" >/dev/null 2>&1 || true
  fi
done

killall -9 AudioComponentRegistrar >/dev/null 2>&1 || true
open "$DEST"

echo
echo "BOXED ARP was copied to:"
echo "  $DEST"
echo
echo "GarageBand: Software Instrument > Plug-ins > AU Instruments > OPTC > BOXED ARP"
echo "Logic instrument: Instrument > AU Instruments > OPTC > BOXED ARP"
echo "Logic MIDI FX: MIDI FX > Audio Units > OPTC > BOXED ARP"
echo
echo "Quit and reopen GarageBand or Logic if either host was already open."
read -r -p "Press Return to close..."
