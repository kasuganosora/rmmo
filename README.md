# rmmo

Godot 4 client + in-process mock server for a tile MMORPG. **This repository is code only.**

Art, audio, fonts, and packs live in an **external content root** (not in git, not in the Godot PCK). See `NOTICE.md`.

## License

MIT for the source in this repo. Third-party art is **not** included and must not be pushed to GitHub.

## Content root

Set `rmmo/content_root` in `project.godot` (or let `AssetManager` fall back to `D:/code/rmmo_runtime` on Windows). Layout:

- `content.json` — start/street pack ids, aliases, spawn cells
- `packs/ui/default/<ver>/` — UI chrome (`content://ui/…`)
- `packs/map_pack/<id>/<ver>/` — map packs
- `data/combat`, `data/map`, `data/rtp` — catalogs (`content://data/…`)
- `assets/fx`, `assets/icon`, `assets/tilesheet`, `assets/charset`, …

The MV image library is a local copy at `{content_root}/packs/mv_img`. Keep it out of git and out of `res://`.

## Run

Use the project's patched **Godot 4.8 beta1** build. On this Windows workstation the default editor/debug executable is `D:/tools/godot/godot.windows.editor.x86_64.exe`; matching debug symbols and the SHA manifest live beside it. Build/patch details and remaining optimization work are recorded in [the 4.8 migration log](docs/godot_4_8_adoption_20261029.md). Godot 4.7 is no longer an active compatibility target.

Open this folder, play `scenes/login.tscn`. Without a local content root, chrome/tiles soft-miss (placeholders). Native texture streaming is enabled with a 512 MiB streaming-texture budget; this is a mip residency budget, not a limit on total GPU memory or imported assets. Other resource budgets remain separate.
