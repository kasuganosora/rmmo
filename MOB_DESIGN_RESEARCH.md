# MMO Monster / Mob System — Research Notes (2026-09-07)

Sources distilled for rmmo (grid + MockServer). Not a literature review; practical checklist.

## Key references
- OSRS-style mob FSM (idle/wander/chase/attack/return): https://hyperscape-ai.mintlify.app/wiki/game-systems/mob-ai
- MaNGOS/AzerothCore AggressorAI + Trinity ThreatManager (heap threat, evade): open-source WoW cores
- Lineage 2 hate / social aggro: https://en.wikibooks.org/wiki/Lineage_2/Combat/Mechanics_of_Hate
- WoW threat table (damage/heal threat, 110%/130% switch): warcraft.wiki.gg Threat
- Chen et al. Character Binding for MMO NPC teams (scalability): http://www.comp.nus.edu.sg/~ooibc/game3.pdf
- White et al. SIGMOD 2007 (data-driven AI for many NPCs): https://www.cs.cornell.edu/~wmwhite/papers/2007-SIGMOD-Games.pdf
- Server-side AI + spatial interest: https://www.ismailguven.com/spec.php

## Component stack (typical MMO)
1. Spawn / template registry (stats, AI profile, loot table id)
2. Instance lifecycle (alive → combat → death → corpse → despawn → respawn)
3. Perception (range, cone, LoS, level gating)
4. Aggro / threat table (multi-target hate, decay, hysteresis)
5. Social / pack assist
6. Movement (wander, chase path, return home, leash)
7. Combat actions (melee CD, skills, flee)
8. Evade / reset (full HP on return, clear debuffs)
9. Interest management (only tick / sync nearby mobs)
10. Data-driven profiles (JSON/DB), not hardcoded per mob

## Optimization themes
- Shared FSM / behavior tree + data profiles (not unique code per species)
- Coarse AI tick (0.2–0.5s), not every frame
- Spatial index / interest sets; lazy updates for packs (Character Binding)
- Server-authoritative; clients get deltas only
- Cap pathfinding; reuse A* graphs; stagger AI across frames
