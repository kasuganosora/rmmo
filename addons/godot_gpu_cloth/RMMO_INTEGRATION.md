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
