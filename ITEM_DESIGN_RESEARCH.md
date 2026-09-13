# MMO Item System — Research Notes (2026-09-07)

Sources distilled for rmmo (MockServer inventory + loot). Practical architecture notes, not a full literature review.

## Key references
- **TrinityCore / MaNGOS** `item_template` + character inventory rows: static defs in DB; per-character stacks / equipped slots as instances (https://trinitycore.info / AzerothCore wiki)
- **Lineage 2** `ItemTemplate` + inventory: template id → type, stackable, consume type; instances carry enchant / count (L2J / L2 OFF server docs)
- **Inventory transaction patterns**: server validates → mutate bag atomically → emit delta (`inventory_update`) so clients never invent items (WoW / L2 / typical authoritative MMO)

## Template vs instance

| Layer | Role |
|-------|------|
| **item_template** | Shared definition: `id`, `name`, `type` (consumable / material / misc / …), `stack_max`, `use_effect`, sell/buy prices, icons |
| **item instance** | Per-player (or ground) row: template id + `qty` (+ optional uid, durability, enchants later) |

Trinity keeps heavy fields on `item_template`; bags store `item` guid + count. L2 `ItemTemplate` similarly drives stackable / consume; inventory holds count per slot. rmmo v1 collapses instance to `{id, qty}` in a Dictionary bag (no guid yet).

## Containers / slots
- Soft **slot capacity** (e.g. 20): each distinct stack occupies one slot.
- Stack merges into an existing stack up to `stack_max`; leftover needs a free slot or the add is rejected.
- Future: equipment slots, warehouse, trade window — same transaction discipline.

## Stackable / consumable
- **Stackable**: `stack_max > 1` (materials, potions).
- **Consumable**: `type=consumable` + `use_effect` (heal_hp / heal_mp / …); use path = validate CD → consume 1 → apply effect → inventory delta.
- Non-consumable materials: loot / craft only for now (no use).

## Loot tables
- Data-driven: mob template id / charset → entries `{item_id, chance, min, max}`.
- On kill: server rolls independently per entry; grant to killer bag (v1) or spawn ground loot later.
- Prefer **auto-add + chat** for v1 (no pickup UI).

## Server authority + delta inventory
1. Client sends intent only (`try_use_item`, never “I have 99 potions”).
2. Server mutates inventory in one transaction; rejects if full / missing / on CD.
3. Client applies `inventory_update` snapshot (or future slot deltas) + `system_message`.
4. Loot grants follow the same path — never trust client-reported drops.

## rmmo mapping
- `data/combat/items.json` (+ mirror under `scripts/net/combat/data/`) = item_template catalog.
- `inventory.gd` = authoritative bag (stack merge, capacity).
- `loot_tables.json` = per-mob / charset tables; MockServer rolls on `kill_npc`.
- Hotbar `use_item` unchanged; effects read `use_effect` or legacy `effect`.
