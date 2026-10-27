# Full native shader-cache I/O: GDB and Trace evidence (2026-10-28)

The normal prepack A1 finished, but B1 exited before ready with a Windows heap-corruption process exit; Windows recorded an earlier access violation. The candidate remains disabled by default, and the failure does not yet identify its cause. See `axel_native_worker_prepack_20261028.md` for the preserved A1/B1 evidence.

## One instrumented full-map candidate-on run

Evidence: `D:/code/rmmo_runtime/review_artifacts/full_map_gate_gdb_on_20261028_01/` (`gdb_stacks.jsonl`, `sample.json`, `status.json`, launch, source/fixture identities). The private desktop used engine09, full staged fixture and reused `full_native_pipeline_user_20261028_03`; `diagnostic_full_native_worker_prepack` and the actual candidate control were true. Source, engine and fixture snapshots matched before/after. The source overlay adds a gate before `MapLoader.start`; overlay import cache differs from the repository. This is not an ordinary timing sample.

GDB loaded matching symbols before releasing the gate and captured 28 all-thread samples. It detached after its 120 s sampling window; subsequent route execution is outside exception coverage. No exception was captured during the attached interval, while the full route later completed with `failures=0` and process exit 0. This does not invalidate the retained B1 crash or exclude a race.

The two sampled main-thread chains both reached `ArrayMesh::surface_set_material → BaseMaterial3D::get_rid → _update_shader → shader_set_code → ShaderRD::_compile_version_start → _load_from_cache → FileAccessWindows::get_buffer → ZwReadFile`. They demonstrate shader-cache file reads at those instants, not shader compiler or driver latency, nor that the two calls use the same material.

The per-process unix/ticks anchor supports approximate matching within milliseconds:

- Sample 26 (~140,642,149 µs) lies inside `shadow.build` for `obj_1019` (140,633,428–146,443,602 µs), specifically its `bind_0_us` interval. It is not the following CPU mesh restore.
- Sample 27 (~146,551,631 µs) lies inside `mesh.gpu_restore_total` (146,459,956–153,202,832 µs), frame 20484, CPU mesh ID `-9223370312106615150`; the matching surface 4 record spans 146,460,961–152,181,634 µs including geometry; its material call starts at 146,461,264 µs, material ID `-9223370365525271366`, empty albedo RID. The stack is inside that call. The recorded multi-second spans contain debugger pauses and do not measure normal operation.

At those stops, several worker threads were in `FileAccessCompressed` / Windows reads; another worker was in `mesh_surface_get_arrays` through `CommandQueueMT::push_and_ret`, and other WorkerThreadPool threads were asleep. These point-in-time stacks do not establish causal lock contention. No sampled worker stack contained the first-pack `ClassDB` default cache path; this does not rule out that race. IDs are process-local and cannot be equated with the earlier 822 ms sample.

## Next diagnostic

A candidate-off, origin-only, actual full fixture run was prepared to enable the engine09 `RMMO_FILE_TRACE` plus existing Trace and texture profiling. Associate per-file begin/end/thread and read/open counters with same-run material/shadow spans; inspect cache file paths, byte sizes and repeated accesses. Record that tracing changes execution and that the private APPDATA/LOCALAPPDATA reside on D:, whereas the user's normal app cache may reside on C:. Do not generalize D: behavior to production, move caches, or change shaders without evidence. The resulting run is recorded below.

Storage context from read-only Windows inventory: C: is Disk 1 Samsung SSD 970 NVMe (SSD); D: is Disk 0 TOSHIBA HDWE160 (HDD). This test's private APPDATA is on D:. `project.godot` identifies the game as `rmmo` without a custom user directory, so the regular default `user://` is expected under C: AppData. The GDB stack alone does not include the shader-cache pathname: file tracing must establish whether the observed accesses really land on D:. Do not present a private HDD result as a measurement of the regular NVMe configuration.

## Candidate-off origin diagnostic with file trace

Evidence: `D:/code/rmmo_runtime/review_artifacts/full_shader_file_trace_origin_20261028_01/`, including `sample.json`, `engine_file_trace.tsv`, `shader_io_analysis.json`, `sample.launch.json`, `sample.result.json`, and `diagnostic_identity.json`. This run used full native materials, `--origin-only`, `--texture-stage-profile`, existing `--monitor` and `RMMO_FILE_TRACE`, with candidate prepack off. Engine/source/project/tool SHA and fixture/settings/map checks match before/after; no reported script errors, probe failures or dropped trace events (3,734 events, 1,893 stats rows). Entry was 11.335 s and origin demand ready 23.969 s, but this is one instrumented run, not a p95 or normal performance result.

Of the file trace rows, 145 successful `user://shader_cache/` reads used 145 distinct paths, 24,326,516 bytes, 3,174 `get_buffer` calls and 584.254 ms cumulative `fread` wall time across all threads; the main thread contributed 101 opens, 10,621,568 bytes and 376.036 ms. This is summed thread work, not elapsed critical-path time. A further pipeline-cache file was read separately; failed-open and incomplete-handle limitations apply. The per-open row is written on close, so only completed FileAccess handles are counted. Its begin/end describes the whole open lifetime, and `read_us` records only wrapped `fread` calls, not open, seek, decoding, or all cache loading work.

The `user://shader_cache/...` paths resolve under this sample's private `D:/code/rmmo_runtime/review_artifacts/full_native_pipeline_user_20261028_03/roaming/Godot/app_userdata/rmmo/shader_cache/`; an example resolved file exists and its 112,840-byte size matches the trace. This establishes D: for the sampled private configuration, not regular game AppData on C:.

In frame 3215, surface 4/5/7 of CPU mesh `-9223370876408275239` took 115.137/151.313/199.871 ms in material calls. For each, two successful shader-cache handles on the same main thread opened and closed wholly within the material span. The two file sizes were approximately 113 KB and 519 KB each; their combined `fread` times were only 0.571/0.476/0.804 ms respectively. The exact paths, sizes, timestamps, counts and process-local material IDs are in `shader_io_analysis.json`. Another 41.461 ms `shadow.build` for `obj_1019` similarly enclosed two shader-cache handle lifetimes; the GDB and file-trace runs are different processes and must not equate RIDs.

The matching engine source shows `_load_from_cache` reads variant bytes and then synchronously calls `shader_create_from_bytecode_with_samplers` per enabled variant before returning and releasing the file handle. Thus the near-complete overlap of a file's lifetime with the material span does not imply the interval was spent reading disk. The `fread` counters exclude substantial other work within the span, but do not on their own identify precisely where it went; bytecode creation, driver and synchronization require further evidence. There is no repeated reopen of the same cache path in this completed origin sample, so an identical-path I/O deduplication claim is unsupported.

## Isolated engine timing by container

An opt-in diagnostic engine was built in `D:/code/rmmo_runtime/review_artifacts/shader_profile_spans_20261028_01/`; the six tracked engine09 source files matched the build09 hashes before building. The patch adds prepare/commit timestamps and Godot thread IDs to the existing `RMMO_SHADER_BUILD` line, only when `RMMO_RESPV_PROFILE=1`; it does not change shader behavior or the default unlocked setting. The two temporarily replaced build-tree files were restored and verified, and engine09's original EXE and symbols SHA remain unchanged. The separately stored diagnostic EXE SHA is `4757c1e891bb92a48b26e2f903dba4f54f3b0af550387b2f1e57740f1916ea71`; the symbols SHA is `d06859926b9d0f2912a2a854c35dc8bfe1c626aa5fa49bfa9b728e2e58a252ff`. Build flags, identities, source copies and patch are preserved beside it. This is a distinct instrumented binary, not an engine09 timing comparison.

The separate private-desktop error-path fixture passed 18/18 with the exact eight expected error lines, four recovery attempts, and 268 successful BUILD lines whose timestamp intervals matched their durations and included valid thread IDs. The fixture regenerates input, whose SHA differs from the earlier test, so it establishes the error-path contract, not identical-byte comparison.

`origin_01/` contains the actual full origin diagnostic with `RMMO_RESPV_PROFILE=1`, `RMMO_SHADER_PREPARE_UNLOCKED=0`, file trace and the existing Trace / texture profiling; both native template reuse and worker prepack controls report false. Source / engine / fixture / settings matched before and after; functionality passed with no unexpected errors. There were 3,685 Trace events, zero dropped, and 1,360 well-formed BUILD rows. `respv_analysis.json` lists every matched row, using the real material start `end_us - material_us`; a BUILD is counted only if its prepare and commit are both fully within the same main-thread material span. Edge overlaps and other threads are excluded separately.

For one CPU mesh in frame 3837, each of surfaces 4, 5 and 7 fully contained **28 container builds**:

| Surface | Material span ms | Prepare ms | Commit ms | Of commit: module ms | Unattributed ms | Largest individual container ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 2,585.879 | 168.123 | 524.649 | 523.208 | 1,893.107 | 53.228 |
| 5 | 3,711.369 | 173.304 | 564.645 | 561.789 | 2,973.420 | 65.892 |
| 7 | 3,907.379 | 170.484 | 595.508 | 593.962 | 3,141.387 | 55.328 |

The largest individual containers' `module_us` were 37.708 / 51.151 / 39.995 ms respectively. `module` is a subset of commit; `decode`, `parse` and parts of `transfer` are nested in prepare, and remaining transfer is nested in commit. They must not be added on top of prepare + commit. The gaps between consecutive BUILD intervals in these surfaces total 1,655 / 2,864 / 2,273 ms; they include logging and other outer work, not a demonstrated single cause. `unattributed` also includes non-container work and the perturbing synchronous log prints.

Instrumentation made the run substantially different: entry 36.184 s and demand ready 89.946 s are **not** ordinary game measurements or a performance regression claim. This run establishes repeated per-variant work on these material paths and quantifies the instrumented containers; it does not prove the 115–200 ms ordinary-frame breakdown, diagnose the residual, or establish which shader code, driver call or logging caused it. A lower-overhead diagnostic or bounded off/on comparison is needed before deciding how to optimize the non-container remainder.

## Buffered native diagnostic preparation

The inline `print_line` diagnostic above heavily perturbed the measured material spans. A separate buffered diagnostic build is stored under `D:/code/rmmo_runtime/review_artifacts/shader_profile_buffered_20261028_01/`; it does not replace engine09 or the installed engine. It retains existing immediate profile mode and default-off behavior. With explicit `RMMO_RESPV_PROFILE=1` and `RMMO_RESPV_PROFILE_BUFFERED=1`, successful shader commits write numeric timings and thread IDs into an append-only fixed-capacity buffer. The slots are never overwritten; overflow is counted. Shader names are deliberately omitted, so these records are anonymous and cannot identify a variant independently.

After renderer teardown and worker-pool join, normal cleanup seals the buffer and writes it once to the explicit external path. Published slots are read with release/acquire ordering. The footer records capacity, written/attempted counts, overflow, observed late-after-seal lower bound and whether writers remained after a bounded wait. An abnormal exit may produce no file; unknown late writers after the footer cannot be excluded merely by a zero lower bound.

An independent C++ test repeated concurrent unique slots, overflow, pending publication during sealing and closed-state cases 50 times. A separate static review checked the state and cleanup ordering. Private-desktop tests of profile off and buffered on each passed 18 checks, with four expected invalid-input/recovery cases and the precise eight expected error lines. The off run emitted neither BUILD lines nor a buffer; the on run emitted 268 well-formed records with footer `attempted=written=268`, `dropped=0`, `incomplete=0`. These tests generated their own shader input and do not compare identical bytes with prior runs. Build09 original EXE/symbol hashes were unchanged and build sources restored; diagnostic EXE SHA `d5d65563ae45bf2639cac285d91a002ad96f6efe2ae53c68f13c7395694463b7`, symbols SHA `f04a554930c6b0655a20f1d64cb22d886fc33c6055482580faa0339d46d12906`.

The pending origin wrapper explicitly rejects either experimental native candidate and verifies actual control values and the single final footer. Missing, truncated, dropped, incomplete or observed late records are not accepted as a complete diagnostic. It disables the previous file-I/O trace, while retaining existing Trace and texture profiling, so it still requires a separate normal sample for performance conclusions. The full fixture manifest is now `b350e4ded3c3666d4768f7695337fdbb0fc5147423d278a02c94d936a4ff6fbb`, distinct from the older samples' manifest; the corresponding changes concern the fixture descriptor/manifest, and the map and SCN are unchanged per the staging audit. The buffered full-origin run after the normal ABBA is recorded below.

## Buffered full-origin diagnostic

After the normal direct-native ABBA, one full-material origin-only diagnostic ran with both experimental candidates off, buffered profile on, shader prepare unlocked off, texture profile and existing Trace on, and file-I/O trace off. Output: `D:/code/rmmo_runtime/review_artifacts/shader_profile_buffered_20261028_01/origin_01/`; host samples are in `origin_observer_01/host.json`. This sample uses the newer `b350e4...f6fbb` manifest, not the earlier fixture manifest.

The run completed with no unexpected errors, and source/engine, settings, map and fixture identities matched. The footer reports 1,388 attempted and written records, zero observed dropped, incomplete and late; the 1,388 rows passed timestamp/field validation. There were 3,834 Trace events with zero dropped. Only successful commits are represented; the late count is a lower bound at flush. Entry was 18.134 s and current-demand ready was 40.239 s, but this instrumented single sample is neither a normal comparison nor a p95. The 29 approximately 1 Hz host snapshots observed Blender in multiple samples, with a maximum single-process CPU rate of 147.05% of one core and maximum sampled system CPU 64.9%; these coarse observations cannot establish precise per-frame causality or an idle machine.

In frame 3005, the same CPU mesh's surfaces 4, 5 and 7 each fully contained 28 anonymous successful container prepares and commits on the same main thread. Matching uses the actual material interval `end_us - material_us` through `end_us`; partial overlaps are not included.

| Surface | Material span ms | Prepare ms | Commit ms | Of commit: module ms | Unattributed ms | Largest individual container ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 780.499 | 135.223 | 638.989 | 636.990 | 6.287 | 55.746 |
| 5 | 762.274 | 130.786 | 600.996 | 599.000 | 30.492 | 59.829 |
| 7 | 1,505.332 | 131.165 | 737.016 | 734.837 | 637.151 | 60.710 |

The largest individual container in each of these three spans had module intervals 45.499 / 52.320 / 51.401 ms respectively. In the matched engine source, `module_us` wraps `vkCreateShaderModule` per shader stage, and includes any driver work or scheduling wait inside that call. It is nested within commit, not extra time. The `parse_us` portion of prepare was 113.794 / 109.298 / 109.769 ms, also nested. Surface 7's large remainder remains unidentified; no source establishes that it has the same cause as surfaces 4 and 5. The named variant is not recorded, and the observed module costs cannot be generalized as normal-engine timing under all workloads. The complete per-container data and partially overlapping exclusions are in `respv_analysis.json`.


## Correction: open duration and shadow reads

The original file trace also records `open_cost_us` in its ninth column (zero-based index 8); the old analysis did not separately include it. The same-run per-surface and shadow open/read totals, actual timer scope, containment rules, and the engine/user-directory boundary are documented in [the native acceptance follow-up](axel_native_acceptance_20261028.md#旧-engine09-文件-trace-的-openread-口径补正). In that engine09 diagnostic the three measured material spans have less than 1.7 ms of open plus fread/check each, but the `obj_1020` shadow span includes 17.813 ms of fread/check and 0.987 ms of open. Do not generalize the earlier low-read observation to the shadow or to another engine run.
