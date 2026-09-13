# Mob system review (street_map / MockServer)

Scope: `mob_ai.gd`, `combat_stats.gd`, `combat_engine.gd`, `mock_server.gd` AI tick,
`npc_actor.gd`, `world.gd` register/apply, `street_map/npcs.json`.

## What works

- **Vision cone**: 120° / 6 cells Euclidean; facing RM dirs 2/4/6/8.
- **Aggressive vs passive**: base `aggressive` from JSON; passive → `enraged` on damage then same chase rules.
- **States**: `idle` → `chase` → `return_home` → `idle`; server tick owns movement.
- **Chase pathing**: A* / greedy via `next_chase_dir`; does not step onto player; facing updates on step / adjacent face.
- **Lose-sight**: 5s after last vision (now gated by `seen_target` — see fixes).
- **Return-home**: `clear_chase` walks to `home_cell` (spawn); can re-aggro on vision if still `wants_chase`.
- **Idle wander**: Chebyshev `wander_radius` around home; interval ~2.2s; radius 0 stands still.
- **Pack / `group_id`**: same non-zero id; assist distance = Chebyshev from **hit mob current cell** using **hit mob `wander_radius`**.
- **Client**: hostiles disable local wander Timer; `npc_move` → `apply_server_move` (no second `try_npc_move`).
- **Register path**: `world` → `register_npc(..., wander_radius, group_id)` seeds `npc_ai` + `home_cell`.

## Gaps / bugs

| Item | Status |
|------|--------|
| Group assist not firing / pack too sparse on street | **Fixed this pass** — dense `group_id: 2` pack + kill-blow / lose-sight fixes |
| Pack assist skipped on killing blow (`remove_npc` before activate) | **Fixed** |
| Off-vision pack chase abandoned in 5s without ever seeing player | **Fixed** (`seen_target`) |
| Return-home interrupted incorrectly | OK for design (vision re-aggro while `wants_chase`) |
| Leash: abandon if too far from home | **Fixed this pass** — Chebyshev `leash_radius` (default **12**, npcs.json) |
| Dead mob respawn / home timer | **Fixed this pass** — template + `respawn_sec` (default **30s**) → `spawn_npc` |
| Facing on wander/chase | Works (step dir / face toward player or home) |
| Client double-move on hostiles | Already guarded (`wander and not hostile`) |
| Pack distance metric | Confirmed Chebyshev vs hit cell + hit `wander_radius` |
| NPC HP seed from snapshot on spawn | Later (see REVIEW.md) |
| Wall LOS on vision ray | **Fixed this pass** — Bresenham + can_pass_tiles |
| Hate list / sticky victim | **Fixed this pass** — multi-actor hate_list, threat_mod, 110% select_victim |
| Evade full HP on return | **Fixed this pass** — clear_chase restores HP + npc_reset |
| Drops / loot + inventory stacks | **Fixed this pass** — loot_tables + stack_max + capacity |

## Fixed this pass

1. **`street_map/npcs.json` dense test pack** — 7 hostiles `group_id: 2`, `wander_radius: 5`, cells **(40–42, 20–22)** (north of spawn ~(41,23)); solos at (43,25)/(44,22); renegade pair `group_id: 1` tightened + radius 5.
2. **`combat_engine._damage_npc`** — call `activate_group_allies` **before** `remove_npc` so killing blows still wake the pack; `begin_chase` only if HP remains.
3. **`seen_target` on AI** — `begin_chase` / vision sets flag; lose-sight timer only accumulates after the mob has seen the player (pack assist / hit-from-behind no longer soft-fail).
4. Docs: `COMBAT.md` pack location + kill-blow / `seen_target` notes; this file; sync list.
5. **Home leash** — while `chase`, if Chebyshev(cell, home) > `leash_radius` (default 12, overridable in `npcs.json`) → `clear_chase` / `return_home` (passive clears enrage). Metric: **Chebyshev** (same as wander/pack).
6. **Dead mob respawn** — `register_npc` stores spawn template; `kill_npc` schedules `respawn_sec` (default 30, `<0` disables); timer re-registers at `home_cell` (or `find_spawn_near`) and emits `spawn_npc` for client `NpcActor` recreate.

## How to test pack assist

1. Enter `street_map` (spawn / warp ~**(41,23)**).
2. Walk **north** to the cluster around **(41,21)**.
3. Attack any pack member once — the other six within radius should path toward you.
4. Attack slime **(43,25)** or monster **(44,22)** — only that solo should react (no pack).

## Fixed this pass (acceptance batch)

7. **Hate list** — `npc_ai.hate_list` + `victim_id`; `add_hate` with threat_mod; sticky `select_victim` at 110%; cleared on evade.
8. **Evade full HP** — `clear_chase` restores `hp=hp_max`, clears hate_list + passive enrage; MockServer emits `npc_reset`.
9. **Vision LoS** — `MobAI.has_line_of_sight` Bresenham; integrated into `player_in_vision(..., map_collision)`.
10. **Items / loot** — expanded `items.json` templates; inventory stack_max + 20-slot soft cap; `loot_tables.json` + auto-grant on kill.
11. Docs: `ITEM_DESIGN_RESEARCH.md`, `ACCEPTANCE.md`, this file, `COMBAT.md`; `tools/test_acceptance_batch.gd`.
