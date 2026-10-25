# Godot 4.7.2 native profiler lifetime fix

Base: official `4.7.2-stable`, commit `ed1daf0bf001b61586d9930840f2f1394092c079`.
The GDScript VM calls `_profile_count_as_native(base_obj, ...)` after invoking
the method, which may have freed `base_obj`. Reuse the `StringName base_class`
already captured before dispatch. Native-call profiling remains enabled.

From an unmodified matching engine source checkout, substitute the absolute
path to this patch. Disable automatic line-ending conversion for this command
so the resulting source bytes match the compiled source recorded in the report:

```powershell
git -c core.autocrlf=false apply --check C:/path/to/godot-4.7.2-profiler-free.patch
git -c core.autocrlf=false apply C:/path/to/godot-4.7.2-profiler-free.patch
$env:GODOT_VERSION_STATUS='stable'
python -m SCons platform=windows arch=x86_64 target=editor use_mingw=yes debug_symbols=yes separate_debug_symbols=yes dev_build=no optimize=speed lto=none d3d12=no accesskit=no angle=no -j6
```

The fixture `tools/test_profiler_free.gd` runs in an empty external Godot
project with the official remote servers profiler and native-call statistics
enabled. It frees 61440 parents with children. A successful stress run alone
does not prove the absence of a dangling access: the report also records GDB
evidence of the ObjectDB slot being empty at the helper, before and after the
fix. This patches the local diagnostic engine only.

Evidence, binary/symbol hashes, full-route checks and limits:
[`docs/axel_white_longframes_20261019.md`](../../docs/axel_white_longframes_20261019.md).

## CPU surface preparation and independent stress tests

`godot-4.7.2-cpu-surface-prepare.patch` exposes the existing native surface
packer as `RenderingServer.mesh_prepare_surface_from_arrays`. It creates
only CPU buffers and returns the native serialized surface layout accepted by
`ArrayMesh._surfaces`. It creates no RID and never sends a renderer command.
The receiving thread installs the complete surface list once. The ordinary
engine validation and packing algorithm remain unchanged, including compressed
attributes, 16/32-bit indices, LODs, custom channels and blend shapes.

`ground_batch_geometry.gd` uses the existing geometry workers to prepare these
buffers. Engines without this method retain the original upload path. Loading
tests can select `--without-prepared-surfaces` and
`--without-inflight-batch-sharing` for a comparison using the same binary.

Independent workload commands (run from the project worktree; adjust the
external output directory if needed):

```powershell
$engine='D:/tools/godot-profile-build/source/godot-4.7.2-stable/bin/godot.windows.editor.x86_64.exe'
$out='D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017'
# CPU-only: same 48 jobs for each worker count, alternating trial order.
& $engine --headless --path . --script res://tools/stress_mesh_surface_preparation.gd -- --cpu-only --workers=1,3,12 --jobs=48 --vertices=60000 --repeats=3 --output="$out/surface_stress.json"
# GPU checks must use the private-desktop runner on Windows.
python tools/run_godot_background.py --timeout 180 --log "$out/surface_stress_gpu.log" -- $engine --path . --script res://tools/stress_mesh_surface_preparation.gd -- --workers=1,3,12 --jobs=48 --vertices=60000 --repeats=3 --output="$out/surface_stress_gpu.json"
python tools/run_godot_background.py --timeout 180 --log "$out/inflight_stress.log" -- $engine --path . --script res://tools/stress_inflight_building_batches.gd -- --groups=12 --output="$out/inflight_stress.json"
```

The pure CPU surface fixture also runs from an empty external `--path` with an
absolute script path; it has no map, resource-package or project-autoload
dependency. GPU mode checks native bytes, decoded channels, LOD, bounds, blend
data and main-thread submission time. Submission timing does not measure GPU
completion. Worker wall time includes exact output comparisons; summed task
wall time must not be reported as process CPU time.

The in-flight fixture deliberately dispatches all groups before joining the
first result. It fixes the total group count rather than multiplying work by
thread count. It covers distinct geometry, cancellation of the producer or a
follower, removal after CPU completion, reparenting, exact world triangles,
independent group identities and complete pending-work drainage.

Keep production files fixed during each paired map measurement. Compare full
white readiness, phase frame times, actual process/main CPU, business counts,
geometry counts and ownership retirement; do not infer whole-map savings from
these independent fixtures.

## CPU concave collision preparation and bounds/retirement stress

`godot-4.7.2-cpu-concave-prepare.patch` adds
`PhysicsServer3D.prepare_concave_shape_data` and
`ConcavePolygonShape3D.set_prepared_faces`. The first uses the unchanged Godot
Physics BVH builder on a private shape without a RID, world or owners. The
internal result is immutable to scripts. The receiving physics thread shares
its vectors only for the exact original COW input, otherwise it builds normally.
The project never creates a body or installs a physics resource on a worker.
Standard engines retain the old shape path.

```powershell
& $engine --headless --path . --script res://tools/stress_collision_preparation.gd -- --output="$out/collision_stress.json"
& $engine --headless --path . --script res://tools/stress_procedural_bounds.gd -- --output="$out/bounds_stress.json"
& $engine --headless --path . --script res://tools/stress_decoded_retirement.gd -- --legacy --output="$out/retirement_legacy.json"
& $engine --headless --path . --script res://tools/stress_decoded_retirement.gd -- --output="$out/retirement_stress.json"
python tools/run_godot_background.py --timeout 180 --log "$out/bounds_handoff.log" -- $engine --path . --script res://tools/test_procedural_bounds_handoff.gd
```

The collision fixture keeps 48 jobs at each of 1/3/12 workers and reverses
trial order. It compares geometry, ray hit position/normal/face index,
backface mode and modified-input fallback. Bounds use the same immutable
arrays and exact old AABB. Retirement verifies immediate logical eviction,
borrowed data survival and final worker completion. These report scheduling
and worker wall time separately; they do not represent whole-map FPS.

The real white-map probe accepts `--without-worker-bvh`,
`--without-worker-surface-bounds` and `--without-decoded-background-release`
to disable this round while retaining earlier improvements on the same engine.

## Separate render thread shutdown

`godot-4.7.2-render-thread-exit.patch` fixes an exit crash with
`--render-thread separate`. Initialization hands the main RenderingDevice to
the render thread (`_assign_mt_ids`). On shutdown that thread exits first and
`DisplayServerWindows` deletes the device on the main thread, where the
`screen_free` / `finalize` thread guards return early and the device is freed
without cleanup. After the pump task completes, `RenderingServerDefault::finish`
now returns device ownership to the main thread. Safe mode is unchanged.

This patch only makes shutdown correct. In the separate model the render
thread runs a frame behind and returns `frame_post_draw` to the main thread
with `call_deferred`, so a post-draw seen while processing usually belongs to
an older frame. Project code waits through
`scripts/util/frame_presentation.gd` instead, which matches each post-draw to
its submitted frame. See rounds 156 and 157 in
[`docs/axel_white_longframes_20261019.md`](../../docs/axel_white_longframes_20261019.md).

## Glyph atlas upload snapshot

`godot-4.7.2-glyph-atlas-upload.patch` fixes a data race in both text servers
with the separate render thread model. A dirty glyph atlas is passed to
`ImageTexture::update`, whose `texture_2d_update` is queued for the render
thread, and later glyphs are rasterized into that same image in place with
`ptrw()`. The render thread then occasionally sees an empty image
(`p_image.is_null() || p_image->is_empty()` in `_texture_2d_update`). When the
caller is not the render thread, the queued update now receives a snapshot of
the atlas. Safe mode and texture creation (synchronous on RenderingDevice) are
unchanged.

## Game render thread feature tag

`godot-4.7.2-game-render-thread-feature.patch` adds the custom feature tag
`rmmo_game_render_thread`. It is true on this build unless the command line
contains `-s` / `--script`, so a project override such as
`rendering/driver/threads/thread_model.rmmo_game_render_thread=2` would only
apply to game runs on the patched engine; tests, tools and the stock engine
stay safe, and the Godot editor is always safe. The project does not set this
override (round 157).

## Self-base profiler accounting (round 166)

The patch godot-4.7.2-profiler-selfbase.patch corrects OPCODE_CALL_SELF_BASE
accounting in modules/gdscript/gdscript_vm.cpp. Script super calls now subtract
the callee duration from the caller's self time. Native super calls use the
ordinary MethodBind policy: native attribution and subtraction are enabled only
when native-call profiling is enabled. Script behavior, return values, missing
method handling and the empty native initializer path stay unchanged. This is a
diagnostic correction; it is not a game loading speedup.

Source: official 4.7.2-stable, commit
ed1daf0bf001b61586d9930840f2f1394092c079, with the existing local engine patches.
The patch was applied to the existing patched VM and built with the same flags:

    python -m SCons platform=windows arch=x86_64 target=editor use_mingw=yes debug_symbols=yes separate_debug_symbols=yes dev_build=no optimize=speed lto=none d3d12=no accesskit=no angle=no -j6

The build used GODOT_VERSION_STATUS=stable and C:/mingw64/bin on PATH. Only the
source build and an external candidate copy were updated; D:/tools/godot was not
replaced. Baseline executable and VM source were copied before applying the
patch. SHA-256 provenance:

| Artifact | SHA-256 |
| --- | --- |
| Baseline executable | 8a4931c5d30631ede2cdf7f486e01e0eda245f5f624f7c0ddf5d6088b11b7b6b |
| Candidate executable | c593823dfcb41422b805558024bc21f7a6944b626ac960064b46c4d09f65afa7 |
| VM before patch | cad523ab6c5d7a487e858e4e5294e9a61ea5de283d430138ceedf079fa9088d0 |
| VM after patch | 06bea519c0acf32d1c76adb52da6ab87dcf74ddb2bd5e09fb738616b80fd6607 |
| Patch | 370fa11b97913caaa905d345950b1110db356a31318faaa9c15b5b989ef2f883 |

The independent fixture is tools/profiler_selfbase_fixture. Its .gdignore keeps
it out of the game import graph. The runner copies it into a new external
project directory, excludes .gdignore/.godot/UID artifacts, then runs only owned
headless receiver, target and decoder processes. Native profiling off and on
are tested separately using a fresh loopback receiver port. Without --run the
runner prints a plan and performs no launch, copy or hash work.

    python tools/check_profiler_selfbase.py --engine D:/path/to/baseline.exe --output-dir D:/external/profiler-results --name selfbase_baseline --expect baseline --run
    python tools/check_profiler_selfbase.py --engine D:/path/to/candidate.exe --output-dir D:/external/profiler-results --name selfbase_candidate --expect patched --run

Use a fresh name for each run. The fixture checks five phases of eight calls,
exact base/child/leaf call counts (18/9/9), 24 signal callbacks, the nested return
value and native object identity. The verdict compares each wrapper's self/total
ratio and native row presence, not total runtime alone. Original engine A1
reproduced both script wrappers with self/total=1.0 in both modes. Candidate A1
reduced those ratios to 0.00012-0.00049. With native profiling on, super.emit_signal
changed from self/total=1.0 and no native row to 0.00166 and eight native calls;
super.get_instance_id gained its one native call. With native profiling off,
native wrappers retain callback time in self, matching ordinary MethodBind.
All target, receiver and decoder exits were zero, and all semantic and call-count
checks passed in both baseline and candidate runs.

Original evidence is under
D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017:
selfbase166_baseline_A1.validation.json,
selfbase166_candidate_A1.validation.json, their native_on/native_off summaries,
gdb166_selfbase_baseline/manifest.json and gdb166_selfbase_candidate/manifest.json.
The self-contained external build helper is build_selfbase_profile166.py; its
build.log records the successful incremental build. The portable delivery runner
passed its independent packaged-tool run, recorded in
selfbase166_delivery_candidate.validation.json: expected_result=true,
fixture_valid=true and patched_green=true. With native profiling both off and
on, the target, receiver and decoder all exited zero.

Known attribution boundaries remain explicit: typed Signal.emit is a control,
not fixed here; a native signal's inclusive duration overlaps its synchronous
script callback; native recorder overhead remains caller self. Per-function
worker aggregates and inclusive totals are not frame wall time. Do not sum them
as disjoint costs or infer that this correction removes game stalls.

## CPU mesh final-release diagnostics (round 169)

`godot-4.7.2-cpu-mesh-release-diagnostic.patch` is an opt-in diagnostic, not a
game optimization. Enable `RMMO_RELEASE169=1`; `RMMO_RELEASE169_MIN_US` defaults
to 5000. It times the complete `memdelete` of a main-thread final Variant owner
of `ground_cpu_mesh.gd`, including the automatic member destruction outside
C++ destructor bodies. The preceding `RefCounted::unreference` is not timed.
Nested phase costs overlap; remainder fields are not exclusive metadata or
member costs. Metadata keys are retained only until the root completes.

No Resource ownership, cleanup order, lock scope or thread is changed. Records
are printed after the native scope; their synchronous JSON/log cost is still
inside the caller's script release span. Never use these runs as normal timing
comparisons. Existing official installations are unchanged. The source-build
executable is now diagnostic SHA b058cb29a1c6f5f6a81648ba7c9dbc98efc798e422c4fb59eed854c7023f203d;
normal comparisons should explicitly use the c593 baseline in the external
`release169_build/baseline` directory, which includes matching verified symbols.
The original sources and complete build manifest are also preserved there.

`tools/test_cpu_metadata_retirement.gd` passed 42 checks on the baseline, with
diagnostics off, and with diagnostics on. The enabled run matched the exact
three root ObjectIDs and nested Shape/ArrayMesh destruction counts. Run GPU
checks via the never-activated private desktop runner. See documentation
section 135 and external `round169_release_native_summary` for real-map evidence
and the unmeasured child-resource cleanup remainder.

## Bounded StandardMaterial shader residency (texture stage, 2026-10-25)

`godot-4.7.2-standard-shader-residency.patch` retains up to 32 unused shader
variants in the existing exact MaterialKey map. It retains shader RIDs only,
not material/texture/mesh owners. The existing mutex protects map and idle-list
changes; compilation remains outside it and preserves the existing concurrent
creation arbitration. Active shaders never enter the eviction list. Shutdown
drains unused entries and disables retention before remaining owners disappear.

Project setting `rendering/shader_compiler/max_unused_standard_material_shaders`
is clamped to 0–256. The test-only `RMMO_STANDARD_SHADER_CACHE_LIMIT` override can
set zero for the old immediate-release behavior. Opt-in
`RMMO_STANDARD_SHADER_CACHE_PROFILE=1` prints actual creation/reuse/eviction and
idle-count statistics. The bound is a count, not a measured GPU byte budget.

Run `python tools/check_standard_shader_residency.py --engine <exe> --output
<new external directory>` for four private-desktop Vulkan processes with limits
0/2/32/0. It checks released resources by weak reference, active owners under
eviction, concurrent variant changes, and identical red/green/red rendered
pixels across independent material instances. The default limit reduced the
fixture's actual creations from 177–178 to 46; release/rebind changed from
21.9–35.7ms to 27–38µs, with all nine semantic checks passing in every process.

Candidate SHA is
`eaec8870dd5940aefff21510bbd559e316e4aa3abe2985738206a9ac0348d73c`;
matching symbols SHA is
`0b8b0e610320f06e2a0b020416cac20d4097306f6b20a4cf76a3e0dc87187ac0`.
It includes b058's opt-in release diagnostics, disabled for normal measurements.
Real-map 0/32/32/0 ABBA reduced creations from 17 to 10 and reused seven returning
variants, but did not establish an initial-load improvement or resolve every
return/reload long frame. All slow samples and diagnostic failures are retained
in `docs/axel_material_shader_residency_20261025.md`. A candidate build alone does
not establish that an installed executable was replaced.

## DDS partial BC blocks (2026-10-25)

`godot-4.7.2-dds-partial-blocks.patch` keeps each DDS mip's logical width and
height instead of padding the base extent before downsampling. Byte sizes still
round each mip to complete BC blocks. This fixes valid 7x7, 7x11 and 1254x1254
images rejected by the previous parser, without resizing authored textures.

`tools/check_dds_partial_blocks.py --engine <exe> --output <external-dir>` runs
24 BC1/BC3/BC5 fixtures. Add `--gpu` for private-desktop Vulkan upload and exact
readback of every mip. Old eaec build: 9 failures; patched 52f532 build: all 24
CPU and all 24 Vulkan cases pass. The map's offline generator still filters
non-multiple-of-four source sizes; this patch alone is not a map upload saving.

See `docs/axel_dds_partial_blocks_20261025.md` for hashes, evidence and backend
limits. Apply on top of the standard shader residency patch; preserve matching
debug symbols and the original engine before installation.

## Compact shader ownership transfer candidate (2026-10-26)

`godot-4.7.2-shader-data-transfer.patch` removes two deep copies of parsed
re-spirv data in Vulkan shader creation. It first compacts vectors with spare
capacity, then moves the parsed stage and final ShaderInfo. GPU creation,
specialization, resource ownership and cache lifetime remain unchanged.
Preserve the existing re-spirv TLS alias and other local engine patches.

`RMMO_SHADER_TRANSFER_MOVE=0` selects the old copies in the same binary;
`RMMO_RESPV_PROFILE=1` enables diagnostic decode/parse/transfer/module timings.
Both copies and transfers still run under the original RenderingDevice lock.
The patch does **not** yet move CPU preparation outside that lock.

`bench_shader_transfer.cpp` takes a directory of captured `.spv` inputs,
`copy`, `move` or `compact`, a round count, and a new external output directory.
Build it with the matching re-spirv implementation and SPIR-V headers, using
`-O3 -DNDEBUG -fno-exceptions -fno-rtti`. Compare output file hashes and vector capacity bytes as well
as timings. The independent two-stage packet is not the Vulkan driver;
microbenchmark savings are not whole-map savings.

The isolated engine15 candidate passed GPU publication/batching and 36 shader
residency checks, but its `shrink_to_fit` was a no-op under the engine's disabled
exceptions. Do not use it as evidence that capacity was preserved. The patch
now explicitly constructs and swaps only vectors with spare capacity; this
passed the same no-exception build regression. Engine22 has also passed the
GPU publication/batching and 36 residency checks. Four full-map comparisons
also passed functionally: mean full-ready 10.955 to 10.839s, reload 1% low
27.032 to 26.950 FPS. This supports retaining the work reduction, not claiming
a stable overall loading/FPS improvement. A 52.335ms return frame still needs work.
It is **not installed** in `D:/tools/godot`. Real-map timings
and unresolved long frames, including concurrent host-load evidence, are
recorded in `docs/axel_shader_transfer_20261026.md`. Do not install this candidate
based only on the independent transfer benchmark.
