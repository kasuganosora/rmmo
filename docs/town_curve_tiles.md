# Editable curved terrain pages

MV A1–A5/B–E tile IDs and quarter-tile rules remain unchanged. A tileset may additionally declare `extraSheets`, up to 64 pack-local 768×768 RGBA pages. Extended IDs start at 16384, with 256 tiles per page and the same two 8×16 blocks used by B–E sheets. They are normal tiles, never autotiles. Existing packs without this field retain their behavior.

The content editor, runtime loader, CPU tile renderer, minimap/baked overview, sheet audit, eyedropper, stamps, passage flags and palette support these pages. The palette's extra-page dropdown exposes them for manual editing. `configure_tileset` configures the nine MV slots plus optional pages and passage flags through MCP. `paint_cells` and named stamps then paint them like other tiles.

Curves are authored from shared spline geometry and sliced into native 48px tiles; boundaries use 2px pixel-art steps, rather than 48px stair steps. A common global mask makes adjacent pieces agree. The map still contains editable tile IDs and separate collision metadata, not a single flattened background image. Baked curve pieces must be regenerated from source control points when changing the overall route; ordinary buildings remain reusable named stamps.

`preview_map` accepts explicit `cell_px` for full previews up to 256×256 cells, bounded to 16 megapixels. Sheet copies are resized consistently, so reduced-density previews sample the correct source regions. Omitting `cell_px` retains the existing bounded chunk preview.

Validation:

- `tools/test_editor_mcp.gd`: preview density and native/downscaled pixel agreement.
- `tools/test_editor_mcp_ops.gd`: tileset configuration validation and existing editor operations.
- `tools/test_town_curves.gd`: actual saved Axel map, every curve tile blit, collision and entrance reachability. This integration test requires the external town assets.
- This integration test also compares every saved object-layer cell and collision metadata cell to the source plan, verifies separate wall body/crown layers and low crop flags, and checks each bridge locally connects its two banks.
- `tools/test_playtest_pack_path.gd`: editor draft paths take precedence over same-ID installed releases, preventing loading the wrong map during playtest.
- `tools/test_chunk_priority.gd`: teleporting drops stale queued regions and loads the current camera chunk before distant prefetch. Live visual acceptance waits for HD chunks rather than capturing the low-resolution placeholder.

Town revision: wall body and bridge deck occupy z2, wall crown z3 with upper-display flags. Shared ground/yard/road pixels are composed together in z0 so river-bank transparency in z1 cannot erase roads. Named stamps retain their saved layer; an explicit paint tile ID replaces a prior multi-cell brush, including metadata clears.

Current town source workspace: `D:/code/rmmo_runtime/style_work/town_m`. Main scripts: `layout.py`, `assets.py`, `guild_asset.py`, `street_assets.py`, `compose.py`, `curves.py`, `paint_town.py`, `acceptance.py`. Generated art stays outside the code repository.
