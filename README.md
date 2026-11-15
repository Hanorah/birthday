# THE LAST PROMISE — Godot 4.3 project

## Play on a phone (web version)
The ready-to-host web build is in the **web** folder.
1. Go to https://app.netlify.com/drop (free) and drag the whole **web** folder onto the page.
2. Netlify gives you a link. Open it on the phone, turn the phone sideways, and tap New Game.
   (Or deploy the folder with Vercel: `vercel deploy web`.)
Touch controls: left thumb = move, right thumb = look, USE = interact, JUMP / CROUCH / RUN, ☰ journal, II pause.
Tap the screen during cutscenes to skip a line.

## Run it on this PC
- Double-click **Play.bat** (uses the bundled Godot 4.3 in `engine/`), or
- Open the folder in Godot 4.3 (`project.godot`) and press F5.
- Low-end GPU / laptop: use **Play-LowSpec.bat** (compatibility renderer).

## Controls
WASD move · Mouse look · Shift sprint · Alt walk · Space jump · C crouch · E interact
Tab journal · Esc pause · Enter/Space skip dialogue line · Gamepad supported.

## What's built (Milestones 1–3)
- Architecture, autoloads (GameState, Audio, UI), save/load, checkpoints, settings (4 quality presets).
- Main menu (New Game, Continue, Chapters, Settings, Exit), loading screen, pause menu, HUD, subtitles, objectives, journal.
- Third-person controller: walk/jog/sprint, jump, crouch, ladder climbing, smooth collision camera, contextual interaction.
- Chapter One — The Beginning: birth night (16 Nov 1987) cinematic, family, 5th birthday (16 Nov 1992),
  radio-repair activity, hide & seek, birthday candles, the promise, growing-up transition, 6 memory collectibles.
- Placeholder music/SFX (generated). Voice-ready dialogue: `narrative/dialogue_ch1.json`.

## Folders
characters/ environments/ levels/ animations/ audio/ ui/ systems/ ai/ cinematics/ assets/ narrative/ tests/ docs/

## Names
Edit `narrative/story_config.gd` (HERO_NAME is a placeholder: "Daniel").

## Real character models
See docs/ASSETS_NEEDED.md. Drop rigged GLBs at `assets/characters/<id>/<id>_<stage>.glb` and they replace the placeholder figures automatically.

## Tests
`engine\godot.exe --headless --path . res://tests/test_runner.tscn` — automated Chapter One playthrough (37 checks).
