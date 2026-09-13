# Code review (post combat leftovers)

Scope: `scripts/net`, `scripts/game`, `scripts/ui` on `/workspace/rmmo`.

## Findings

| Severity | File | Issue | Status |
|----------|------|-------|--------|
| **Medium** | `mock_server` / `combat_engine` | Adjacency trusted client when NPC cell unknown | **Fixed:** reject when cell missing; attack/interact use `player_cell` |
| **Medium** | `mock_server.try_move` | `from` not checked vs `player_cell` | **Fixed:** reject + `resync` coords |
| **Medium** | `game_hud` inventory/skills | L2Mock fluff | **Fixed:** server bag + `skill_catalog` text lists |
| **Medium** | `world` click-to-engage | No auto-engage on arrival | **Fixed:** `_pending_engage_npc_id` + `arrived_cell` |
| **Medium** | death | system_message only | **Fixed:** `player_died` → `respawn` at last safe / spawn |
| **Low** | `try_transfer` player_cell | unset until world respawn | **Fixed** (prior) |
| **Low** | player damage apply | ignored | **Fixed** (prior) |
| **Low** | hotbar | placeholder | **Fixed** (prior thin wiring) |
| **Low** | NPC hp seed on spawn | optional | Later |
| **Low** | void filler heuristic | pack override | Later |
| **Info** | Skill icon polish | no art invented | Skipped by design |

## Safe fixes applied this pass

1. Auto-engage after pathfinding arrives beside click target (`try_attack` / `try_interact`).
2. `try_move` anti-desync (`resync`); attack/skill/interact use authoritative cell + registered NPC adjacency.
3. Player death → respawn actions (full HP/MP, clear CDs, brief client input lock).
4. HUD Skills/Inventory driven by `skill_catalog` / `inventory_update` (text labels).

## Left for later

- NPC HP seed from `ensure_npc` snapshot on spawn.
- Data-driven dialogue scripts beyond `actor_rest`.
- Skill icons / drag-to-hotbar (needs real art).
- `void_tile_id` pack override.

## Architecture

See **`COMBAT.md`**.
