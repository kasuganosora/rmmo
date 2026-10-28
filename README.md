# rmmo

Godot 4 client + in-process mock server for a tile MMORPG. **This repository is code only.**

Art, audio, fonts, and packs live in an **external content root** (not in git, not in the Godot PCK). See `NOTICE.md`.

## License

MIT for the source in this repo. Third-party art is **not** included and must not be pushed to GitHub.

## Content root

Set `rmmo/content_root` in `project.godot` (or let `AssetManager` fall back to `D:/code/rmmo_runtime` on Windows). Layout:

- `content.json` — start/street pack ids, aliases, spawn cells
- `packs/ui/default/<ver>/` — UI chrome (`content://ui/…`)
- `packs/map_pack/<id>/<ver>/` — map packs
- `data/combat`, `data/map`, `data/rtp` — catalogs (`content://data/…`)
- `assets/fx`, `assets/icon`, `assets/tilesheet`, `assets/charset`, …

The MV image library is a local copy at `{content_root}/packs/mv_img`. Keep it out of git and out of `res://`.

## Run

Godot 4.7+. Open this folder, play `scenes/login.tscn`. Without a local content root, chrome/tiles soft-miss (placeholders).

The login screen's connection settings can switch between MockServer and the Go
server. To start directly in real mode:

```sh
godot --path . -- --backend=real --server-url=http://127.0.0.1:7777
```

See [real server connection](docs/real_server_connection.md) for map mappings,
protocol generation, supported flows, remaining business UI adapters and live tests.
See [conditional gameplay snapshots](docs/runtime_snapshot_sync.md) for resource
versions, bounded batch fallback and compatibility with older servers.

See [MockServer architecture](docs/mock_server_architecture.md) for module ownership,
generated interfaces, simulation settings and asset-free regression commands.
