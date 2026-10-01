# AI tileset acceptance

> Historical 2D workflow, retired on 2026-10-01. Its source remains, but these tools are no longer registered or served. Use [the current 3D editor MCP](world_editor_mcp.md) for active editor operations; the commands below are retained for reference.

The content editor MCP can validate and render MV assets without changing the
current map. Keep technical acceptance separate from image review: dimensions
and file hashes cannot establish that an illustration matches an art reference.

## Repeatable run

Create a JSON manifest mapping every expected sheet name to its SHA256. Then run:

```powershell
python tools/accept_tileset_mcp.py --tileset outside --expected expected_sha256.json --out evidence
```

The default endpoint is `http://127.0.0.1:18765/mcp`; override with `--url`.
The runner refreshes assets, checks resolved paths, hashes, image cache identity,
MV dimensions and transparent B0, then saves native 48px fixture PNGs and RPC
results. It checks the hashes again afterwards and verifies editor state did
not change. A run starts with `technical_passed: false`, so a failed rerun cannot
leave an earlier green acceptance result. No current pack is saved.

## MCP operations

- `audit_tileset`: optional `tileset_id`, `expected_sha256` object. Returns
  `technical_passed`, per-sheet `path`, `sha256`, `errors`. Missing expected
  declarations, unreadable/wrong-size sheets, opaque B0, stale cached images and
  unexpected versions fail technical acceptance.
- `preview_autotile_cases`: `kinds` (1–8 integers, 0–127), optional `frame`
  (0–3), `tileset_id`, `path`, `max_px`. Uses the project's actual `TileBlit`
  and `TileId`, with island, concave hole, L, one-cell cross and every legal
  shape. Each material occupies a 288px-high row. The first four fixtures are
  five tiles wide each; the remaining eight columns contain shape samples.
  Waterfalls have four legal shapes, walls sixteen, floors forty-eight.
- `reload_tilesheets`: clears asset/minimap caches and refreshes palette plus
  current map field. Minimap colors are keyed by source-image identity, tile ID
  and flag, avoiding stale colors when changing tilesets.
- `preview_map`: set `grid:false`, `entities:false`, `cursor:false` for clean
  in-game evidence. `overview:true` is a low-detail overview and must not be
  used to certify native-pixel seams.
- `preview_sheet_rect`: reads the AssetManager-resolved file and reports
  `resolved_path`; negative row/column indices are rejected.

## AI review and repair loop

After technical success, the agent must inspect the saved PNGs and the user's
reference artwork. Check palette, pixel density, detail, redesigned silhouettes,
object meaning and multi-cell placement; then inspect convex/concave corners,
narrow paths, roofs, snow, water and waterfall phases at native resolution.
Inspect B/C and a composed scene too: autotile fixtures alone miss object-slot
errors. When layout preservation is required, compare the original and new
48px occupancy maps in both directions and keep the terrain alpha masks.

Record image evidence paths/hashes, findings, fixes and the exact reviewed
asset manifest in a separate visual review. Never convert technical success
alone to overall visual approval. Repair failures, rebuild and repeat the
affected checks; invalidate visual review when asset hashes change.

## Regression tests

Run `tools/test_tileset_qa.gd`, `tools/test_editor_mcp_ops.gd`,
`tools/test_autotile_paint.gd` and `tools/test_tile_anim.gd` with Godot headless.
QA tests cover bad dimensions, B0, missing declarations, invalid fixture input,
animation, map preservation, cache separation and owner lifetime. Module owner
links use `WeakRef` to avoid controller/module reference cycles. Combat module
lifetime shares this fix; cast, status/AoE, DPS, skill-targeting and hit/crit
tests cover those paths.
