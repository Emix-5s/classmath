# Add Synth Purge to the chat room

## Build
- Add the uploaded Synth Purge HTML game as a self-contained app asset.
- Bundle its Three.js dependency locally so gameplay does not rely on an outside script.
- Add Chat and Synth Purge tabs to the center room panel.
- Load the game only when opened, with a large playable frame and a full-screen option.
- Keep the game's credits and progress separate from Nexus coins; no extra backend usage.

## Validation
- Check the app loads without errors.
- Open the game from the room, start a run, and verify desktop and mobile-sized layouts.
