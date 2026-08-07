BOXED ARP — GitHub macOS build
==============================

This repository is configured so GitHub Actions builds the macOS AUv3 MIDI plug-in for Logic Pro.

WHAT THE BUILD PRODUCES
- BOXED ARP.app
- Embedded BoxedArpAU.appex Audio Unit
- Component identity: aumi / BARP / OPTC
- INSTALL.command helper

PLUGIN FEATURES IN THIS BUILD
- Up / Down / Up-Down / Random
- 1/4, 1/8, 1/8T, 1/16, 1/16T, 1/32, 1/32T, 1/64, 1/64T
- 1–4 octaves
- Gate
- Swing
- Latch
- Host sync / free BPM
- Scale lock
- Chromatic, Major, Minor, Dorian, Lydian, Hirajoshi, Bhairav, Todi, Marwa, Malkauns, Hamsadhwani, Charukeshi
- Native BOXED ARP control UI
- Logic-visible automatable AU parameters

BUILD ON GITHUB
1. Create a GitHub repository.
2. Upload every file and folder from this package, including the hidden .github folder.
3. Commit to main.
4. Open the Actions tab.
5. Select "Build BOXED ARP for Logic".
6. Run the workflow if it did not start automatically.
7. When it finishes, download the artifact named "BOXED-ARP-Logic-MIDI-FX".
8. Unzip it on the Mac.
9. Double-click INSTALL.command, or drag BOXED ARP.app into your Applications folder and open it once.
10. Restart Logic Pro.

IN LOGIC
Create a Software Instrument track. In the MIDI FX slot, look under Audio Units / OPTC for BOXED ARP. Put your synth or sampler after the MIDI FX and hold a chord.

NOTE ABOUT SIGNING
The GitHub build is ad-hoc signed for personal testing. It is not a notarized commercial release. macOS may ask you to confirm opening an app downloaded from the internet.

If the GitHub Action fails, open the failed Build Release step and copy the first red compiler error. That is enough to patch the project without starting over.
