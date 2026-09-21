# rmmo Asset Manager Design (UGC / Hot-Load)

Status: **P2c actor AOI rings implemented** (2026-09-09). Autoload + Gate + stream queue + actor VIEW/AOI/PREFETCH/COLD rings (not map chunks). See docs/asset_manager_review_log.md.

## Why not Godot `res://` / ResourceLoader

| Godot import pipeline | UGC / hot-load needs |
|---|---|
| Editor imports PNGs into `.import` + UID | Players upload maps/NPCs/chars after ship |
| `res://` baked into PCK | Content lives on CDN / GameServer |
| `ResourceLoader.load` expects imported assets | Must `Image.load` / JSON from disk or HTTP |
| Project tree pollution | Charsets already forbidden under project (苍蓝星 rule) |

**Rule:** Game shell (Godot project) ships code only. All art — including UI chrome — is **external** under the runtime content root (`rmmo/content_root`, e.g. `D:/code/rmmo_runtime`). Packs are **never** stored in `res://` and are **never** baked into the Godot PCK. Address them by content IDs (`content://map_pack/default`, `content://ui/l2/panel.png`), not project paths.

First-party default packs:

- `content://map_pack/default` → `{content_root}/packs/map_pack/default/<version>/`
- `content://ui/{skin}/{path}` → `{content_root}/packs/ui/default/<version>/{skin}/{path}`

Playtest maps: `content://map_pack/demo_map` (and bath_map / street_map) under `{content_root}/packs/map_pack/`. `res://demo_map` is a resolve alias only — the files are not in the Godot project.

## Goals

1. **Hot-load** packs from GameServer / CDN without rebuilding client.
2. **UGC**: player-submitted maps, NPCs, char models, looks — same pipeline as first-party.
3. **Own manager**: resolve → fetch → verify → cache → decode → hand out handles; Godot only renders textures we create.
4. **MockServer / future GameServer** remains authority for *which* pack IDs a player may enter; client only loads bytes.

## Content address

```
content://{kind}/{id}[@{version}]

kind ∈ map_pack | ui | charset | look | tilesheet | audio | icon | manifest
id   = stable slug (e.g. demo_home, actor03_0001, look_f_12)
version = semver or content-hash short (optional; omit = "latest allowed")
```

Examples:

- `content://map_pack/demo_home@1.2.0`
- `content://charset/!Chest1`
- `content://look/female/walk_04`
- `content://ui/l2/panel.png`
- `content://ui/indigo/button/UI_Dialogue_Button_White.png`
- `content://fx/fx_slash.png`
- `content://icon/wooden_sword`

Internal resolve maps to a filesystem path under the content root, or a URL to download into cache.

## On-disk layout (runtime)

```
{content_root}/                          # e.g. user://content  or  beside exe: data/content
  manifests/
    index.json                           # catalog: id → {kind, version, hash, size, url?}
  packs/
    map_pack/
      demo_home/
        1.2.0/
          pack.json
          map.json
          tileset.json
          tiles/*.png
          npcs.json
          events.json
          characters/                    # optional pack-local overrides
  assets/
    charset/
      actor03_0001.png
      !Chest1.png
    look/
      female/walk_04/...
  cache/
    downloads/                           # incomplete / staging
    verified/                            # hash-checked blobs
```

Dev fallback may still point `charset` at `D:/code/rmmo_runtime/characters` via config.

## Pack formats

### map_pack (extends current `tilemap_pack_v1`)

Keep existing JSON shape. Add to `pack.json`:

```json
{
  "format": "tilemap_pack_v1",
  "content_id": "demo_home",
  "version": "1.2.0",
  "deps": [
    {"kind": "charset", "id": "actor03_0001"},
    {"kind": "charset", "id": "!Chest1"}
  ]
}
```

Client loads pack folder; AssetManager ensures `deps` are present (download if missing).

### charset / look

Raw PNG (or folder of frames). No Godot import. Decode via `Image.load` / `Image.load_png_from_buffer`.

## AssetManager API (client)

Singleton / Autoload `AssetManager` (skeleton: `scripts/asset/asset_manager.gd`):

```
ensure(content_ref) -> Error          # block or async: local or download+verify
has(content_ref) -> bool
path(content_ref) -> String           # absolute local path after ensure
load_image(content_ref) -> Image      # cached
load_json(content_ref_or_path) -> Dictionary
load_map_pack(id, version="") -> TilemapPack-like
evict(content_ref) / clear_cache()
set_remote(base_url, headers)         # future CDN
```

**Never** return `PackedScene` / imported `Texture2D` from `res://` for UGC. Always `Image` → `ImageTexture.create_from_image`.

## Trust & verification

1. Manifest lists `sha256` + size per blob.
2. After download, hash must match before promoting staging → verified.
3. GameServer signs catalog entries (later); MockServer can ship local manifests unsigned.
4. UGC: server validates dimensions / format / max size / banned paths before listing.

## Load pipeline

```
HUD/World needs asset
  → AssetManager.ensure(ref)
       → hit verified cache? return
       → hit content_root packs? verify hash → cache handle
       → else HTTP GET url from manifest → staging → hash → verified
  → decode Image / JSON
  → MapField / CharsetSheet / Look consume Image (no ResourceLoader)
```

Async: prefer signal `ensure_finished(ref, ok)` for large packs; Loading screen already exists — hook pack ensure there.



## Two load modes: Gate vs Stream

UGC means you will **never** have every asset before play. Split loads into:

| Mode | When | UX | Blocks gameplay? |
|---|---|---|---|
| **Gate (Loading)** | Enter world / map transfer | Full-screen Loading + % | Yes — stay on Loading until **required** set ready |
| **Stream (in-map)** | Another player/NPC/item appears with unknown look/equip/icon | Placeholder → swap in | No — world keeps running |

**Hard rule:** Only **map shell** (tiles + collision + local player look + pack-listed NPC deps) is Gate. Everything belonging to *other actors* or *optional icons* is Stream.

---

## Loading screen: resource progress

Extend current `loading_screen.gd` (already bakes map/radar) into phased progress.

### Phases (weights example)

```
0–5%    session / spawn payload from MockServer
5–15%   ensure map_pack (download+verify if needed)
15–40%  ensure pack deps (tilesheets, listed charsets) — byte progress
40–85%  decode + MapField bake (existing rebuild_async)
85–95%  ensure local player look / paperdoll sheets
95–100% apply bake, hand off to World
```

UI copy examples: `拉取地图包…` / `校验素材 3/12` / `绘制地图…` / `准备角色…`

### Required set for Gate (must finish)

From spawn / transfer action:

```json
{
  "map_content": "content://map_pack/demo_home@1.2.0",
  "required": [
    "content://map_pack/demo_home@1.2.0",
    "content://charset/$Hero",
    "…"
  ]
}
```

Server (or pack `deps`) lists required refs. Client `AssetManager.ensure_many(required, on_progress)` before bake.

### Optional prefetch (nice-to-have on Loading)

Nearby map warps' pack manifests only (not full tiles) — can start download in background after enter.

### Failure on Gate

- Retry N times → show error + button back to character select.
- Never enter World with missing tiles/collision.

---

## In-map streaming: other players bring unknown assets

### Problem

You entered `demo_home` with pack deps loaded. Another player walks in wearing UGC armor `content://icon/eq_fancy_helm@3` and look `content://look/ugc_bob@1` you never downloaded.

### Server contract

Every visible actor snapshot must carry **content refs**, not only display names:

```json
{
  "actor_id": "p_123",
  "name": "Bob",
  "look": "content://look/ugc_bob@1",
  "equipment_visuals": [
    {"slot": "head", "icon": "content://icon/eq_fancy_helm@3"},
    {"slot": "weapon_main", "icon": "content://icon/eq_wood_sword@1"}
  ]
}
```

Ground loot / bag UI icons same: item def → `icon` content ref.

MockServer / GameServer is still authority for *which* ids exist; client only fetches allowlisted manifest URLs for those refs.

### Client flow (Stream)

```
spawn/update remote actor
  → collect missing refs from look + equipment_visuals + nameplate icons
  → AssetManager.enqueue(refs, priority=VISIBLE_ACTOR)
  → bind actor to PlaceholderAppearance immediately
  → on ensure_finished(ref, ok):
       if ok → rebuild that actor's sprites / paperdoll layer / item icon
       if fail → keep placeholder + optional tiny "!" once
```

### Placeholders (must ship in client PCK — these MAY use res://)

| Missing | Placeholder |
|---|---|
| Player/NPC look / charset | Silhouette / letter-avatar (existing InvSlot grapheme style) + tint |
| Equipment icon | Empty slot chrome or generic "gear" glyph |
| Item icon in bag/loot | Letter-avatar from item name (already done) until icon arrives |
| Whole remote player | Capsule + nameplate; no soft-lock |

Placeholders are **first-party chrome**, not UGC — OK to embed in Godot project.

### Priority queue

```
CRITICAL   Gate required (Loading only)
HIGH       On-screen remote players / selected target
NORMAL     Off-screen but in AOI (interest radius)
LOW        Prefetch (adjacent map, bag icons not open)
```

- Cap concurrent downloads (e.g. 2–4).
- Cancel or demote LOW if HIGH backlog grows.
- Deduplicate: one `ensure` per content ref globally.

### When to load vs when not

| Situation | Behavior |
|---|---|
| Remote player enters AOI | Stream look + visible equip icons |
| Remote player leaves AOI | Keep cache; stop pending LOW jobs for them |
| Open bag / examine | Bump those item icons to HIGH |
| Emote / rare FX | Stream; placeholder skip OK |
| Map transfer | Gate again for new map required set |

### Memory / eviction

- LRU on decoded Images after cap (e.g. 128–256 MB soft).
- Never evict **current map tilesheets** or **local player** look while on that map.
- Evict remote looks unused for N minutes.

### Consistency

- Appearance is cosmetic: late swap must not affect MockServer combat/hitbox (server already has stats).
- If hash/version mismatch mid-stream, drop to placeholder and request fresh manifest entry (log once).

### Anti-abuse

- Max size per ref; max concurrent stream bytes per minute.
- Only fetch URLs present in signed/server manifest — no raw URL from other clients' packets.

---

## Loading vs Stream API sketch

```
AssetManager.ensure_many(refs, gate=true) -> await Progress
AssetManager.enqueue(refs, priority)
AssetManager.cancel_priority_below(HIGH)
signal progress(ref, loaded_bytes, total_bytes)
signal ensure_finished(ref, ok)
signal gate_progress(phase, fraction, label)   # for Loading UI
```

Loading screen subscribes to `gate_progress`. World/HUD subscribe to `ensure_finished` to refresh actors.

---



## AOI interest + out-of-view prefetch (memory-safe)

Large maps + many players: **never** "load the whole map / everyone" at Gate or on enter. Interest is spatial.

### Rings (cell or pixel radius from local player / camera)

```
                ┌─────────────────────────────┐
                │  PREFETCH (LOW)             │  +N cells beyond AOI
                │   ┌─────────────────────┐   │
                │   │  AOI / STREAM (NORMAL)│   │  interest radius (server+client)
                │   │   ┌─────────────┐   │   │
                │   │   │ VIEW (HIGH) │   │   │  camera frustum + margin
                │   │   │   YOU       │   │   │
                │   │   └─────────────┘   │   │
                │   └─────────────────────┘   │
                └─────────────────────────────┘
         outside → COLD: no download; evict decoded if over budget
```

| Ring | Who | Asset policy | Priority |
|---|---|---|---|
| **VIEW** | On screen (+ small margin) | Must show soon; placeholder→swap | HIGH |
| **AOI** | In interest / sync radius | Keep decoded if budget allows; download looks | NORMAL |
| **PREFETCH** | Thin band outside AOI | **Only** cheap/meta or next-chunk tiles; throttle hard | LOW |
| **COLD** | Far | No new downloads; eligible for eviction | — |

Prefetch is **not** "load everything nearby early." It is a **small lookahead** so walking feels smooth without exploding RAM.

### What to prefetch vs what not to

| Asset | Prefetch? | Notes |
|---|---|---|
| Map **collision / walk grid** for current pack | Gate (full) | Small JSON; needed for pathfinding |
| Map **tile images** | Chunk / sector streaming if map huge | See map chunks below — do **not** blit entire megamap at once long-term |
| Charsets / looks of players in VIEW+AOI | Stream | Prefetch band: at most **names + look id**, start download only if bandwidth idle |
| Equipment icons | Only VIEW / open UI | Prefetch band: skip unless examine queued |
| Adjacent warp pack | Prefetch **manifest only** (KB) | Full pack download starts on transfer Gate, or optional soft prefetch when standing near warp for T seconds |
| Audio / FX | On demand | Never whole-pack prefetch |

### Map chunks (big maps)

Current demo packs bake whole ground/upper into Images (OK for small maps). For street-scale / UGC megamaps:

1. Split bake into **chunk images** (e.g. 32×32 or 64×64 tiles per chunk).
2. Gate loads **spawn chunk + 8-neighbors** only.
3. As camera moves: enqueue neighbor chunks LOW/NORMAL; unload chunk textures that leave PREFETCH ring (keep collision data).
4. Radar can keep a **downscaled whole-map atlas** (already 0.5× bake idea) as one small texture — not full-res tiles.

Until chunked blit exists: Gate still bakes current pack size, but **actor assets** must already follow AOI rules so player count does not multiply VRAM.

### Memory budget (soft caps)

Configurable defaults (tune later):

```
decoded_image_budget_mb   = 192   # soft
decoded_image_hard_mb     = 256   # start aggressive eviction
max_cached_looks          = 64    # remote actor looks
max_cached_icons          = 128
max_concurrent_downloads  = 3
prefetch_bandwidth_share  = 0.25  # prefetch ≤25% of download slots when HIGH pending
```

**Eviction order when over soft budget:**

1. COLD decoded looks/icons (LRU)
2. PREFETCH-only downloads cancel first
3. AOI-off-screen looks (keep placeholder binding)
4. Never evict: current VIEW actors, local player, **resident map chunks**, Gate-required tilesheets for current map

### Prefetch scheduler rules

1. If any HIGH job pending → **pause** PREFETCH downloads (finish in-flight only).
2. Prefetch queue capped (e.g. 8 entries); drop oldest LOW when full.
3. Enter PREFETCH ring → may `enqueue(look_ref, LOW)` once; leaving PREFETCH → cancel LOW job if not started.
4. Leaving AOI → mark look **evictable**; do not immediately free if under soft budget (hysteresis ~5–10s) to avoid thrash when player turns around.
5. Server AOI list is source of truth for "who exists"; client does not invent far players to prefetch.

### Server help (MockServer / GameServer)

- Interest management: only replicate actors in AOI (+ maybe prefetch shell as **ids without full equipment icon list**).
- Appearance packet can be **tiered**:
  - AOI enter: `look` ref + name
  - VIEW / target / examine: full `equipment_visuals` icon refs
- Reduces client even *knowing* about hundreds of fancy icons for far players.

### Performance intent

| Bad | Good |
|---|---|
| Enter map → download all players' UGC | Enter → Gate map shell; stream VIEW; soft prefetch AOI band |
| Keep every look forever | Budget + LRU + ring demotion |
| Prefetch = full adjacent maps | Prefetch = chunk neighbors + idle look downloads only |
| One giant ground Image for 500×500 | Chunk textures + small radar atlas |

### API additions (skeleton later)

```
AssetManager.set_budget(mb_soft, mb_hard)
AssetManager.set_interest(view_rects, aoi_ids, prefetch_ids)
AssetManager.note_actor_ring(actor_id, ring)  # VIEW|AOI|PREFETCH|COLD
# on ring downgrade → cancel LOW / mark evictable
```

Loading screen unchanged: still Gate-only. Prefetch starts **after** World visible (`gate_progress done`).


## Implementation order (updated)

| Phase | Work |
|---|---|
| P0 | Design (this doc) + AssetManager skeleton |
| P1 | Local content_root; charset/map resolve via Manager |
| P1b | Loading: `ensure_many` + progress labels around existing bake |
| P2 | Manifest + deps |
| P2b | Placeholders + in-map enqueue for charset/look (single-player fake remote optional) |
| P2c | AOI rings + budget/LRU + prefetch throttle; cancel LOW when HIGH busy |
| P2d | Map chunk streaming design spike (big maps); radar stays low-res whole |
| P3 | HTTP download + hash; Loading byte progress |
| P3b | Remote-player appearance refs in MockServer snapshot + stream |
| P4 | UGC upload pipeline (server) |


## Migration plan

| Phase | Work |
|---|---|
| **P0 Design** | This doc + skeleton AssetManager |
| **P1 Local root** | Unify content_root; move demo packs path resolution through AssetManager.path; charset_sheet calls AssetManager.load_image |
| **P2 Manifest** | Local `manifests/index.json`; deps check on map enter |
| **P3 Hot fetch** | HTTP download + hash; Loading UI progress |
| **P4 UGC upload** | Server API accept zip → validate → publish manifest entry (out of client scope) |
| **P5 Evict look_catalog res://** | BKX1 looks leave project; same charset/look pipeline |

## MockServer authority

- Spawn / transfer still returns `pack_path` or better **`content_id` + version**.
- Client may only load packs the server named; do not trust client-supplied arbitrary URLs without manifest allowlist.
- Events / NPCs / shops stay JSON inside the pack; scripts run on server as today.

## Non-goals (v1)

- Streaming mipmaps / VRAM budgets beyond simple Image cache caps
- Encrypting all assets at rest
- Live patch of a pack while standing on that map (require leave map / reload)
- Replacing Godot for UI themes (chrome may stay `res://`)

## Open decisions (defaults)

1. **content_root default:** `user://content` (writable) + optional read-only `exe/data/content`.
2. **Pack zip vs folder:** ship/download as `.rmpack` zip (zip+manifest); extract to `packs/.../version/`.
3. **Version pin:** server spawn dict includes `content_version`; client refuses mismatch.

## Skeleton files

- `scripts/asset/asset_manager.gd` — API stub + local resolve
- `scripts/asset/content_ref.gd` — parse `content://...`
- `docs/asset_manager_design.md` — this file
