# Acceptance checklist — hate list / evade / LoS / loot / items (2026-09-07)

Use this on Luna after extracting `rmmo_combat_sync.tar.gz`. MockServer is authoritative; client only applies actions.

## Automated (box / headless)

```bash
godot --headless --path /path/to/rmmo -s res://tools/test_acceptance_batch.gd
godot --headless --path /path/to/rmmo -s res://tools/test_mob_ai.gd
godot --headless --path /path/to/rmmo -s res://tools/test_combat_layers.gd
godot --headless --path /path/to/rmmo -s res://tools/test_authority.gd
godot --headless --path /path/to/rmmo -s res://tools/test_loot_confirm.gd
godot --headless --path /path/to/rmmo -s res://tools/test_ground_drops.gd
```

Expect `PASS` on all four.

| Check | Expected |
|-------|----------|
| Hate sticky | Second actor switches only at ≥110% of current victim threat |
| Tank hold | Actor A mod 2.0 smaller raw damage holds; B needs ≥110% applied hate to pull |
| Evade heal | `clear_chase` restores NPC HP to max; clears passive enrage + hate_list |
| `npc_reset` | Emitted on leash / lose-sight evade; client HP bar resets |
| Vision LoS | Wall / void cell on Bresenham ray blocks cone aggro |
| Loot roll | `loot_tables.json` by npc_id / charset; force-roll non-empty |
| Stack inventory | Merge to `stack_max`; soft 20 slots; reject when full |
| Kill loot | Ground bag (`ground_spawn`); open when adjacent; take → `inventory_update` + `获得 xxx×n`; close keeps bag |
| use_item | Hotbar potions still heal via `use_effect` / legacy `effect` |

## Manual (street_map)

1. **Dialogue / warps** — talk to friendlies on demo; warp demo ↔ street; confirm unbroken.
2. **Hotbar use_item** — keys 4/5 potions; inventory click-use; qty decreases; HP/MP rise.
2b. **Bag grid + drag** — open 背包 → letter-avatar grid; drag potion to hotbar → press uses; right-click clears.
2c. **Skills grid + tabs** — open 技能 → 物理/魔法/被动 tabs; letter-avatar; drag skill to hotbar; passive click shows 被动无需施放 (no cast).
2d. **Quest list + side drawer** — open 任务 → tabs 正在进行/已完成 → select row → external side drawer slides out (desc/objectives/rewards); close slides away; list stays.
3. **Hate / chase** — aggro a street hostile; it chases you (`select_victim` / highest hate = you).
4. **Evade full HP** — pull a mob, damage it, then run beyond leash / break vision 5s; mob returns home and HP bar snaps to full (`npc_reset`).
5. **LoS** — stand behind a wall tile inside cone range; mob should **not** aggro until line is clear.
6. **Loot** — kill `street_slime` / pack renegade; ground marker appears (no auto window); walk adjacent + click marker → 掉落确认; 拾取/全部拾取 grants; 关闭 keeps bag on ground.
6b. **Player drop** — open 背包, **right-click** a slot → drops ×1 at feet (`扔下了`); marker updates/merges.
7. **Bag full** — fill ~20 distinct stacks (dev/test), kill again; open bag; expect “背包已满” and item stays on ground / in loot window.
8. **Pack assist** — still works (group_id 2 north of spawn); killing blow wakes allies.
9. **Respawn** — dead hostile returns after `respawn_sec` (~30s) via `spawn_npc`.

## Files to verify present

- `ITEM_DESIGN_RESEARCH.md`, `ACCEPTANCE.md`, `AUTHORITY.md`
- `data/combat/items.json`, `data/combat/loot_tables.json` (+ scripts mirrors)
- `scripts/net/combat/loot_catalog.gd`
- Updated: `inventory.gd`, `item_catalog.gd`, `mob_ai.gd`, `combat_stats.gd`, `combat_engine.gd`, `mock_server.gd`, `world.gd`, `game_hud.gd`
- `scripts/ui/inv_slot.gd`, `scripts/ui/hotbar_slot.gd`, `scripts/ui/skill_slot.gd`
- `data/combat/skills.json` (+ scripts mirror) with `category`
- `data/combat/quests.json` (+ scripts mirror)
- `scripts/net/combat/quest_journal.gd`
- `tools/test_acceptance_batch.gd`


## Inventory UI (grid + hotbar drag)

- Open **背包** → fixed-size window (not resizable); ScrollContainer fills body; 5×10 StyleBoxFlat slot grid (scrollbar; no sub-title/hint labels) from server `inventory_update`.
- Cells fill content width (computed from window width / cols); vertical scroll if rows exceed visible area; empty slots still fill the grid.
- Letter-avatar = first char of display name; qty bottom-right; tooltip name+id.
- Left-click consumable → `request_use_item` / server `try_use_item`.
- Drag bag slot onto hotbar → session binding `{kind:"item", id}`; press slot uses item. Right-click hotbar clears binding.
- No new art assets; bag authority remains server-only.

## Skills UI (grid + tabs + hotbar drag)

- Open **技能** (K) → fixed-size window (not resizable); tab bar 物理 / 魔法 / 被动; ScrollContainer fills body; 5×8 StyleBoxFlat slot grid (scrollbar; no chrome helper labels).
- `skills.json` / skill_catalog `category`: `physical` | `magic` | `passive` (basic_attack/power_strike physical; heal_light magic; tough_skin/keen_eye stub passives).
- Letter-avatar = first char of skill name; drag onto hotbar → `{kind:"skill", id}`; active skills left-click / hotbar → `request_use_skill` / MockServer `try_use_skill`.
- Passive: left-click shows “被动，无需施放” (toggle stub UI-only); hotbar press does not cast; server rejects passive cast.
- No new art assets; skill use authority remains MockServer.


## Quest UI (list + side drawer)

- Open **任务** → fixed-size **list** window (not resizable); tabs **正在进行** / **已完成** filter by journal status (`in_progress`/`ready` vs `completed`).
- Clicking a quest row slides an **external side drawer** out beside the list (HUD sibling, right of quest panel) with desc / objectives cur/max / rewards; X or re-click row slides it away; list window stays.
- Authority: MockServer `quest_journal` + `data/combat/quests.json`; client applies spawn `quests` / `quest_update` only (no `L2Mock.quests_for`).
- List row: title + short status `进行中` / `可交付` / `已完成`. Sample journal includes completed quests for the 已完成 tab.
- No internal horizontal list|drawer split; no chrome helper labels.
- `try_abandon_quest` stub exists server-side but not wired for v1 UI.

## Out of scope (v1)

- Ownership timers / ninja loot rules (owner_id stub empty = free loot)
- Auto death-drop of player inventory
- Multi-player positions (hate list + character ids are wired; chase still uses local player cell)
- Ranged 130% sticky threshold
- New art assets
