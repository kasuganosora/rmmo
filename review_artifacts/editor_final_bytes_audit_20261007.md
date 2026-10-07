# Editor final source verification — 2026-10-07

## Decision and scope

The earlier Grok initial review (`grok_open_signature_20261007/report.txt`, exit 0, independently reviewed in `review.txt`) correctly rejected background-only SHA, mtime/size and cross-frame incremental SHA. None preserves the current final-check-to-publication rule. Replacing final cryptographic hashing with **complete byte equality in the same synchronous unit** retains a final observation of all source bytes, while moving SHA calculation to the existing worker. It is not an OS writer lock; neither was the previous final SHA.

Implemented with parent authorization after the independent probe: an internal source snapshot reads once, hashes and parses those same bytes; retain at most 256 MiB until final validation. Final 4 MiB reads compare every byte with that snapshot, without yielding or invoking progress. Above the retention limit, the worker releases raw bytes and the final synchronous SHA remains. No mtime/size-only acceptance, sampled content, prepared-success Boolean, or change to save conflict/atomic publish is introduced.

## Reproduced measurements

Read-only fixture: `D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf`, 169,359,708 bytes; SHA `95999c6c22d14a14d3187ea0df865db5fb3dcb52276b6c6ec3426559c74bc62d`. Godot 4.7.2 exact binary commit `ed1daf0bf001b61586d9930840f2f1394092c079`.

`tools/profile_document_final_check.gd` ran two SHA / whole / chunk / chunk / whole / SHA sequences in headless mode, exit 0. These are main-thread, complete-operation times; frame count did not advance inside any check and simulated publication. They are not whole-editor loading measurements.

| Final check | Four samples (ms) | Maximum main-thread unit | Additional sampled engine static allocation |
|---|---|---:|---:|
| FileAccess SHA-256 | 771.633, 825.072, 780.968, 802.477 | 825.072 ms | ~0 (native stack hash buffer not measured) |
| Whole-file read + equality | 104.593, 120.270, 139.541, 112.594 | 139.541 ms | 169,360,488 bytes |
| 4 MiB read + snapshot slice equality | 215.109, 233.513, 225.010, 229.276 | 233.513 ms | 8,389,452 bytes |

All methods in this probe hold the initial 169 MB snapshot. In production the new path therefore adds that retained payload compared with the old SHA path; the table's allocation figures are additional final-check buffers only. Engine allocation sampling is not OS RSS; cumulative process static peak is separately labeled in JSON. The selected chunk method trades approximately another 0.1 second for approximately 161 MiB less temporary allocation on this fixture. It still causes a measurable synchronous load pause; it does not make publication free or fit an 8 ms slice.

Evidence: `D:/code/rmmo_runtime/review_artifacts/document_final_check_20261007.json` and `.log`.

## Production changes and trust boundary

- `scripts/world3d/document_source_snapshot.gd`: one worker read → SHA and JSON; bounded byte retention; explicit short-read/open/error handling; final complete chunk comparison or SHA fallback. `retain_limit` can only reduce the hard cap, useful for testing fallback on small fixtures.
- `scripts/world_editor/load_job.gd`: the private worker returns this typed internal object; `begin_snapshot` receives it explicitly. It is released before scene building. Initial SHA and JSON no longer come from two separate reads.
- `scripts/world3d/document_open_cursor.gd`: the original `begin_document(prepared: Dictionary)` path still uses final SHA, irrespective of arbitrary extra Dictionary/JSON keys. The new explicit typed entry derives path, parsed data, and signature together from the internal source object. The final signature stage compares before constructing/publishing the document and records `metrics.final_check`.

GDScript members are conventionally private, not a sandbox against malicious in-process scripts. The boundary here is untrusted JSON/MCP/prepared Dictionaries versus the internal loader-created object. No API deserializes a snapshot or accepts independently supplied raw bytes as evidence. Parsed data still passes every existing validator and is copied before publication. Saving still receives the original SHA in `_disk_signature`; native save locking, live conflict checks and Windows atomic replacement are untouched.

The original final SHA has no deny-write/delete handle: Godot's Windows FileAccess ordinarily uses `_SH_DENYNO`. A concurrent external writer can always write after either final observation; no new await/callback window has been introduced. A stronger absolute cross-process guarantee would require a separately designed writer-excluding handle/snapshot protocol compatible with atomic replacement, outside this change. Source references: [Windows FileAccess](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/drivers/windows/file_access_windows.cpp#L204), [FileAccess SHA and buffer implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/io/file_access.cpp#L923).

## Regression results and remaining validation

`tools/test_document_source_snapshot.gd`: 15 PASS, exit 0. Tests actual cursor signature-stage mutation with identical length and exact restored Windows UTC timestamp; document stays null. Also covers final missing-file failure, missing initial file, malformed JSON, full matching signature/data/bytes, original synchronous SHA path, over-limit fallback, fake prepared keys, no post-check callback, multiple chunks/short tail and changed last byte beyond the first chunk.

`tools/test_document_open_cursor.gd`: exit 0, all existing checks PASS, including earlier late append race, no final progress callback, native and legacy validation. Existing expected empty legacy scene warning remains; no new failure.

Logs: `D:/code/rmmo_runtime/review_artifacts/document_source_snapshot_20261007.log`, `document_cursor_snapshot_20261007.log`.

A check-only invocation of `test_editor_sliced_load.gd` found a parse error in `mcp_ops.gd:296` (`entries` inference). Parent added the explicit Array type and reran parsing and the complete background GPU/HTTP test: `editor_sliced_snapshot_20261007.log`, exit 0, failures 0, actual final_check=bytes. Frozen-town `editor_load_snapshot_20261007.json` also exited 0 with 4372 records, 223 groups, 1009 sources, 555 surfaces and unchanged source SHA; the production final byte check took 227.777 ms. Another task's Godot asset publication started during the complete-load run, so its 106.346-second total and 881.494-ms maximum frame are not an isolated A/B result. The defensible performance reduction remains the independent full-file final-check probe; whole-editor responsiveness is still unfinished.
