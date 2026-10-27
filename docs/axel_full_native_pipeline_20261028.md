# Axel full-native model materials: first pipeline sample (2026-10-28)

## Scope and identity

- Sample `D:/code/rmmo_runtime/review_artifacts/full_native_pipeline_20261028_03/`; machine-readable summary `analysis_summary.json`, raw `sample.json`, `sample.log`, `sample.result.json`, `sample.launch.json`, and pre/post `isolation.variants.*.json` in that directory.
- Isolated full fixture `D:/code/rmmo_runtime/review_artifacts/axel_full_native_staging_20261027_01/`; manifest SHA `e54ff11993616a492c6a7e4abce21ebd5b2c40e5604b92d51907933d5d25dcb7`, target map SHA `870e9384df4923df7668967e17faddc7bfb15444100b525f664b3f65515f12d1`. It has 2,369 records, 49 model products, 1,065 reference resources and 159 declared texture/DDS files. Model logical GLBs do not exist. Authoring copies outside those logical paths are allowed.
- Private-desktop GUI engine09, normal process priority, source and engine as identified in launch file; separate private APPDATA/LOCALAPPDATA/TEMP. Controls report full_material_stage=true, map_textures=true, compiled=true, white_material=false, white_native=false, native_geometry_only=false. Texture profile was disabled. The listed script/shader/probe sources, map, settings and fixture identities agreed before/after; the engine SHA was recorded at launch only, without a post-run engine hash. `project.godot` was not included in that source snapshot. No script/engine errors, return code 0, functional_ok=true. Full fixture guard hashes metadata, map, refs and declared textures, but checks SCN by published SHA identity, size and mtime rather than rescanning 2GB payload bytes. Offline fixture construction separately reported payload SHA validation.
- This is MapLoader plus core streaming with procedural textures and full native imported model materials, without avatar, HUD, weather, gameplay and full navigation baking. The sample is **not** full-game FPS. The OS cache and derived-index state were not cleared/controlled; fixture SHA checks warmed relevant files. No physical-cold or p95 claim is warranted.
- Source timer is the existing pipeline `began` before `MapLoader.start`. Ready is three consecutive observations of current demand, queue, stream and batching settled, plus an idle queue and drained shared/retiring pixel outputs; it does not assert a GPU completion fence or first presentation.

## Results and frame intervals

- Entry: **39,078.854 ms**. Current-demand ready: **65,778.762 ms**; entry to ready difference **26,699.908 ms**, not an exclusive measured stage.
- After a real draw, the model-specific audit matched 912 imported record IDs and observed 606 scene-tree-visible resident model meshes: 887 surfaces, 523 base textured surfaces with 97 distinct textures; active materials also had 523 textured surfaces, with 55 overridden surfaces. This is not proof of camera-frustum visibility, every model, or original GLB visual equivalence.
- Frame samples are observer-to-observer intervals labelled by the ending callback. p99 uses nearest rank; 1% low is `1000 / mean(slowest ceil(1% × N) intervals)`. Small phase samples are not stable estimates. `process_ms` is an engine-published monitor, not same-row OS CPU time.

| Phase | Frames | p99 ms | max ms | >50 ms | 1% low fps |
| --- | ---: | ---: | ---: | ---: | ---: |
| loading | 24,521 | 10.154 | 917.439 | 25 | 15.93 |
| origin observation | 68 | 2,880.691 | 2,880.691 | 28 | 0.35 |
| origin demand settle | 1,085 | 77.804 | 1,791.134 | 100 | 1.87 |
| post-ready steady | 1,174 | 16.076 | 82.011 | 1 | 40.00 |
| departure | 3,159 | 20.644 | 35.546 | 0 | 40.49 |
| unload | 19,205 | 6.063 | 33.113 | 0 | 107.86 |
| return | 8,547 | 21.820 | 46.045 | 0 | 38.11 |
| reload | 3,392 | 36.512 | 187.243 | 4 | 21.96 |

The fixed probe route reached the native far departure, unload, return and reload; logged 257 crossings, 4,625 removed and 4,539 reloaded identifiers. End-of-map cleanup confirmed no map, template owners, jobs or admission leases. The interval for initial cover restoration and material audit has its own phase, separate from traversal.

## Work and budget evidence

Initial demand had **one** native model (`7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb` logical key), one native cache hit and no fallback. The recorded asset parse span was **29,465,910 μs** (wall 29,467,024 μs); the SCN payload was 281,810,329 bytes. Its complete fixed reservation was 5,450,944,511 bytes, admitted exclusively despite the 4 GiB in-flight limit; the admission record reports no blocking. This is estimated reservation, neither RSS nor a process-wide 4 GiB ceiling. Initial capture reported 2,007 meshes and 2,417,659 μs aggregate (2,906,277 μs wall). Do not add overlapping wall and CPU scopes.

At the last queue snapshot, **white_stream_exit_inflight at 190,421.459 ms**, counters read models/compiled_hits 56/56, instances 3,216, specs 6,945, captured meshes 2,695, publication units 4,910, worker_us 136,694,296 (parallel aggregate, not elapsed time), reference reads 1,635 and records 3,294. Shared pixel pool reported produced 146, shared hits 124, peak retained estimate 296,352,920 bytes, and 0 current outputs/consumers/retiring bytes. Initial ModelParse and Deferred have separate ledgers; Deferred geometry/shared pixels share a queue admission. Counters are a last-snapshot observation, not an exact post-exit count. Final retirement reports 0 admission bytes, 0 worker jobs, 0 retained templates and a freed map.

The non-detailed `stage_slow` list includes publish spans of 1,768.425 ms and 1,099.829 ms and an accept span of 915.925 ms. These are nested wall spans, not exclusive attribution. Detailed texture phase profiling was disabled, so absent stage counters cannot be treated as zero work. Preserve the raw sample and investigate the 29.466 s native-read path first, independently and with symbols, before claiming causes or gains. The 187.243 ms reload and origin long frames remain separate investigation targets.

## Failed setup attempts and validation

- `full_native_pipeline_20261028_01/isolation.variants.before.json`: fixture precheck rejected integer-valued JSON floats in old footprint budgets. Production accepts finite integral floats; the external audit was corrected and regression-tested. No GPU map ran.
- `full_native_pipeline_20261028_02/`: fixture precheck passed but the probe rejected the correct new full manifest name because its startup check still required the old map-texture fixture manifest. No map began. The probe was corrected with stage-specific filename tests.
- `full_native_preflight_20261028_01`, `_02`, `_03` preserve parse and contract runs; the final `_03` ran the extended full-stage and base-versus-active material assertions with zero reported failures. Full-fixture audit and isolated-runner Python regression evidence is recorded in the task history; the first full sample above is the first actual full-native map measurement, not an A/B comparison.

## Next diagnosis

Prepare a standalone worker-thread read of the same staged 281.8 MB SCN using its actual full candidate, main-thread frame pump and explicit resource-retirement check. Keep a normal timed run separate from a GDB run; use engine09 and matching debug symbols, load symbols before releasing a file gate, then capture worker, main and render thread stacks. Do not infer the native loader's internal bottleneck from the aggregate 29.466 s span. Apply only evidenced fixes, then rerun full-map load, low-frame, unload/return and work comparisons. The staging model SHA audit and five model review are separate evidence, not replaced by this one map sample.
