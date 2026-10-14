"""Aggregate five bridge reviews without modifying maps or source evidence.

Run after review/publication; rerunning replaces only model_reviews/*.json/*.md.
--dry-run prints the index without writing. Missing/stale evidence stays pending.
visual_acceptance.json must explicitly approve each bridge, with id, passed,
frozen_payload_sha256, and views near/mid/far/detail containing path, sha256,
reviewed:true and passed:true. Add lod_assessment {status:'passed', decision,
reason}; this is a reviewer decision, never inferred from image existence.
Global candidate_sha256 binds acceptance and runtime to the saved candidate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

DEFAULT_OUT = Path("D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014")
VIEWS = ("near", "mid", "far", "detail")


def identity(path):
    p = Path(path) if path else None
    result = {"path": str(p) if p else "", "exists": bool(p and p.is_file())}
    if result["exists"]:
        digest = hashlib.sha256()
        with p.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        result.update(sha256=digest.hexdigest(), bytes=p.stat().st_size)
    return result


def read(path):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8-sig"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def stage(passed, reason, failed=False):
    return {"status": "passed" if passed else "failed" if failed else "pending", "reason": reason}


def by_id(rows, key):
    if isinstance(rows, dict):
        return rows.get(key, {})
    return next((r for r in rows if isinstance(r, dict) and r.get("id") == key), {})


def approved(row):
    return row.get("passed") is True or row.get("status") == "passed"


def same_sha(a, b):
    return isinstance(a, str) and len(a) == 64 and a == b


def verified_file(row):
    actual = identity(row.get("path"))
    return actual, actual["exists"] and same_sha(actual.get("sha256"), row.get("sha256"))


def aggregate(out):
    paths = {"build": out / "build.json", "visual": out / "visual_acceptance.json",
             "runtime": out / "runtime/result.json", "publication": out / "publication.json"}
    paths["resources"] = next((p for p in (out / "resource_audit.json", out / "bridge_assets/resource_audit.json")
                               if p.is_file()), out / "bridge_assets/resource_audit.json")
    docs = {k: read(p) for k, p in paths.items()}
    build, audit, visual, runtime, publication = (docs[k] for k in ("build", "resources", "visual", "runtime", "publication"))
    if not audit and isinstance(build.get("bridge_asset_audit"), dict):
        audit = build["bridge_asset_audit"]
        paths["resources"] = paths["build"]
    candidate = identity(build.get("candidate") or audit.get("map", {}).get("path"))
    candidate_sha = build.get("candidate_sha256")
    current = same_sha(candidate.get("sha256"), candidate_sha)
    audit_current = current and same_sha(audit.get("map", {}).get("sha256"), candidate_sha)
    build_ok = current and build.get("phase") == "candidate_complete" and build.get("failures") == 0
    runtime_ok = (current and runtime.get("phase") == "complete" and runtime.get("status") == "passed"
                  and runtime.get("failures") == 0 and same_sha(runtime.get("map_sha256"), candidate_sha))
    visual_current = current and same_sha(visual.get("candidate_sha256"), candidate_sha)
    formal = identity(publication.get("formal_path"))
    pub_checks = publication.get("checks", [])
    formal_ok = (publication.get("published") is True and publication.get("failures") == 0
                 and bool(pub_checks) and all(c.get("passed") is True for c in pub_checks)
                 and same_sha(publication.get("candidate_sha256"), candidate_sha)
                 and same_sha(formal.get("sha256"), publication.get("formal_sha256")))
    compact_records = [r for n in read(formal["path"]).get("nodes", [])
                       for r in n.get("extras", {}).get("rmmo_records", [])] if formal_ok else []
    provenance = {k: identity(p) for k, p in paths.items()}
    reports = []
    for number in range(1, 6):
        key = f"axel_bridge_{number}"
        row = by_id(audit.get("bridges", []), key)
        accepted = by_id(visual.get("bridges", []), key)
        actual_resource, resource_match = verified_file(row.get("native_resource", {}))
        native = row.get("native_resource", {})
        resource_match = resource_match and same_sha(native.get("sha256"), native.get("expected_sha256"))
        frozen = row.get("frozen_payload", {})
        issues = audit.get("errors", [])
        cpu_ok = (bool(row) and audit_current and audit.get("passed") is True and not issues and resource_match)
        lod = accepted.get("lod_assessment", {})
        acceptance_bound = visual_current and same_sha(accepted.get("frozen_payload_sha256"), frozen.get("sha256"))
        lod_ok = acceptance_bound and approved(lod) and bool(lod.get("decision")) and bool(lod.get("reason"))
        images = []
        for view in VIEWS:
            evidence = accepted.get("views", {}).get(view, {})
            actual, match = verified_file(evidence)
            reviewed = evidence.get("reviewed") is True and evidence.get("passed") is True
            images.append({"view": view, "approval": evidence, "actual_file": actual,
                           "stage": stage(match and reviewed and acceptance_bound,
                                          "Explicit review, image hash and candidate identity must all match.")})
        visual_ok = (visual.get("passed") is True and approved(accepted) and acceptance_bound
                     and all(i["stage"]["status"] == "passed" for i in images))
        run = by_id(runtime.get("bridges", []), key)
        run_ok = runtime_ok and bool(run) and bool(run.get("walks")) and bool(run.get("parapets"))
        compact = next((r for r in compact_records if r.get("uuid") == key), {})
        ref = compact.get("rmmo_ref", {})
        formal_asset_ok = formal_ok and same_sha(ref.get("sha256"), native.get("sha256"))
        textures = {}
        for material in row.get("materials", []):
            for binding in material.get("texture_bindings", {}).values():
                info = audit.get("textures", {}).get(binding.get("path"), {})
                textures[info.get("sha256", binding.get("path", "unknown"))] = info
        meshes = {m.get("geometry_identity", str(i)): m for i, m in enumerate(row.get("mesh_buffers", []))}
        costs = {k: row.get(k) for k in ("expanded_render_triangles", "expanded_collision_triangles", "render_surface_instances")}
        costs.update(unique_mesh_buffers=len(meshes),
                     unique_geometry_cpu_channel_bytes=sum(m.get("cpu_channel_bytes", 0) for m in meshes.values()),
                     unique_lod_index_bytes=sum(m.get("lod_index_bytes", 0) for m in meshes.values()),
                     textures=list(textures.values()),
                     texture_totals={field: sum(t.get(field, 0) for t in textures.values()) for field in
                                     ("bytes", "decoded_bytes", "same_format_with_mips_bytes", "rgba8_or_native_mips_conservative_bytes")},
                     lod_buffers=[{"index": m.get("index"), "levels": m.get("lods_per_surface", [])} for m in meshes.values()],
                     note="Texture costs are unique within this bridge, shared across bridges. Surface instances are not draw calls; mip budgets are not measured VRAM/RSS. LODs are alternatives, not simultaneous render triangles.")
        stages = {
            "resource_cpu": stage(cpu_ok, "Current native resource SHA/expected SHA and complete CPU audit required.", audit_current and bool(issues)),
            "lod_necessity": stage(lod_ok, "Explicit necessity decision and rationale tied to this payload required."),
            "resource": stage(cpu_ok and lod_ok, "CPU evidence plus reviewed LOD necessity."),
            "visual": stage(visual_ok, "Explicit per-bridge near/mid/far/detail approval; image presence alone never passes.", acceptance_bound and accepted.get("passed") is False),
            "pipeline": stage(build_ok and cpu_ok, "Completed native authoring/save/reopen plus current frozen resource audit required."),
            "runtime": stage(run_ok, "Candidate gameplay completion, bridge walks and parapet probes required."),
            "formal_integration": stage(formal_asset_ok and visual_ok and run_ok and build_ok, "Verified atomic publication/reopen and identical per-bridge native resource; candidate runtime evidence is not a separate formal gameplay run."),
        }
        reports.append({"schema_version": 1, "id": key, "stages": stages,
                        "overall": "passed" if all(s["status"] == "passed" for s in stages.values()) else "failed" if any(s["status"] == "failed" for s in stages.values()) else "pending",
                        "candidate": candidate, "formal": formal, "evidence_files": provenance,
                        "identity": {"source_module_glb": row.get("source_module_glb", {}), "frozen_payload": frozen,
                                     "native_resource": native, "actual_native_resource": actual_resource,
                                     "formal_native_reference": ref},
                        "costs": costs, "lod_assessment": lod, "images": images,
                        "unreviewed_capture_inventory": [i for i in build.get("images", []) if key in Path(i.get("path", "")).stem],
                        "runtime_evidence": run, "audit_errors": issues, "head_support": row.get("head_support", []),
                        "editable_semantics": row.get("editable_semantics", {}), "bindings": row.get("bindings", []),
                        "static_object_exemptions": {"wind_and_animation": "not applicable: static stone bridge"},
                        "batching_shared_scene": build.get("ground_batching", {}),
                        "scope_note": "Report aggregation only; does not perform visual inspection, rerun gameplay, approve publication or change maps."})
    return reports


def markdown(report):
    lines = [f"# {report['id']} 模型验收", "", f"结论：{report['overall']}", ""]
    for name, result in report["stages"].items():
        lines.append(f"- {name}: **{result['status']}** — {result['reason']}")
    ident = report["identity"]
    lines += ["", "实际资源：", "", f"- frozen payload SHA: `{ident['frozen_payload'].get('sha256', '待验')}`",
              f"- native rmres SHA: `{ident['actual_native_resource'].get('sha256', '待验')}`",
              f"- native 文件: {ident['actual_native_resource'].get('path', '待验')}",
              "", f"资源：渲染三角形 {report['costs']['expanded_render_triangles']}；碰撞三角形 {report['costs']['expanded_collision_triangles']}；LOD 决策 {report['lod_assessment'] or '待验'}。",
              "", "截图证据（存在不代表通过）：", ""]
    for evidence in report["images"]:
        lines.append(f"- {evidence['view']}: {evidence['stage']['status']} — {evidence['actual_file']['path'] or '待提供'}")
    lines += ["", "纹理及缓冲成本详见同名 JSON；保守显存预算不作为实际 RSS/VRAM。正式接入与候选运行验证分别记录。", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--dry-run", action="store_true", help="Read evidence and print statuses, without writing reports")
    args = parser.parse_args()
    reports = aggregate(args.out)
    index = {"schema_version": 1, "bridges": [{"id": r["id"], "overall": r["overall"], "stages": r["stages"]} for r in reports]}
    if not args.dry_run:
        dest = args.out / "model_reviews"
        dest.mkdir(parents=True, exist_ok=True)
        for r in reports:
            (dest / (r["id"] + ".json")).write_text(json.dumps(r, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            (dest / (r["id"] + ".md")).write_text(markdown(r), encoding="utf-8")
        (dest / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(index, ensure_ascii=False))


if __name__ == "__main__":
    main()
