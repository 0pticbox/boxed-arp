# BOXED ARP — GarageBand + Logic Universal Build

One macOS host app containing **two AUv3 plug-ins**:

1. **BOXED ARP Instrument** (`aumu / BARP / OPTC`) — for GarageBand and Logic.
2. **BOXED ARP MIDI FX** (`aumi / BARP / OPTC`) — for Logic's MIDI FX slot.

## Instrument version

The GarageBand/Logic instrument is the full BOXED ARP synth build:

- dual saw / square / sine oscillators
- oscillator blend and detune
- ADSR envelope
- resonant low-pass filter
- Up / Down / Up-Down / Random arpeggiator
- SYNC and FREE arp timing
- 1/4 through 1/64T divisions
- 1–4 octave expansion
- gate, swing, latch, Play/Stop
- built-in chords
- large world/microtonal scale bank
- analog delay
- generated MIDI output
- MIDI capture and `.mid` export
- presets and multiple CRT/pixel skins
- automatable Audio Unit parameters
- horizontal 720 × 340 interface

## Logic MIDI FX version

The MIDI processor can be placed before any Logic software instrument and provides:

- Up / Down / Up-Down / Random
- 1/4 through 1/64T
- 1–4 octaves
- gate, swing and latch
- project tempo sync or free BPM
- scale locking with western and world-scale choices
- native AU parameter automation

## Build with GitHub Actions

Upload the contents of this folder to the root of your GitHub repo. The workflow must be at:

`.github/workflows/build-macos.yml`

Then open **Actions → Build BOXED ARP for GarageBand + Logic** and run the workflow on `main`.

A successful run uploads this artifact:

`BOXED-ARP-GarageBand-Logic`

Inside is `BOXED_ARP_GarageBand_Logic.zip` containing `BOXED ARP.app` and `INSTALL.command`.

## Install

1. Unzip the GitHub artifact.
2. Unzip `BOXED_ARP_GarageBand_Logic.zip` if GitHub did not already expose its contents.
3. Double-click `INSTALL.command`.
4. If macOS blocks an ad-hoc GitHub build, Control-click the installer/app and choose **Open**.
5. Quit and reopen GarageBand and Logic after installation.

### GarageBand

Create a **Software Instrument** track and look for:

`AU Instruments → OPTC → BOXED ARP`

### Logic Pro — instrument

Load:

`AU Instruments → OPTC → BOXED ARP`

### Logic Pro — MIDI processor

Load:

`MIDI FX → Audio Units → OPTC → BOXED ARP`

## Source layout

- `BoxedArpInstrumentAU/` — GarageBand + Logic instrument
- `BoxedArpMIDIAU/` — Logic MIDI processor
- `App/` — small containing/registration app
- `Packaging/` — installer helper
- `Tests/` — MIDI-engine smoke test
- `project.yml` — XcodeGen project spec
- `.github/workflows/build-macos.yml` — macOS/Xcode cloud build

The GitHub artifact is ad-hoc signed for personal testing, not Developer-ID notarized for public distribution.
