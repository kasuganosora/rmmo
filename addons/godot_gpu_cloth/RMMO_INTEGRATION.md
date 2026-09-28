# Pinned experimental dependency

Source: https://github.com/alien-life/gpu-cloth-sim
Commit: bd917afd15a8389370c7e12ec9c074555834cf68
License: MIT (LICENSE retained).

Local changes: safe uniform-set and Texture2DRD teardown; external attachment
targets and triangle colliders in solver-local space; point/linearly moving
triangle sweep with previous-frame geometry; follow before contact projection;
reference-frame translation/rotation compensation without accumulating it as
physical velocity; warm-start reference reset.
The optional reverse-contact stage computes body-vertex/cloth-face corrections
from an immutable snapshot and gathers them per cloth particle. Collider edge
pairs can also be supplied for experimental edge/edge sweeps; RMMO leaves those
disabled by default because the real skirt regression is worse despite the
isolated edge test passing. Small-buffer initialization is padded consistently.
Reproducible upstream diff: tools/patches/gpu_cloth_candidate_integration.patch.
Do not enable the editor plugin merely to run the solver. RMMO's candidate adapter
keeps source garment materials and uses a hidden control mesh for simulation.
This remains an explicitly selected experimental backend, not a release default.

`tools/test_gpu_cloth_candidate.gd` probes free/pinned cloth, external packets,
large steps, moving impact, blend targets behind the collider, and reference
motion. `tools/capture_candidate_wardrobe.gd` retains HW's original materials and
captures stand/sitting transitions against the real axis-skinned body and chair.
Run `tools/audit_garment_contacts.py --candidate` after capture. Basic probes do
not imply acceptance of the real skirt: edge/face, layer/self contacts and visual
quality remain separate gates. Source garment pins are preserved, not invented.

`tools/test_gpu_cloth_reverse_contact.gd` has positive/negative probes for face
interiors and edge-only intersections, including downward motion and reversed
winding. The body-volume audit now uses whole-surface winding, with an optional
libigl exact implementation; see `tools/requirements_geometry_audit.txt`. Nearest
face normals alone produced exterior false positives near fingers.

Self-collision now falls back to the full index buffer when proxy decimation is
disabled or produces no triangles, matching the existing peer-collision path.
`tools/test_gpu_cloth_self_contact.gd` checks two disconnected sheets on the GPU,
fixed anchors, and finite positions. `--disabled` is an expected-failure negative
control; `--proxy` and `--flip-winding` exercise the other binding and orientation.
This only verifies near-contact separation, not continuous self collision or
ruffle quality. The real wardrobe adapter still leaves self collision disabled.

The default `--candidate` contact audit now also rejects nonadjacent cloth-face
intersections using libigl (required offline dependency). The fourth-batch HW
captures fail this added gate despite passing the older body/strain checks.
`audit_cloth_self_intersections.py --directory <checkpoint>` compares source
and captured triangles and reports face IDs; shared-vertex pairs are excluded.
`capture_garment_binding_baseline.gd` isolates binding from dynamics without
overwriting the simulated captures. Rest/stand binding has zero crossings;
sit binding already has 1235. Do not treat the follow targets as collision-free.

`continuous_self_contacts` is a separate, default-off experiment. It preserves
substep-start positions before PREDICT overwrites moving pins, copies predicted
positions to an immutable snapshot, then reuses the moving-triangle vertex/face
predicate for self contact on full source topology. A final body-triangle pass
follows self contact. Contact gaps are capped at half the source point/face
distance so a global thickness cannot inflate closely spaced authored ruffles.
This is not a complete cloth solver: edge/edge contact, simultaneous conflicting
constraints and initial tangles remain unresolved. Do not enable it by default.

Probe with `test_gpu_cloth_self_contact.gd -- --sweep`, `--moving-anchor`, and
`--flip-winding`; `--sweep --legacy` is an expected failure. The no-argument test
now verifies preservation of a close source gap rather than inflating it to the
global thickness. For a separate real garment experiment, use
`capture_candidate_wardrobe.gd -- --self-contact --stand-only`, then
`audit_garment_contacts.py --candidate --self-contact --stand-only`. These captures
use `candidate_self_hw_` and cannot replace the normal candidate's evidence.

Multiple simultaneous self contacts can be revisited with `self_contact_iterations`
(1 by default, bounded to 8). `self_contact_structural_projection` optionally
continues existing XPBD constraints between rounds without resetting lambdas or
reapplying follow. Both are experimental. The corner probe
`test_gpu_cloth_self_corner.gd` verifies two simultaneous planes, fixed particles,
and finite positions; `--single` is an expected failure, `--reverse-faces` changes
face order/winding, and `--contact-structure` exercises alternating projection.
Real capture options `--self-contact --contact-iterations --stand-only` (4 rounds)
and `--self-contact --contact-structure --stand-only` (4 rounds plus structure)
write separate `candidate_self4_hw_` / `candidate_self4s_hw_` outputs. The contact
auditor uses the same flags. Latest stand crossing counts are 125 / 99, respectively;
4 contact-only rounds introduce one overstretched edge, alternating rounds do not.
Neither configuration passes the full self-intersection gate or validates sitting.

The next default-off experiments add `self_edge_contacts` and
`self_contact_mass_balance`. Edge contacts run in their own snapshot phase over
unique edges; adding their correction to a stale vertex/face correction caused
severe stretch and is retained only in failed external evidence. Mass balancing
writes one point/face contact into four participant reactions, then gathers them
without shared float writes. Fixed points can push back against free faces;
anchoring is not a collision-disable flag. Resolved sweeps must not attract
particles back to a prior contact. This is still a bounded iterative experiment,
not a guarantee of conservation under simultaneous contacts or untangling.

After self projection, both reverse body/face and forward point/body contacts
run again. Merely repeating forward contacts failed on hand/face interiors.
All new switches remain OFF by default. Real capture:
`capture_candidate_wardrobe.gd -- --self-edges --mass-balance --review-id=mass_unilateral`;
audit using `audit_garment_contacts.py --candidate --review-id=mass_unilateral`.
An explicit review ID separates versions without overwriting earlier evidence.

Run Godot `--editor --import --quit` after GLSL edits. Review tools now validate
the import cache's source MD5 and save source/compiled SHA256 manifests; launching
a script alone can consume stale SPIR-V. `test_gpu_cloth_contact_suite.py --godot
<executable>` runs eleven geometry probes including expected failures; these
must not substitute for the real skirt audit. Back views also have an extra
chair-hidden render, with collisions unchanged and no intervening solver step.

`self_contact_body_tangents` is another default-off candidate. Reverse and forward
body passes record their separating directions separately for each cloth point,
cleared every substep. Self-contact reactions use one-sided feasible directions
and recompute the effective inverse mass. A final constrained self pass follows
body projection, so separating cloth need not undo the body's clearance. These
two local directions approximate active contact; they are not a complete curved
body manifold, and remaining real skirt failures still prohibit release use.

`test_gpu_cloth_body_layers.gd -- --aligned` reproduces the body/layer conflict;
`--body-tangents` verifies both clearances simultaneously. The rotated and offset
variants avoid relying on a specific world axis or identical triangle layout.
The contact suite now contains 15 cases. Real capture adds `--body-tangents` to
`--self-edges --mass-balance`, with a distinct `--review-id`.

For first-failure diagnostics, `--trace-frames` records raw per-frame particles;
`--trace-stage-frame=N` also records internal stages without changing positions.
`--trace-until=N` stops with a partial diagnostic, never a completed pose report.
Use `audit_cloth_trace.py` for whole-mesh checks or explicitly scoped face-pair
tracking. Rebuild patches with `rebuild_gpu_cloth_patch.py --upstream <checkout>`:
the upstream repository includes the `addons/godot_gpu_cloth/` prefix; stripping
it previously caused an invalid empty-baseline replay to appear successful.


2026-09-28 联合方向补充：两半空间使用直接投影（14 项 GPU 已知值/旋转对照），并对有效质量退化时的反作用施加局部残差步长上限。原无界版本在斜接触小例中将 5.5 mm 修正放大为 5.767 m，真实坐姿也失败；不能启用为正式默认。`test_gpu_cloth_oblique_contact.gd` 只验证有限步长及身体半空间，不宣称一次完成分离。接触套件现为 16 项，真实服装审计仍独立且必需。`body_bounded` 捕获中途停止，不是完整动作证据；`body_trust` 是当前完整复测 ID。


最终复测状态：`body_trust` 重新引入手部穿透，不能采用；`self_contact_body_tangents` 继续默认关闭。前向身体投影已修正历史接触吸附及屏蔽后续未解决事件的问题，`test_gpu_cloth_body_unilateral.gd` 原向/旋转四例通过，接触套件现为 17 项。`body_release` 在关闭方向实验时完整采样身体/手/场景穿透均为 0，但坐稳自交 659 对、5 条过度拉伸边，仍未满足完整衣服验收。独立 IPC 工具仅用于离线诊断，不是游戏新物理后端。


2026-09-28 最后一轮（用户要求余项留档后转下一项）：

- `external_bend_pairs` 可接源弯曲邻接，空值沿用原拓扑推导；适配器 `source_bending` 默认关闭。相同柔度下真实坐姿没有改善。
- `interpolate_external_targets` 将外部附件目标与碰撞体统一到子步末的时刻，warm start 清除历史；原生蒙皮/关闭开关保留原行为。适配器 `interpolate_targets` 默认关闭，用 `--interpolate-targets --review-id=target_time` 重放。
- `test_gpu_cloth_target_time.gd` 直接执行生产预测 shader：固定/混合目标的六组时刻与关闭对照通过。130 帧真实裙对照仍有坐姿尖折（最大边长 1.89985、7 条过度拉伸），没有提升为默认。
- 不再为消除全部自交计数展开本轮求解器优化；保留 `candidate_visual_current_hw_` 基线及 `checkpoints/skirt-final-round/`，继续人物计划的下一项。
