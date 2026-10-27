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

## Original diagnosis plan (executed in the following section)

Prepare a standalone worker-thread read of the same staged 281.8 MB SCN using its actual full candidate, main-thread frame pump and explicit resource-retirement check. Keep a normal timed run separate from a GDB run; use engine09 and matching debug symbols, load symbols before releasing a file gate, then capture worker, main and render thread stacks. Do not infer the native loader's internal bottleneck from the aggregate 29.466 s span. Apply only evidenced fixes, then rerun full-map load, low-frame, unload/return and work comparisons. The staging model SHA audit and five model review are separate evidence, not replaced by this one map sample.

## Warm origin-only follow-up and largest-model investigation

`D:/code/rmmo_runtime/review_artifacts/full_native_origin_warm_20261028_01/` is a separate **origin-only** run, not a second traverse. It reused the first sample's private user/shader directory and retained dependency index (before/after index SHA `dbafdcb707ae3e6746f675bb011b5c4cf2a9433c74ddf8a9678d689a78ee3fb1`); the run reported `reference_index_hit=true`. OS cache was not controlled, and fixture checks warm files. Engine, project.godot, production/probe source snapshot, manifest and index SHA were checked before and after by the external observer; all agreed. Its process observations are in `D:/code/rmmo_runtime/review_artifacts/full_native_origin_observer_20261028_01/`.

- Entry **12,000.768 ms**, current-demand ready **23,913.161 ms**; the same initial largest model reported one compiled parse **4,693.919 ms** versus 29,465.910 ms in first full03. Because index state, reusable user/shader caches and uncontrolled OS cache differ together, this does not identify which factor caused the difference.
- Loading p99 27.609 ms, max 426.348 ms, 14 frames >50; origin observation 136 frames, p99 282.674 ms, max 621.941 ms, 99 frames >50; origin settle p99 89.664 ms, max 136.897 ms, 6 frames >50; post-ready steady p99 16.819 ms, max 139.932 ms, one frame >50 and 1% low 33.86 fps. These observer intervals and small phase samples have the same limitations as the first table.
- Final sampled queue snapshot was post_ready_steady at 34,209.945 ms: models/compiled hits 23/23, instances 1,514, specs 2,185, worker_us 35,318,812 and publication units 1,696. The first full03 last snapshot was at exit after the complete unload/return route; these work totals are not comparable.
- Owned process counters observed once per second between first/last snapshots changed by about 49.469 user CPU seconds, 10.297 system CPU seconds, 425,357 read calls and 2,212,453,235 read bytes. Those are process-wide observed counters, can omit startup/exit, and are not physical disk throughput or one-model I/O.

A separately created worker-thread single-product probe used the same staged full-native SCN, no source GLB, a running main frame pump, the same engine and full candidate, and retained then released the result. Normal sample `D:/code/rmmo_runtime/review_artifacts/guild_worker_normal_20261028_01/` reported native_read **3,676.644 ms**, total worker read **3,687.844 ms**, release **19.252 ms**, with the weak owner released. Engine, source snapshot, fixture, probe and product stat identity were checked before and after. This is an isolated workload with different renderer/user/cache/concurrency state from the map; it is not a direct explanation of full03.

The separate intrusive GDB gate sample `D:/code/rmmo_runtime/review_artifacts/guild_worker_gdb_20261028_01/` loaded the matching engine symbols, attached to its explicitly owned process and only then released the worker gate. Ten all-thread snapshots were saved, seven containing worker OS TID 66160, at collector times approximately 6.391–27.875 s. Three worker stacks showed `FileAccessCompressed::get_buffer` → `ResourceLoaderBinary::parse_variant` → ZSTD decoding, one showed `ArrayMesh::_set_surfaces` → `mesh_generate_pipelines` → waiting for shader compilation, one showed image release during texture initialization, one showed Vulkan transfer buffer allocation/AMD wait, and one showed file read within the compressed resource parser. Main OS TID 26332 appeared in repeated rendering/present stacks. GDB pauses dominate the diagnostic's 28 s wall span; sample counts cannot be turned into exclusive time shares and do not prove the map's 29.466 s cause. Raw stacks and MI log are retained in that directory.

After confirming that the initial micro probe had not recorded VSync, four fresh-process single-product runs used identical fixture, engine, source/probe identity and the warm origin run's private user directory. They kept 3D enabled and `Engine.max_fps=0`; A uses default VSync=1, B explicitly disables it:

| Run | Read wall ms | native_read ms | drawn frames during read | Approx draw fps |
| --- | ---: | ---: | ---: | ---: |
| A1 | 2,566.101 | 2,548.751 | 155 | 60.40 |
| B1 | 2,580.066 | 2,573.816 | 2,579 | 999.59 |
| B2 | 3,001.821 | 2,992.745 | 2,536 | 844.82 |
| A2 | 2,641.168 | 2,628.471 | 159 | 60.20 |

All four exited without engine/script errors and released the packed owner; their individual `guild_pacing_abba_{A1,B1,B2,A2}_20261028/` directories contain identities, process CPU snapshots and raw traces. A/B medians are 2,603.635/2,790.944 ms (two observations per arm). VSync removal alone did not reproduce the 29 s map span in this isolated workload, but the limited sample and absent full-map contention preclude broader claims.

## Full traversal diagnostic: material restore and template acceptance

`D:/code/rmmo_runtime/review_artifacts/full_native_trace_20261028_01/` used the same relocated full fixture and reused user/index, with `--monitor`, `--texture-stage-profile`, and a 10 ms trace-event threshold. It is a diagnostic workload, not an ordinary performance comparison. The externally wrapped actual command and diagnostic flag are recorded in `sample.launch.json`; the observer directory is `full_native_trace_observer_20261028_01/`. The run completed the entire route and map-exit cleanup without engine/script errors. Engine, project.godot, source snapshot, diagnostic shim, manifest and index matched before/after. Entry was 11,545.526 ms, current-demand ready 24,886.752 ms; instrumentation and cache state differ from earlier runs.

Trace contains 9,858 recorded events, 4,076 per-thread/label statistics rows, **0 dropped events**, and a 10,000 μs event threshold. Stats count all instrumented calls, including those below the event threshold. `trace_analysis_summary.json` retains the five longest events for each requested label, their same-thread nested events and the observer frame associated by event end time. Event spans overlap/nest and cannot be added indiscriminately.

The largest main-thread `mesh.gpu_restore_total` span was **822.260 ms**, ending at 16,831.141 ms in an origin observer interval of 946.142 ms. The texture-profile surface rows for the same CPU mesh ID and interval record three distinct `surface_set_material` calls: surface 4 **186.760 ms**, surface 5 **294.029 ms**, and surface 7 **308.168 ms** (sequential material wall spans, totaling 788.957 ms). A fourth recorded surface spent 31.840 ms in geometry construction. Another restore of 163.304 ms included one material binding at 162.921 ms. These identify blocking calls; they do not yet distinguish shader compilation, renderer synchronization, upload locks, driver wait or other engine internals. Do not treat the model's vertex count alone as the cause.

The return/reload template acceptance is a **different** chain: an observer frame of 211.640 ms contained `deferred.accept_template` **208.204 ms** for the large building, with same-thread nested `asset_library.cache_materials` **93.907 ms**, `asset_library.cache_pack` **91.609 ms**, and `asset_library.cache_dispose` **22.558 ms**. They belong to the outer acceptance span. Across this diagnostic, these library functions were each called 54 times; their recorded totals/maxima were 468.316/93.907 ms, 197.638/91.609 ms, and 38.702/22.558 ms respectively. Another 56.653 ms acceptance included 49.947 ms material work, itself containing 17.649 ms `asset.transfer_sync`. All values are wall spans under trace; no end-to-end benefit has yet been established.

The largest `deferred.instance_specs` events were 137.790 ms and 95.792 ms, both on pavement instances; their exact internals were not isolated by this trace. `mesh.renderer_array_capture` had 4,783 calls and 10,980.270 ms accumulated across workers, max 141.113 ms; parallel sums are not wall or CPU time. The earlier full03 publication stages included large cursor slices, but **do not** equate those stage totals to the final publication commit. The first full03 origin maximum's preceding draw/frame-setup spans and these later material/acceptance traces are distinct evidence, not proof they are the same cause.

## Current priority and remaining boundaries

1. Reproduce and isolate the `surface_set_material` stalls with the actual affected mesh/material/RID combination in an independent test, then use Godot profiler/GDB or a minimal diagnostic instrument to distinguish engine synchronization, shader/pipeline compilation, upload and other underlying work. Preserve ownership and full-material semantics. Do not repeat the already completed single-product 29 s/uncapped experiment as the primary next step.
2. Independently reproduce the large building's `cache_materials` / main-thread `cache_pack` / disposal acceptance chain and remove duplicate work or move safe preparation off the main thread; validate resource transfer and return/reload behavior.
3. Reassess the pavement instance-spec slices and the separate first-draw/frame-setup stall from matching evidence, then compare cumulative real-map load, frame intervals and work in normal non-diagnostic samples.
4. Preserve the first 29.466 s native-read sample: warm repeat was 4.694 s, but index, user/shader and OS cache conditions changed together. No single cause is proven. The 56 full03 Deferred compiled hits span the outward/unload/return route; return naturally permits a new read and this count alone does not establish unnecessary duplicate loading.

The unrelated process-wide frame-cap question was tested only in an isolated single-product ABBA; the observed lack of a 29 s reproduction there does not rule out full-map contention. The user-requested content editor adaptation remains a separate required follow-up after the material optimization work.
