# MV image library

English / 中文 brief. The image library lives in the content pack. **Never copy these PNGs into `res://`.**

## Layout

| Role | Path |
|------|------|
| Content root | `D:/code/rmmo_runtime` (Luna) or `/workspace/rmmo_runtime` (box) |
| MV img root | `{content_root}/packs/mv_img` |
| Charsets | `packs/mv_img/characters/*.png` |
| Tilesets | `packs/mv_img/tilesets/*.png` |

## Settings (`project.godot` / ProjectSettings)

- `rmmo/content_root` — runtime root (optional; auto Luna/Linux paths).
- `rmmo/charset_root` — legacy charset folder (still used; e.g. `D:/code/rmmo_runtime/characters`).
- `rmmo/mv_img_root` — force the image root if not using `{content_root}/packs/mv_img`.

Discovery order for `AssetManager.mv_img_root()`:

1. `rmmo/mv_img_root` if set
2. `{content_root}/packs/mv_img` if that directory exists
3. Linux pack `/workspace/rmmo_runtime/packs/mv_img`
4. Legacy Linux fixture `/workspace/rmmo_runtime/mv_img`

## Resolve order

**Charset** (`content://charset/{id}`):
`assets/charset` → `content_root/characters` → `charset_root` → **`packs/mv_img/characters`** → exe `data/characters` → legacy.

**Tilesheet** (`content://tilesheet/{name}`):
`assets/tilesheet` → **`packs/mv_img/tilesets`**.

`tilemap_pack` loads `pack/tiles/{name}.png` first; if missing, falls back to `content://tilesheet/{name}`. Soft-miss → null / placeholder as before.

## Test

```bash
timeout 45 stdbuf -oL -eL godot --headless --path /workspace/rmmo -s tools/test_mv_hotload.gd
```

---

图库在内容包 `{content_root}/packs/mv_img`。禁止拷进工程树 `res://`。缺失 charset/tilesheet 走既有占位软失败。
