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

Commercial RTP / other games' `www/img` may be junctioned as `mv_img/` **on your machine only**.

## Run

Godot 4.7+. Open this folder, play `scenes/login.tscn`. Without a local content root, chrome/tiles soft-miss (placeholders).
