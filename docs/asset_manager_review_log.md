# AssetManager review log

Date: 2026-09-08 (Asia/Shanghai). Three sequential review+fix passes after P1/P1b implementation.
No Luna sync (user accepts tonight).

---

## Review 1 — Logic completeness (vs `asset_manager_design.md`)

**Checked:** Gate vs Stream split, `ensure_many` + `gate_progress`, queue priorities / dedupe, `prefetch_allowed`, budget + LRU stubs, `content://` parse, no `ResourceLoader` for UGC images, AOI `note_actor_ring` stub.

**Findings:**
1. Design API `load_json(content_ref_or_path)` missing — only `load_json_file`.
2. No `clear_cache()` alias (image + json).
3. Prefetch throttle existed, but LOW queue was uncapped (design: cap ~8).
4. Gate needed soft-miss for charset/look while HTTP download still stubbed (else Loading hard-fails without D:/ runtime).

**Fixes:**
- Added `load_json` (content ref → path → JSON; map_pack → pack.json). Never uses ResourceLoader.
- Added `clear_cache()` + kept `clear_image_cache` / LRU `evict_lru_if_needed`.
- Soft-optional charset/look/icon misses in `ensure_many` (map pack remains hard).
- Confirmed Image path uses `Image.load` only for UGC.

---

## Review 2 — Integration

**Checked:** `project.godot` autoload, `loading_screen.gd`, `charset_sheet.gd`, `npc_actor.gd`, `world.gd`, `map_field.gd`, pack.json deps, MockServer spawn, events/equip/shop untouched.

**Findings:**
1. Loading used a lambda for `gate_progress` — fragile connect/disconnect.
2. MockServer spawn/transfer did not surface `content_id` / `content_version` from pack.json (Loading/World could not prefer content ids).
3. `charset_sheet.build_sprite_frames` re-tried missing AM paths and spammed errors when PNG absent.
4. World transfer handoff did not copy `content_id` into session spawn.

**Fixes:**
- Loading: member `_on_gate_progress`; resource phase 5–35%, bake 35–95%; enter fail → character select; transfer fail → stay with error.
- MockServer `_load_pack` reads pack `content_id`/`version`; spawn + transfer payloads include them.
- World transfer copies `content_id`/`content_version`; enter resolves pack via AssetManager.
- CharsetSheet prefers AssetManager; legacy roots remain for headless without autoload.
- NpcActor: missing frames → enqueue HIGH + letter placeholder + `note_actor_ring(VIEW)`.
- `demo_map` / `bath_map` / `street_map` pack.json: `content_id`, `version`, `deps` (charset list).

**Regression:** `test_events`, `test_authority`, `test_equipment`, `test_quest_journal`, path/void/npc tests still PASS.

---

## Review 3 — Edge cases

**Checked:** missing AssetManager autoload; missing PNG; empty deps; transfer loading; headless without D:/; double ensure; queue dedupe.

**Findings:**
1. Headless Linux has no `D:/code/rmmo_runtime/characters` — Gate must soft-miss charsets; tests must skip PNG asserts.
2. Prefetch LOW could grow without bound under spam enqueue.
3. Double `ensure` / re-entrancy needed a guard (`_ensuring`).
4. Loading without autoload must not crash (legacy bake path).

**Fixes:**
- `ensure` re-entrancy guard; double ensure OK in tests.
- Enqueue dedupe + priority bump; LOW prefetch cap 8.
- `ensure_many([])` → OK; missing pack deps → empty/partial array, no crash.
- CharsetSheet / Loading / NpcActor all fall back when AssetManager null.
- Missing PNG: ensure returns ERR_FILE_NOT_FOUND; placeholder frames; quiet resolve when file absent.
- `tools/test_asset_manager.gd` covers parse, resolve, ensure_many empty, enqueue/pump, budget, rings, collect_map_pack_deps, placeholders — **ALL PASS**.

---

## Done snapshot

| Item | Status |
|---|---|
| Autoload `AssetManager` | Registered |
| Loading resource phase | 5–35% ensure_many + Chinese labels |
| Charset via Manager + fallback | Yes |
| Stream enqueue + placeholder | NpcActor |
| `test_asset_manager` | PASS |
| Prior tests | No bad regressions |
| Luna sync | **Not done** (per user) |

## Acceptance fix (2026-09-08 evening)

- Bug: Loading showed `地图包缺失: street_central` because `content_id` aliases only covered folder names (`street_map`), not pack.json ids (`street_central` / `bath_home`).
- Fix: map `street_central`→`res://street_map`, `bath_home`→`res://bath_map`; scan known project packs by `content_id`; Loading/World fall back to `spawn.pack_path` if id resolve misses.


---

## P2c — Actor AOI preload rings (2026-09-09)

**Implemented (shell only; no new art / packs / progress persistence):**

- `AssetManager`: `bind_actor_refs` / `clear_actor_refs`, enriched `note_actor_ring` (PREFETCH→COLD cancels unstarted LOW; COLD/leave-AOI marks refs evictable with ~7s hysteresis; VIEW/AOI clears mark), `set_interest(view, aoi, prefetch)`, `cancel_actor_low_jobs`, LRU skips VIEW-protected paths and prefers COLD/evictable.
- `scripts/asset/aoi_driver.gd`: Chebyshev cell distance; defaults **view=14 / aoi=22 / prefetch=30**; World ticks ~0.25s or on player cell change; only existing `_npcs`.
- `NpcActor`: no longer forces VIEW + HIGH enqueue on setup — placeholder only; World AOI owns enqueue priority.
- Map chunk streaming (P2d) **out of scope**.
- Tests: `tools/test_aoi_rings.gd` + smoke in `test_asset_manager.gd`.
- Luna sync: **not done** (coordinator).
