# Godot engine patches

Current status (2026-10-30 08:37 +08:00): the project and the installed default use **Godot
4.8 beta1 candidate08**, with matching symbols, at
`D:/tools/godot/godot.windows.editor.x86_64.exe`. Its executable SHA-256 is
`69fccbed237845e578fdb279d9951ac92c71a29d2a1c7c660903064296cb3303`.
The installation record is `D:/tools/godot/patched_build_manifest.json`.
The [installation evidence](D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/streaming_alpha_feedback_08/installation_attempts/20261030_083604_735508/installation.json)
verifies seven executable/alias/symbol files and five version probes. Candidate07,
including its full manifest and symbols, is backed up under
`D:/tools/godot/_backup/before_08_20261030_083604_735508`.
The [4.8 adoption record](../../docs/godot_4_8_adoption_20261029.md) tracks
runtime/editor integration and remaining boundaries. The 4.7.2 sections below
are historical experiments, not instructions to downgrade or resume 4.7 work.

## Candidate09 material queue experiment (not installed)

The [four-file incremental patch](godot-4.8-beta1-material-queue-candidate09.patch)
applies **after candidate08**, not directly to the official archive. Its
[manifest](godot-4.8-beta1-material-queue-candidate09.json) records exact input/output
hashes, all 55 compiled source hashes, the isolated executable/symbols and tests.
The installed default remains candidate08.

A private worker completes its new spatial shader before registering a material
in the global dirty-uniform queue. This prevents the render thread from finding
an unfinished material and blocking on the worker's shader-version lock. Main
thread creation and updates to existing materials keep their original ordering.
Independent Vulkan tests reduce worker-phase main-frame maxima from 331–391 ms
to 6–13 ms; first-frame/update/cancellation checks pass 18/18 and native CPU
handoff passes 35/35. Those results are not a whole-map loading/FPS claim.

Fresh executable paths produce slow first map runs on both engines (112.42 /
113.15 seconds full readiness). Driver/OS caches are not isolated. The slow
samples are retained; production batch uploads still occur on main, and editor
streaming regressions remain required before installation. See the
[performance record](../../docs/axel_post_roads_performance_20261031.md).

## Reproducible 4.8 beta1 candidate08

Apply [`godot-4.8-beta1-runtime-candidate08.patch`](godot-4.8-beta1-runtime-candidate08.patch)
once to the pristine official beta1 archive. Its [manifest](godot-4.8-beta1-runtime-candidate08.json)
records **51/51 byte-exact source files**, the runtime build, matching symbols,
four red/green cutout samples and the editor regressions. Do not stack it over
candidate07 or an earlier candidate.

Two Forward+ files change after07. Feedback now precedes the built-in cutout;
feedback-enabled alpha-clip color pipelines retain reverse-Z GREATER_OR_EQUAL
instead of forcing prepass EQUAL, with color depth writes still disabled.
This lets initially transparent coarse mips request their missing detail.
Default-prepass occluder rejection and transparent holes remain correct.

Candidate08 passes scissor GPU20, editor alpha71, banner47 and final actual
WindRuntime banner48 checks. The original07 fails the two targeted scissor
checks; the08 result is pixel-identical to a full-resident reference. Alpha-hash
is in the affected code scope but not a separately rendered acceptance case.
Prepass-off hidden surfaces may request extra detail; custom FRAGMENT discard
remains outside the fix. Candidate07 native CPU tests were not rebuilt or rerun
for08. See the [cutout report](../../docs/godot48_cutout_streaming_feedback_20261030.md)
for exact evidence and boundaries; no whole-map performance claim is made.

## Reproducible 4.8 beta1 candidate07

Apply [`godot-4.8-beta1-runtime-candidate07.patch`](godot-4.8-beta1-runtime-candidate07.patch)
once to the pristine official beta1 archive identified below. This is cumulative;
do not apply it over candidate04d/05/06. Its [manifest](godot-4.8-beta1-runtime-candidate07.json)
records **49/49 byte-exact source files**, both test/runtime builds, and matching symbols.

It retains candidate06's stable command ownership and staged shutdown. The new
asynchronous observation API follows an original GPU feedback-buffer generation,
fitted texture residency, and an I/O execution epoch. A project must redraw and
verify unchanged versions after presentation before saving a thumbnail. The API
does not force mip zero, flush streaming, or wait for an I/O worker on main.

Native tests pass 148 assertions. GPU UI72, LoadJob140, mip12 and ordinary game35
pass; the game retains exactly 74 existing stride warnings. A separate 24-assertion
GPU check covers fully resident STEX with streaming disabled. The final preview
and PNG match the reference pixels. These are component correctness results,
not an axel_town loading/FPS claim. See the
[native editor report](../../docs/native_streamed_model_runtime_20261029.md).

## Reproducible 4.8 beta1 candidate04d

[`godot-4.8-beta1-runtime-candidate04d.patch`](godot-4.8-beta1-runtime-candidate04d.patch)
is a cumulative patch against the pristine official **4.8 beta1 source archive**,
commit `4d10419cacd6d3009976e8f9fd3abd970fd58018`. Apply it once to that source;
do not stack it on candidate03, 04b, the renderer delta, or a patched build.
The [manifest](godot-4.8-beta1-runtime-candidate04d.json) records the archive,
patch, executable/symbol identities, all 43 before/after file hashes, each
intermediate stage, build command, tests and unresolved boundaries.

The verified sequence is official beta1 → archived candidate03 → native CPU
capture04b → renderer velocity-copy fix → loader/WTP lifetime04d. An independent
external tree passed every intermediate before/after hash. A second pristine
tree accepted the cumulative patch and matched all **43 compiled source files
byte for byte**, including three additions. These validation trees contain the
affected files only; this delivery does not claim a fresh complete engine build.
Neither proof uses the local engine repository's Git HEAD or index as a source
baseline. Preserve LF bytes and verify the archive SHA before applying.

The additions after 03 provide scoped CPU-only native mesh capture, an RG16F
velocity-copy shader using the TAA internal extent, and ResourceLoader/worker
task lifetime and scoped-work fixes. The normal RGBA16F copy branches remain
unchanged. The renderer change preserves sampled/storage access and does not
require external OpenXR velocity textures to support transfer-source usage.

04d passes 13 lifecycle cases/46 assertions, 56 repeated cases/208 assertions,
179 original API assertions in both headless and real GPU modes, four TAA
scale/MSAA GPU cases with zero pixel mismatches, and the frozen ordinary-project
35-assertion GPU regression. The latter retains exactly 74 existing glTF stride
warnings and adds no diagnostic. These are functional contracts, not proof of a
whole-map loading/FPS improvement. The former female-world Loading timeout has
not been rerun or attributed to these fixes; a rare dying-token cleanup still
runs under the caller's outer loader mutex. The native-texture 65-assertion GPU
fixture used **04b + renderer**, and must not be relabeled as an 04d run.

To reproduce, first extract a fresh full copy of
`godot-4.8-beta1.tar.xz` outside the project. Its SHA-256 must be
`6d49c02e438935e49a12231d857b2b56131948b004d5b668bf295c9bc3b2281c`.
Do not use the existing patched engine tree as the baseline. Run the following
from the new archive's `godot-4.8-beta1` directory, adjusting the repository path:

```powershell
$ErrorActionPreference = 'Stop'
$patchDir = 'D:/code/rmmo/tools/engine_patches'
$patch = Join-Path $patchDir 'godot-4.8-beta1-runtime-candidate04d.patch'
$manifest = Get-Content -Raw (Join-Path $patchDir 'godot-4.8-beta1-runtime-candidate04d.json') | ConvertFrom-Json
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash.ToLowerInvariant() -ne $manifest.patch.sha256) { throw 'Patch SHA mismatch' }
foreach ($row in $manifest.files) {
    if ($null -eq $row.before_sha256) {
        if (Test-Path -LiteralPath $row.path) { throw "Expected absent: $($row.path)" }
    } elseif ((Get-FileHash -Algorithm SHA256 -LiteralPath $row.path).Hash.ToLowerInvariant() -ne $row.before_sha256) {
        throw "Original source SHA mismatch: $($row.path)"
    }
}
git -c core.autocrlf=false apply --check $patch
if ($LASTEXITCODE -ne 0) { throw 'Patch check failed' }
git -c core.autocrlf=false apply $patch
if ($LASTEXITCODE -ne 0) { throw 'Patch apply failed' }
foreach ($row in $manifest.files) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $row.path).Hash.ToLowerInvariant() -ne $row.after_sha256) { throw "Patched source SHA mismatch: $($row.path)" }
}
$env:PATH = 'C:/mingw64/bin;' + $env:PATH
$env:GODOT_VERSION_STATUS = 'beta1'
$env:PYTHONUTF8 = '1'
& 'D:/tools/godot-4.8-build/python-env/Scripts/python.exe' -m SCons platform=windows arch=x86_64 target=editor use_mingw=yes debug_symbols=yes separate_debug_symbols=yes dev_build=no optimize=speed lto=none d3d12=no accesskit=no angle=no -j4
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
```

The recorded executable and symbols identify the tested build. Exact source
reproduction does not promise identical PE/DWARF bytes with another toolchain,
timestamp or source path. Keep each rebuilt executable with its own symbols;
run GPU fixtures through `tools/run_godot_background.py` with isolated external
projects. Applying or compiling this patch does not install it or enable the
split-model pipeline in ordinary package builds.

## Archived candidate03

The original `godot-4.8-beta1-runtime-candidate.patch` and its JSON manifest are
preserved unchanged, including their historical pre-installation status. They
record 29 before/after hashes against the same official archive. Candidate03
includes the frozen-type registration fix: bind the collision preparation API
during PhysicsServer3D class initialization, then register its CPU callback.
The reusable `check_glyph_upload.py` covers four glyph update paths with and
without mipmaps in safe/separate render modes, checking actual thread identity
and final GPU atlas bytes. Only compiled dynamic-font servers are exercised;
Dummy is explicitly skipped.

## Historical 4.7.2 native profiler lifetime fix

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

## Vulkan shader CPU preparation candidate (2026-10-26)

Apply `godot-4.7.2-shader-cpu-prepare.patch` after the compact transfer patch.
It moves per-call container decoding, reflection and re-spirv preparation out
of the RenderingDevice mutex. Sampler lookup, GPU creation and RID publication
remain locked. Reflection is built once; no shared parsed-shader cache is added.
Other backends retain their existing driver entrypoint and are not validated here.

`RMMO_SHADER_PREPARE_UNLOCKED=0/1` compares lock scopes in the same binary.
The final patch defaults to locked preparation; explicitly set `=1` to opt in.
Earlier engine03 experiment artifacts defaulted to unlocked preparation, with
their original source preserved separately. Their explicit 0/1 comparisons
remain valid for those recorded binary identities.
`RMMO_RESPV_PROFILE=1` adds prepare/commit and decoded-buffer fields to the
existing native record. Diagnostic total is prepare + commit, excluding the
intervening lock wait; it is not main-thread CPU or complete API wall time.

Run `res://tools/stress_shader_creation_lock.gd` through
`tools/run_godot_background.py`, with `--inputs-dir=<external captured .spv dir>`,
`--output=<new external JSON>` and `--rounds=32`. Two workers partition the same
16 largest inputs, creating/freeing 512 RIDs. Normal mode has no per-frame file
writes. `--gate-file` and `--progress-prefix` are debugger-only controls and
must not be enabled in normal timing comparisons.

`res://tools/test_shader_preparation_failure.gd -- --output=<external JSON>`
corrupts only a local copy's second stage, then retries into the same placeholder.
Expect exactly four malformed-SMOL-V errors and four preparation-return errors;
all other errors are failures. The old driver instead reports four `!shader_id`
return errors. Do not suppress arbitrary native errors in a runner.

The isolated engine03 passes GPU publication/batching, 36 residency checks,
failure/retry checks and an actual two-worker debugger suspension comparison.
The Windows debugger is still all-stop; the owned fixture uses balanced Win32
thread suspension to isolate one worker. See `docs/axel_shader_cpu_prepare_20261026.md`
for hashes, normal map comparison, retained failures and memory boundaries.
Cached variants are still created sequentially within each ShaderRD group.

The normal-map `map12` repeat had no observed competing Godot/Blender/compiler
processes. It still did not establish overall benefit: mean full-ready was
10.896s locked versus 11.242s unlocked, and reload 1% low was 26.931 versus
24.657 FPS. Preserve this candidate and its independent lock-decoupling proof,
but do not install it on the basis of the microbenchmark alone.

## Collision debug appearance must not rebuild physics (2026-10-26)

`godot-4.7.2-shape-debug-refresh.patch` makes Shape3D debug color/fill setters
explicitly call the base debug-cache invalidation, retaining change signals.
Virtual dispatch previously reached ConcavePolygonShape3D's full physics update.
In DEBUG_ENABLED node binding, this rebuilt an already prepared BVH on the main
thread merely to propagate the default collision debug color.

`RMMO_SHAPE_DEBUG_REFRESH_ONLY=0/1` controls the old/new path in one binary.
`tools/test_collision_debug_refresh.gd` runs headless in an empty external project
with `--output=<external JSON>` and optional `--cells=96`. It checks shared shape
notifications, no-op edits, RID identity, ray queries and actual geometry/backface
changes. The independent GDB fixture counts 40 to 3 native BVH builds while all
40 debug refreshes remain; four stress runs each pass 49 assertions. Real GPU
collision/product/material regressions add 149 passing assertions.

See `docs/axel_collision_debug_refresh_20261026.md` for compiled identities,
the failed winding fixture retained before correction, and real-map evidence.
The full-map comparison fixes shader CPU preparation to its locked control so
that only collision debug invalidation changes. All four map07 samples overlapped
other Blender/Godot work; they are retained, not a stable performance claim.
The final default-config engine09 passes another 198 checks, but its first map
smoke test took 22.334s without sufficient attribution. Default installation is
therefore pending; the ordinary D:/tools/godot installation remains unchanged.

## Active Vulkan module sharing and complete shader decode (2026-10-28)

On the existing build09 patched source, apply in this order:

1. `godot-4.7.2-shader-module-share.patch`
2. `godot-4.7.2-shader-decode-length.patch`
3. `godot-4.7.2-shader-module-source-key.patch`

The first patch shares identical source VkShaderModules within one device while
owners are alive. `RMMO_SHADER_MODULE_SHARE=1` opts in; the default is off.
The third uses exact original compressed bytes and complete codec parameters
only for successfully decoded, unmodified `store_respv` stages. Opt in with
`RMMO_SHADER_MODULE_SOURCE_KEY=1` as well. All other cases retain the raw-key
path. Both representations share the same per-device 64 MiB key-vector-capacity
and 8192-entry limits. This is not an RSS/VRAM ceiling. Last-owner release drops
the entry; RID, reflection, layout and per-pipeline specialization remain private.
Do not enable source-key without the complete-decode fix.

The decode fix uses the length returned by the existing single Zstd call and
rejects short/error results; raw input must match the declared output length.
It adds no second decode, scan or hash. This fixes the shared CPU function used
by Vulkan, Metal and D3D12, but the latter two GPU backends were not tested here.

For the CPU regression only, additionally apply
`godot-4.7.2-shader-decode-contract-diagnostic.patch`. Copy the
`shader_decode_contract` fixture to an external directory and run its script
headless with `RMMO_SHADER_DECODE_TEST_API=1`. The original decoder with the
same bridge expects `RMMO_EXPECT_DECODE_RED=1` (6 passes, 8 expected failures);
the fixed decoder without that flag expects 14 passes. Without the API flag the
fixture exits 2. The bridge is not required for the production optimization.

`test_shader_module_registry.cpp` compiles against the patched engine include
root with `-std=c++17 -pthread -UNDEBUG`; its compile-time guard prevents silent
removal of assert-based workload. It checks collisions, limits, failure rollback,
and concurrent raw/source owners. The `shader_module_contract` GPU fixture must
also be copied outside the project and run with `tools/run_godot_background.py`.
Its explicit test controls and exact expected native errors are recorded in the
report below; never enable test injection in normal map samples.

The isolated GREEN binary passed four 43-check GPU ownership modes, 97 material
publication checks and 18 preparation-failure/retry checks. Full-map raw-key
workload comparisons reduced source module calls 2559 to 1681, but did not prove
a stable loading or low-frame benefit. Source-key full-map results are separate.
Neither candidate is installed. Patches are delivered as LF; applying them
reproduces the candidate code modulo CRLF normalization, not byte-identical
original source hashes. See [module report](../../docs/axel_shader_module_share_20261028.md)
and [decode report](../../docs/axel_shader_decode_contract_20261028.md) for exact
binaries, evidence, retained failures, test controls and limits.

## Editor CPU texture encoding and local device publication (2026-10-28)

On the GREEN overlay described above, apply
`godot-4.7.2-main-device-publication.patch` and
`godot-4.7.2-per-call-cpu-compression.patch`. Local RenderingDevices never become
the global device, and the main device is published only after initialization.
`Image.compress_from_channels_cpu` selects the existing CPU encoder per call,
without mutating global GPU settings or creating a RenderingDevice.

The isolated candidate passes the original Compatibility GPU crash fixture,
CPU/legacy output comparisons, GDB constructor counts (CPU 0 / GPU 1), main RD
identity checks on Forward+, and 32 actual editor DDS HTTP/UI checks. These are
functional tests, not a map performance result or an attribution of old crashes
without stacks. The binary is not installed. Copy `cpu_texture_compression` to
an external directory for the private-desktop probe. See
[engine contract](../../docs/editor_dds_engine_contract_20261028.md) for exact
identities, commands, retained runner failure and remaining acceptance work.

## Native memory timeline, Godot 4.8 (2026-10-31)

Apply `godot-4.8-beta1-debug-trace-candidate17.patch` after the candidate16r2
source identified by `godot-4.8-beta1-instance-property-candidate16.json`.
The accompanying candidate17 manifest records every before/after source SHA,
build command, executable/symbol hashes, and validation artifacts. The patch
is the complete trace addition relative to 16r2, not an incremental r2-to-r3
patch. Source snapshots and failed earlier probes remain in external evidence.

`Performance.debug_trace_*` exposes bounded per-thread memory recording and
explicit stop/export. Scalar writes have no logging mutex; first registration
and optional distinct task-name metadata may allocate. Native scopes cover
the main loop, worker enqueue/execute/wait, resource loading, material binding,
render synchronization, pipeline waits and CPU-side Vulkan calls. Capture is
off by default and existing optional optimization switches remain independent.

The validated diagnostic executable and matching symbols are installed at
`D:/tools/godot/debug-trace-4.8/`. The ordinary default candidate10 is unchanged.
This build inherits the earlier diagnostic candidates and does not replace
normal-engine performance acceptance. Use the reusable component runner and
offline decoder described in [debug timeline](../../docs/debug_timeline.md).
Three 88-check contracts, equal-work benchmarks, private-desktop Vulkan,
offline decoding and CSV dependency checks passed. No map loading improvement
is claimed by this instrumentation delivery.

## Render phase timeline, candidate18 (2026-10-31)

Apply `godot-4.8-beta1-render-trace-candidate18.patch` after candidate17r3.
It adds 40 fixed labels beneath rendering and the main loop: scene/resource
updates, viewports, culling, shadows, instance data and draw lists. It changes
no rendering, quality, cache or scheduling policy. Draw-list task/context
fields are candidate element count and pass mode, not worker IDs or actual
draw-call counts; viewport scopes use the viewport RID as a scalar identity.

The manifest records the isolated executable, source hashes and validation.
One 88-check CPU contract, equal-work probe and private-desktop Vulkan probe
passed; 854 GPU events had no drops, orphan ends or crossing scopes, and the
rendered pixels matched. Three boundary spans were left incomplete. The
existing decoder accepts the added labels without an update. The full-map
diagnosis and retained cache restart evidence are tracked in
[the performance log](../../docs/axel_post_roads_performance_20261031.md).
Default candidate10 and the installed candidate17 diagnostic entry remain
unchanged. This instrumentation is not a claimed performance optimization.

## Per-draw descriptor scratch, candidate19r2 (2026-10-31)

Apply `godot-4.8-beta1-descriptor-scratch-candidate19.patch` after candidate18.
`RenderingDevice::draw_list_draw` uses a bounded stack array instead of a TLS
vector that was cleared/resized for every draw. The existing recorder copies
the IDs synchronously; binding order, resource lifetimes and checks are retained.
The patch reproduces the saved build source after newline normalization.

`tools/test_draw_descriptor_scratch.gd` exercises sparse bindings, material and
pipeline switches on a real local RD. Four visible stripes verify earlier queued
bindings survive scratch reuse. Six private-desktop processes in ABBAAB order
passed 53 checks each with equal draw/binding work and pixel hashes. Per-process
encoding medians and all slower samples are retained in the linked performance
log. This candidate has not replaced the default engine; component gains are not
a claim of full-map loading or low-frame gains. See its JSON manifest for the
exact executable, parent source and external evidence.

## Frame-end timeline, candidate20 (2026-10-31)

Apply `godot-4.8-beta1-frame-trace-candidate20.patch` after candidate19r2.
It appends 22 labels for RD frame preparation, graph dependencies/sorting,
barriers, driver command replay, submission and resource disposal. Two scalar
marks per draw list report actual draw/binding instruction counts. An indirect
instruction can represent multiple hardware draws; counts include canvas and
postprocessing. API wall times are not GPU timestamps.

The real-GPU component passed 53 checks and exactly matched 98,308 recorded draw
instructions. Three full-map lifecycle captures passed with no dropped events,
orphan ends, crossing spans or task-name conflicts. The saved-parent patch check
matches the built sources after newline normalization. See the manifest and
performance log for retained slow frames, the uninstalled binary and evidence.
This diagnostic adds no parallel scheduling and does not claim a map speedup.
