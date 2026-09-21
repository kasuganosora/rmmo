# NOTICE — what this repository does and does not ship

This GitHub repository is **source code only** (MIT). It does **not** include
game art, audio, fonts, JSON catalogs, or content packs.

## Do not commit

| Location | Why |
|----------|-----|
| `{content_root}/` (e.g. `D:/code/rmmo_runtime`) | External runtime. Packs, tilesheets, UI chrome, catalogs. |
| `packs/` | Map / UI packs |
| `data/` | Combat / map / RTP JSON (`content://data/…`) |
| `assets/` | Local art (gitignored) |
| RPG Maker MV RTP images | Kadokawa / Degica license — user must own MV |
| 苍蓝星 / other commercial `www/img` | Commercial game art — hot-load from a local install only |
| Third-party UI kits (IndigoLay, L2-inspired chrome, fonts) | Redistribution of those files is not allowed by their licenses |

`.gitignore` already excludes images, audio, fonts, `rmmo_runtime/`, and `packs/`.

## Included (code / data, not artwork)

- Engine scripts, scenes, shaders. Playtest maps live in `{content_root}/packs/map_pack/` (not in git).
- RTP **tables** live at `{content_root}/data/rtp/` (not in git). **No RTP PNGs** in this repo.
- `icon.svg` — Godot project icon (Godot is MIT).
- `addons/godot_ai/` — MIT (see that addon's `LICENSE`).

## Runtime layout (local, not GitHub)

```
{content_root}/
  content.json                       — start/street packs, aliases, spawn cells
  packs/map_pack/<id>/<version>/
  packs/ui/default/<version>/
  data/combat, data/map, data/rtp     — catalogs (`content://data/…`)
  assets/fx, icon, tilesheet, charset, audio, look, system
  mv_img/          optional junction to an MV www/img you own
```

Address content with `content://…` refs. Never copy third-party PNGs into `res://`.
