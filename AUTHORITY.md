# Authority boundary — MockServer owns simulation

Client is a **rendering skin**: collect input → send `try_*` intents → apply returned `actions[]` / snapshots. No local cell writes, combat math, aggro, loot rolls, or dialogue text authority.

## Client may

- Plan click paths client-side (`GridPath`) as **intent only**; each step still calls `try_move`.
- Tween / animate sprites after server-ok moves (`apply_server_move`, player step tween).
- Cosmetic facing before a move attempt; **prefer** facing from `try_move` / `npc_move` results.
- Face NPCs locally on interact click (FX only).
- Drive HUD from server snapshots / actions (`set_stat`, `inventory_update`, `show_npc_dialogue`, …).
- Poll `poll_combat_tick()` and apply ambient `npc_move` / combat actions.

## Client must not

- Advance player or NPC cells without a successful server result.
- Call `try_npc_move` (server AI only).
- Run wander Timers / local AI for any NPC (hostile or friendly).
- Mutate HP / MP / inventory / loot / aggro except by applying actions.
- Open dialogue from pack `interact_text` (server `show_npc_dialogue` only).

## try_* / poll_* (client → MockServer)

| Method | Role |
|--------|------|
| `try_move(from_x, from_y, dir)` | Player grid step; `{ok,x,y,facing}` or `{ok:false,resync,x,y}` |
| `try_transfer(from_x, from_y)` | Warp when on warp cell |
| `try_interact(npc_id, px, py)` | Friendly script → `show_npc_dialogue` actions |
| `try_attack(npc_id, px, py)` | Basic attack → damage / kill / hate |
| `try_use_skill(skill_id, target, px, py)` | Skill cast |
| `try_use_item(item_id)` | Consumable use |
| `poll_combat_tick()` | Drain buffered AI `npc_move` + combat tick actions |
| `register_npc(...)` / `set_player_cell` | World sync occupancy on map load (not gameplay cheats) |

Server-internal (not for client actors): `try_npc_move` — used by MockServer AI tick only.

## Action opcodes (server → client apply)

| `type` | Effect on client |
|--------|------------------|
| `show_npc_dialogue` | Open Chat / dialogue UI |
| `npc_move` | `NpcActor.apply_server_move(x,y,facing)` |
| `npc_reset` | Restore NPC HP bar after evade |
| `damage` / `heal` / `set_stat` | HUD / target frame numbers |
| `skill_cd` | Hotbar cooldown display |
| `inventory_update` | Bag snapshot |
| `quest_update` | Quest journal snapshot |
| `kill_npc` / `spawn_npc` | Despawn / respawn actor |
| `player_died` / `respawn` | Lock input / place player |
| `loot_drop` | v1 no-op (loot via inventory + system_message) |
| `system_message` | System chat line |

## NPC / mob AI

- **All** idle wander / chase / return_home runs on MockServer (`AI_TICK_INTERVAL`).
- Hostiles: full AI (vision, hate, leash, respawn).
- Non-hostile with `wander: true` and/or `wander_radius > 0`: **idle wander only** (default radius `DEFAULT_FRIENDLY_WANDER_RADIUS` = 2 when flag set without radius).
- Client `NpcActor`: spawn / kill / face / `apply_server_move` only.

## Player movement

- Keyboard and click-follow both go through `_try_step` → `try_move`.
- Reject + `resync` → snap client cell (and facing if present) to server.
