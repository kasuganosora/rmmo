# Combat / Skills / Items architecture (MockServer)

Authoritative data & logic live in **MockServer** (stand-in for a future GameServer).
The client only reports **intent** and applies returned **`actions[]`**.

## Layout

```
scripts/net/mock_server.gd          # Facade: try_move, try_attack, try_use_skill,
                                    #         try_use_item, try_interact, poll_combat_tick
                                    #         + mob AI tick → npc_move
scripts/net/combat/
  combat_stats.gd                   # Player/NPC HP·MP·ATK, cooldowns, npc_cells, npc_ai, hate_list
  combat_engine.gd                  # Damage, heal, death, counter-attack, skill/item resolve
  mob_ai.gd                         # Vision cone + LoS + chase / return-home / idle wander
  skill_catalog.gd                  # Loads skills.json (+ builtin fallback)
  item_catalog.gd                   # item_template JSON (+ builtin fallback)
  inventory.gd                      # Server bag: stack_max merge, soft slot capacity
  loot_catalog.gd                   # loot_tables.json roll on kill
  data/skills.json
  data/items.json
  data/loot_tables.json
data/combat/                        # Mirror of JSON for future GameServer share
```

## Client → server intents

| Call | Purpose |
|------|---------|
| `try_move(from, dir)` | Grid step; returns `facing`; rejects if `from ≠ player_cell` (`resync`) |
| `try_attack(npc_id, x, y)` | Basic attack (uses authoritative `player_cell` + registered NPC cell) |
| `try_use_skill(skill_id, target_npc_id, x, y)` | Validate MP/CD/range → resolve |
| `try_use_item(item_id)` | Consume → heal / inventory_update |
| `try_interact(npc_id, x, y)` | Dialogue when adjacent (registered cell required) |
| `poll_combat_tick()` | Drain ambient combat ticks + `npc_move` AI actions |

## Action opcodes (client apply)

- `damage` — target `npc` or `player` (`amount`, `hp`, `hp_max`; optional `crit:true`)
- `miss` — target `npc` or `player` (`id`); no HP change. Hit≈90% ±2%/level diff; crit≈8% ×1.5 via `combat_randf`
- `heal` — player HP/MP restore
- `set_stat` — sync player HP/MP bars
- `kill_npc` — remove actor + clear occupancy
- `skill_cd` — remaining / cooldown hint
- `inventory_update` — `{ items: [{id, qty}, ...] }`
- `player_died` — lock input, clear path/target
- `respawn` — place at cell, restore bars, brief `input_lock_sec`
- `npc_move` — `{ npc_id, x, y, facing }` server-driven NPC step / face (chase / return / idle)
- `spawn_npc` — `{ npc: {…npcs.json fields…} }` recreate hostile after timed respawn
- `npc_reset` — `{ npc_id, hp, hp_max, reason:"evade" }` restore client NPC HP after evade
- `loot_drop` — `{ npc_id, item_id, qty }` informational roll line
- `ground_spawn` / `ground_update` / `ground_despawn` — world ground bags (`bag` snapshot / `bag_id`)
- `loot_open` / `loot_update` / `loot_close` — loot UI session for an open `bag_id` (close keeps bag)
- `system_message` — chat/system line (loot: `地上出现了掉落物` / `获得 xxx×n` / `扔下了 xxx×n`)
- `show_npc_dialogue` — unchanged NPC Chat path

## Mob AI (aggressive vs passive)

Hostiles split into **主动 (aggressive)** and **被动 (passive)**.

| Flag | Source | Behavior |
|------|--------|----------|
| `aggressive: true` | `npcs.json` (base 主动) | Chase when player enters vision |
| `aggressive: false` / omitted | default **被动** | No chase on sight; react-on-attack (adjacent counter) as before |
| `enraged` | runtime (server `npc_ai`) | Set when a **passive** takes player damage; then chase uses the **same** vision rules as aggressive |

### Vision (meters → cells)

- Project tiles are **48px** (RPG Maker style). Convention: **1 tile ≈ 1 meter**.
- Vision range **6 m → 6 cells**.
- Cone **120°** (half-angle **60°** from facing).
- Facing uses RM dirs: `2` down, `4` left, `6` right, `8` up.
- Distance: **Euclidean** cell distance ≤ 6.
- In vision when `angle(forward, to_player) ≤ 60°` and distance ≤ 6.
- **Line of sight:** before the cone accepts the player, Bresenham / step along cells;
  if any intermediate cell blocks passage (`can_pass_tiles` / wall / void), vision fails.

### Chase / lose-sight / return home / idle wander

States (`npc_ai.ai_state`): **`idle`** | **`chase`** | **`return_home`**.

- Authoritative AI runs on MockServer (`AI_TICK_INTERVAL` ≈ 0.45s), not the client.
- On `register_npc`, spawn cell is stored as **`home_cell`**; **`wander_radius`** (cells) comes from `npcs.json` (default **0** = stand still when idle).
- Aggressive **or** enraged + player in vision → `ai_state=chase`, set `chase_target`, path one A* / greedy step via `try_npc_move`, emit `npc_move`.
- While chasing, facing updates toward move / player.
- If chasing but player **not** in vision: accumulate `lose_sight_sec`; at **≥ 5 s** abandon chase (`clear_chase`).
- In vision while chasing → reset lose-sight timer.
- **Home leash:** while chasing, if **Chebyshev**(current cell, `home_cell`) > `leash_radius` → abandon (`clear_chase`) same as lose-sight.
  - Default **`leash_radius` = 12** cells (Chebyshev). Override per NPC in `npcs.json` (`leash_radius`). `<0` disables.
- **No valid target:** while chasing, if player is outside engage range (Chebyshev ≤ `max(leash_radius, 15)`) for **≥ 5 s** (`no_target_sec` / `NO_VALID_TARGET_SEC`) → same abandon.
- **After abandon (`clear_chase` / evade):** clear chase + **hate list** / victim; **passive** clears `enraged`;
  **restore NPC to full HP**; emit **`npc_reset`** so the client HP bar resets; enter **`return_home`**
  and step toward `home_cell` (emit `npc_move`) until arrived → **`idle`**. Does **not** freeze in place.
- **While `return_home`:** no vision re-aggro, no ambient counter-attack, no chase skills — walk home first.
  If path is blocked for **`RETURN_STUCK_TICKS` (8)** AI steps → **teleport** snap to `home_cell` (`npc_move` + `teleport:true`) and idle.
- **Idle:** if `wander_radius > 0`, occasionally step to a random landable neighbor that stays within Chebyshev radius of `home_cell` (interval ≈ `IDLE_WANDER_INTERVAL_SEC` 2.2s); if `0`, face idle / no move.
- After arriving home (`idle`), vision aggro may resume (aggressive or still-enraged).

### Pack / group_id

- `group_id` (int) on NPC / `npc_ai`: **`0` = solo**; same non-zero value = one pack.
- When the player **hits** a mob with `group_id ≠ 0`, server calls `activate_group_allies`
  **before** `remove_npc` (so a killing blow still wakes the pack):
  every other living hostile with the **same** `group_id` whose cell is within
  **Chebyshev ≤ hit mob's `wander_radius`** of the **hit mob's current cell**
  also `begin_chase` (passive → enraged + chase; aggressive → chase even off-vision).
- Pack assist uses the **attacked mob's** `wander_radius` and **current** position (行走半径).
- Off-vision chase (pack / hit-from-behind): `seen_target` stays false until the mob
  actually sees the player; **lose-sight 5s only accumulates after** first vision.
- On `clear_chase` / return home: each mob clears its own chase; **passive** pack members
  clear `enraged` (not permanently aggro). Aggressive keep base aggressive.

### Map defaults

- `street_map` entry / warp spawn ≈ **(41,23)** (from demo outdoor door).
- **Dense test pack `group_id: 2`** (7 hostiles, `wander_radius: 5`, `aggressive: true`):
  tight cluster cells **(40–42, 20–22)** — walk **north** from spawn a few tiles.
  Charsets rotate `gnr_renegade001` / `Monster` / `retira_slime`.
  Hit any one → all in Chebyshev ≤5 of the hit cell should `begin_chase`.
- Renegade A/B `group_id: 1` at **(38,24)** / **(37,25)**, `wander_radius: 5` (small pack).
- Solos `group_id: 0`: slime **(43,25)**, monster **(44,22)** — contrast (no assist).
- `demo_map` slime: `aggressive: false` (被动), `wander_radius: 2`, `group_id: 0`.
- Omitted `aggressive` → **false** (passive). Omitted `wander_radius` → **0** (stand still).
  Omitted `group_id` → **0** (solo).
  Omitted `leash_radius` → **12** (Chebyshev). Omitted `respawn_sec` → **30**.

### Dead mob respawn

- On `register_npc`, MockServer stores a **spawn template** (id, name, charset, stats snapshot, aggressive, wander_radius, group_id, home, facing, leash/respawn).
- When a hostile dies (`kill_npc` / `remove_npc`), server schedules respawn after **`respawn_sec`** (default **30**; set on `npcs.json` / AI blob; **`<0` disables**).
- On timer: if `home_cell` landable use it, else `find_spawn_near(home)`; re-register NPC; emit **`spawn_npc`** with full npc data.
- Client `world` applies `spawn_npc` like pack spawn (`NpcActor.setup` + occupancy).

### Client

- World applies `npc_move` → `NpcActor.apply_server_move` (no second `try_npc_move`).
- World applies `spawn_npc` → recreate `NpcActor` from action payload.
- `register_npc(..., hostile, aggressive, facing, wander_radius, group_id, spawn_data)` seeds `combat_stats.npc_ai` (+ `home_cell`) and stores respawn template.
- **All** NPCs: client wander Timer **removed**. Hostiles: server idle/chase/return. Friendlies with `wander: true` / `wander_radius`: server idle wander only (see AUTHORITY.md).

### Hate list (multi-player threat)

- Per-mob **`hate_list`**: `Array` of `{ id, threat, threat_mod }` (source of truth) + **`victim_id`** sticky target.
- Legacy `threat{}` dict is migrated away on read; `add_threat` remains a thin wrapper → `add_hate(..., mod=1.0)`.
- API (`combat_stats`):
  - `add_hate(npc_id, actor_id, raw_amount, threat_mod=1.0)` — applied = raw × mod; upsert list entry.
  - `get_hate_list(npc_id)` — copy of entries (sorted by threat desc).
  - `select_victim(npc_id)` — sticky: keep current unless another ≥ **110%** melee (`THREAT_SWITCH_RATIO`; ranged 1.30 later).
  - `clear_hate(npc_id)` on evade; also cleared inside `clear_chase`.
  - `set_actor_threat_mod(actor_id, mod)` / `get_actor_threat_mod` (tank weapons/skills ≈ 1.5–3.0).
  - Stub `add_hate_heal(npc_id, healer_id, heal_amount)` at **0.5×** for future party heals.
- Damage path: `add_hate(npc, attacker_id, damage, attacker_threat_mod)` — actor id from session character string when set, else `"player"`.
- Chase AI calls **`select_victim` each tick** / after damage (not a single hardcoded player).
- Character/session: `player_actor_id` + `threat_mod` (default 1.0; mock tank 2.0–3.0 for tests).

## Items / inventory / loot

### item_template (`items.json`)
Fields: `id`, `name`, `type` (`consumable`|`material`|`misc`), `stack_max`, `use_effect` (or legacy `effect`), `amount`, `cooldown`, optional `sell_price`.

### Inventory
- Stack merges up to `stack_max`; soft capacity **20** distinct slots — reject add if full.
- `try_use_item` unchanged for hotbar; reads `use_effect` then `effect`.

### Loot tables (`loot_tables.json`)
- Lookup: `by_npc_id` → `by_charset` → `default`.
- Entries: `{item_id, chance, min, max}`.
- On `kill_npc`: MockServer rolls → `loot_drop` lines + **ground bag** at kill cell (`ground_spawn`/`ground_update`, merge same cell). **No auto-open** loot UI; system `地上出现了掉落物。`
- Open: click bag marker when adjacent → `try_open_ground_bag` → `loot_open` (HUD reuse).
- `try_loot_take` / `try_loot_take_all` / `try_loot_close` operate on **open bag_id**; grant on take; bag full leaves items on ground; **close keeps bag** (empty → `ground_despawn` + `loot_close`).
- Player drop: `try_drop_item` (HUD inventory **right-click** slot → drop ×1) → remove from inv → ground bag at player cell + `扔下了 xxx×n`.
- Street pack mobs wired via charset (`retira_slime` / `Monster` / `gnr_renegade001`) and explicit `street_slime` / `street_monster` ids.

See also `ITEM_DESIGN_RESEARCH.md` and `ACCEPTANCE.md`.

## Click-to-engage

World stores `_pending_engage_npc_id` when click-to-move targets an NPC.
Player emits `arrived_cell`; when adjacent (or path ends beside target),
world auto-calls `try_attack` (hostile) or `try_interact` (friendly).
Keyboard / failed path clears the pending id.

## Death / respawn

HP ≤ 0 → `player_died` + MockServer `_append_respawn_actions`:
`你死了。`, close open loot UI only (ground bags persist), restore full HP/MP, clear CDs,
`set_player_cell` to `last_safe_cell` / `respawn_cell`, emit `respawn` +
`你已在安全点复活。` (client locks input for `input_lock_sec`).

## Hotbar / HUD

- Hotbar page 0: `1` basic_attack · `2` power_strike · `3` heal_light ·
  `4` potion_hp_small · `5` potion_mp_small
- Skills window: `snapshot_skill_catalog()` text rows (click to cast)
- Inventory window: `inventory_update` / bag snapshot text rows (click to use)

## Notes

- Range requires `combat_stats.npc_cells` (from `register_npc` / `try_npc_move`).
  Unknown cell → reject (no client trust).
- Map warps unchanged; transfer updates `respawn_cell`.
- No dependency on tile PNGs / skill icon art.
- Vision includes wall LoS (Bresenham); actor occupancy does not block sight (`can_pass_tiles`).
- Research notes: `ITEM_DESIGN_RESEARCH.md`, `MOB_DESIGN_RESEARCH.md`. Acceptance: `ACCEPTANCE.md`.
