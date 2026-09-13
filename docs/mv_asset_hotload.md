# MV asset hot-load / 苍蓝星外部图根

English / 中文 brief. **Never copy 苍蓝星 PNGs into `res://`.**

## Layout

| Role | Path |
|------|------|
| Content root | `D:/code/rmmo_runtime` (Luna) or `/workspace/rmmo_runtime` (box) |
| MV img root | `{content_root}/mv_img` → junction to `…/苍蓝星…/www/img` |
| Charsets | `mv_img/characters/*.png` |
| Tilesets | `mv_img/tilesets/*.png` |

Luna junction example:

```text
D:/code/rmmo_runtime/mv_img  →  D:/Games/<魔法少女苍蓝星v50.5>/www/img
```

## Settings (`project.godot` / ProjectSettings)

- `rmmo/content_root` — runtime root (optional; auto Luna/Linux paths).
- `rmmo/charset_root` — legacy charset folder (still used; e.g. `D:/code/rmmo_runtime/characters`).
- `rmmo/mv_img_root` — force MV `www/img` root if not using `{content_root}/mv_img`.

Discovery order for `AssetManager.mv_img_root()`:

1. `rmmo/mv_img_root` if set  
2. `{content_root}/mv_img` if directory exists (junction)  
3. Windows scan `D:/Games/*v50.5*/www/img`  
4. Linux mock `/workspace/rmmo_runtime/mv_img`

## Resolve order

**Charset** (`content://charset/{id}`):  
`assets/charset` → `content_root/characters` → `charset_root` → **`mv_img/characters`** → exe `data/characters` → legacy.

**Tilesheet** (`content://tilesheet/{name}`):  
`assets/tilesheet` → **`mv_img/tilesets`**.

`tilemap_pack` loads `pack/tiles/{name}.png` first; if missing, falls back to `content://tilesheet/{name}` (MV hot-load). Soft-miss → null / placeholder as before.

## Playtest (Luna)

1. Ensure junction `rmmo_runtime/mv_img` exists and lists `characters/` + `tilesets/`.  
2. Run game, enter demo map — tiles should blit even without `res://demo_map/tiles`.  
3. Optional NPC: set `charset` in `npcs.json` to any sheet name present under `mv_img/characters` (missing → soft placeholder, headless safe).

## Test

```bash
timeout 45 stdbuf -oL -eL godot --headless --path /workspace/rmmo -s tools/test_mv_hotload.gd
```

---

苍蓝星图只从外部 `mv_img` 热加载，禁止拷进工程树。缺失 charset/tilesheet 走既有占位软失败。
