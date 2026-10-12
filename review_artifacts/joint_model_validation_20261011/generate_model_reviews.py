"""Assemble eleven SHA-bound model reviews from existing JSON evidence only.

No engine, model/image reads, hashes, imports, cache writes or visual inference.
Missing final evidence remains pending. Re-run into a new output directory after
the final smoke/verification; older review snapshots are never overwritten.
"""
import argparse
import json
import os
import re
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

REPO = Path("D:/code/rmmo")
RUNTIME = Path("D:/code/rmmo_runtime")
HERE = REPO / "review_artifacts/joint_model_validation_20261011"
EVIDENCE = RUNTIME / "review_artifacts/joint_model_validation_20261011"
HANDOFF = REPO / "review_artifacts/town_asset_size_audit_20261011/candidate_handoff.json"
VISUAL = REPO / "review_artifacts/town_asset_size_audit_20261011/selected_visual_review.json"
PASS, FAIL, PENDING = "通过", "不通过", "待验"
SHA = re.compile(r"[0-9a-f]{64}\Z")


def canonical(value):
    return Path(os.path.abspath(value)).as_posix()


def same_path(left, right):
    return bool(left and right) and canonical(left).casefold() == canonical(right).casefold()


def read(path):
    if not path:
        return {}
    p = Path(path)
    if not p.is_absolute() or not any(p.is_relative_to(root) for root in (REPO, RUNTIME)):
        raise ValueError("Evidence must be an absolute project/runtime path: " + str(path))
    try:
        if p.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("Evidence JSON too large: " + str(p))
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        # Running harnesses can be between writes; never promote partial data.
        return {"incomplete_json": True}


def succeeded(data):
    return bool(data) and not data.get("timeout") and not data.get("incomplete_json") and data.get("failures", []) in (0, []) \
        and all(item.get("ok") is True for item in data.get("checks", []))


def state(ok, available, reason, **detail):
    return {"status": PASS if ok else FAIL if available else PENDING, "reason": reason, **detail}


def native_sha(case):
    return case.get("native", {}).get("footprint_candidate", {}).get("source_sha")


def compact_cost(value):
    stats = value.get("native_stats", {})
    return {"source_bytes": value.get("source_bytes"), "native_bytes_at_art_review": value.get("native_bytes"),
        "cpu_image_mip_bytes_estimate": stats.get("image_mip_bytes"),
        "gpu_rgba_mip_bytes_estimate": stats.get("gpu_rgba_bytes"),
        "full_peak_admission_bytes_estimate": value.get("full_peak_conservative_admission_bytes"),
        "meshes": stats.get("meshes"), "materials": stats.get("materials"), "textures": stats.get("textures")}


def art_checks(row, visual):
    compare_path = Path(row["review"])
    comparison = read(compare_path)
    baseline_path, candidate_path = compare_path.parent / "baseline.json", compare_path.parent / "candidate.json"
    baseline, candidate = read(baseline_path), read(candidate_path)
    identity = baseline.get("original_sha") == row["original_sha256"] and candidate.get("original_sha") == row["candidate_sha256"] \
        and native_sha(candidate) == row["candidate_sha256"] \
        and comparison.get("candidate_native", {}).get("footprint_candidate", {}).get("source_sha") == row["candidate_sha256"]
    paired = identity and all(succeeded(case) and case.get("passed") is True for case in (baseline, candidate, comparison))
    images = comparison.get("images", [])
    names = [image.get("name") for image in images]
    covered = len(names) == 12 and all(any(name.startswith(view + "_") for name in names) for view in ("near", "medium", "far")) \
        and all(any(name.endswith(suffix) for name in names) for suffix in ("still.png", "wind_t1.png", "wind_t4.png"))
    semantics = row.get("nontexture_semantics_exact") is True and comparison.get("nontexture_semantic_exact") is True
    artistic = row.get("art_status") == "isolated_review_passed"
    manual, manual_note = [], "同 SHA 美术交接记录；本生成器没有重新看图。"
    if row["label"] == "pennant_quality":
        manual = visual.get("pennant_quality", {}).get("manually_inspected_pairs", [])
        manual_note = visual.get("pennant_quality", {}).get("observation", manual_note)
    elif row["kind"] != "lossless":
        family = row["label"].removesuffix("_pbr2k_albedo4k")
        foliage = visual.get("foliage_pbr2k_albedo4k", {})
        manual = foliage.get("manually_inspected_pairs", {}).get(family, [])
        manual_note = foliage.get("observation", manual_note)
    if row["kind"] == "lossless":
        visual_ok = paired and covered and artistic and semantics and row.get("pixel_exact") is True \
            and comparison.get("semantic_exact") is True and all(image.get("exact") is True for image in images)
    else:
        visual_ok = paired and covered and artistic and semantics and visual.get("passed") is True \
            and row["label"] in visual.get("approved_labels", []) and bool(manual)
    shadow_path = row.get("shadows")
    shadow = read(shadow_path)
    shadow_identity = False
    if shadow_path:
        shadow_case = read(Path(shadow_path).parent / "candidate.json")
        # Shadow harness calls its immutable identity source_sha; older files
        # may use original_sha. Do not inherit a different asset's images.
        shadow_identity = row["candidate_sha256"] in (shadow_case.get("source_sha"), shadow_case.get("original_sha"))
        visual_ok = visual_ok and succeeded(shadow) and shadow.get("passed") is True and shadow_identity
    art_generator = candidate.get("native", {}).get("footprint_candidate", {}).get("generator")
    return {
        "resource_audit": state(paired and semantics, identity and bool(comparison),
            "继承同源/候选 SHA 的静态语义、真实导入、native 保存重开及成本审计；未重新读取模型字节。",
            evidence=[str(compare_path), str(candidate_path)], baseline=compact_cost(row["baseline"]),
            candidate=compact_cost(row["optimized"]), kind=row["kind"], nontexture_semantics_exact=semantics),
        "visual_quality": state(visual_ok, identity and bool(comparison),
            "同 SHA 美术证据的固定条件近/中/远/细节及匹配风时刻结果；不是本轮逐图重新人工检查。",
            evidence=[str(compare_path), str(VISUAL)], paired_image_names=names, paired_capture_count=len(names),
            inherited_manual_pairs=manual, inherited_manual_observation=manual_note,
            supplementary_shadows={"evidence": shadow_path, "passed": bool(shadow_path and shadow_identity and succeeded(shadow) and shadow.get("passed") is True),
                "note": "仅继承该 SHA 的专门接收阴影记录。" if shadow_path else "此无损候选无独立补充阴影报告；不冒称另拍阴影图。"},
            art_pipeline_generator=art_generator, scope="历史美术管线结果；最终共享开关由联合运行测试覆盖，未重新拍摄全部单模型视角。"),
        "isolated_pipeline": {"passed": paired, "generator": art_generator, "source_sha256": row["candidate_sha256"],
            "evidence": str(candidate_path), "scope": "历史版本真实导入、native保存重开；不能当作最终generator缓存命中证明。"}}


def publication_for(row, receipt):
    matches = [item for item in receipt.get("imports", []) if item.get("label") == row["label"]]
    plans = [item for item in receipt.get("model_plan", []) if item.get("label") == row["label"]]
    item, plan = (matches[0] if len(matches) == 1 else {}), (plans[0] if len(plans) == 1 else {})
    identity = plan.get("candidate_sha256") == row["candidate_sha256"] and plan.get("original_sha256") == row["original_sha256"] \
        and item.get("expected_source_sha256") == row["candidate_sha256"] and same_path(item.get("target"), plan.get("target"))
    ok = succeeded(receipt) and receipt.get("ok") is True and receipt.get("map_published") is True \
        and receipt.get("choice") == "preferred" and identity and item.get("import_ok") is True \
        and item.get("exact_source_copy") is True and item.get("closed_source", {}).get("ok") is True \
        and item.get("native", {}).get("ok") is True and item.get("footprint", {}).get("ok") is True
    return ok, item, plan


def smoke_for(row, plan, receipt, smoke):
    binding = smoke.get("publication_receipt", {})
    overall = succeeded(smoke) and smoke.get("stage") == "finished" \
        and binding.get("published_sha256") == receipt.get("published_sha256") \
        and binding.get("catalog_sha_after") == receipt.get("catalog_sha_after") \
        and smoke.get("expected_sha256") == receipt.get("published_sha256") \
        and smoke.get("formal_sha256") == receipt.get("published_sha256") and smoke.get("model_texture_sharing") is True
    matches = [item for item in smoke.get("catalog_audit", []) if item.get("label") == row["label"]]
    matched = len(matches) == 1 and matches[0].get("source_sha256") == row["candidate_sha256"] \
        and same_path(matches[0].get("target"), plan.get("target"))
    return overall and matched


def compiled_for(plan, receipt, compiled):
    matches = [item for item in compiled.get("models", []) if same_path(item.get("path"), plan.get("target"))]
    return succeeded(compiled) and compiled.get("source_sha") == receipt.get("published_sha256") \
        and same_path(compiled.get("map"), receipt.get("source")) and compiled.get("source_unchanged") is True \
        and compiled.get("footprints_failed") == 0 and compiled.get("skipped") == 0 and len(compiled.get("models", [])) == 32 \
        and len(matches) == 1 and matches[0].get("ok") is True and matches[0].get("footprint", {}).get("ok") is True


def postverify_ok(data, receipt, receipt_path):
    if not succeeded(data) or data.get("passed") is not True or data.get("mode") != "verify" \
            or not same_path(data.get("receipt"), receipt_path):
        return False
    return any(same_path(item.get("path"), receipt.get("source")) and item.get("sha256") == receipt.get("published_sha256")
               for item in data.get("allowed_changes", []))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", default=str(EVIDENCE / "publish_preferred_v2_receipt.json"))
    parser.add_argument("--catalog-smoke", default=str(EVIDENCE / "joint_published_catalog.json"))
    parser.add_argument("--compiled-report", default=str(EVIDENCE / "compile_published_shared.json"))
    parser.add_argument("--game-smoke", default=str(EVIDENCE / "published_game_default.json"), help="Completed profile_game_entry JSON for the published-SHA checkpoint")
    parser.add_argument("--transfer-smoke", default=str(EVIDENCE / "published_transfer_default.json"))
    parser.add_argument("--postverify", help="Successful postpublish_validation.py verify JSON")
    parser.add_argument("--output-dir", default=str(HERE / ("model_reviews_" + str(time.time_ns()))))
    args = parser.parse_args()
    handoff, visual = read(HANDOFF), read(VISUAL)
    rows = handoff.get("preferred", [])
    if len(rows) != 11 or len({row["label"] for row in rows}) != 11 or any(not SHA.fullmatch(row["candidate_sha256"]) for row in rows):
        raise ValueError("Expected eleven distinct preferred model SHA identities")
    if handoff.get("preferred_source_saved_bytes") != 1497622136:
        raise ValueError("Preferred source-size handoff changed; inspect rather than reuse prior total")
    receipt, smoke, game, verification = read(args.receipt), read(args.catalog_smoke), read(args.game_smoke), read(args.postverify)
    compiled, transfer = read(args.compiled_report), read(args.transfer_smoke)
    output = Path(args.output_dir)
    if not output.is_absolute() or not output.is_relative_to(HERE) or output == HERE or output.exists():
        raise ValueError("Output must be a new child directory of the joint review directory")
    output.mkdir(parents=True)
    game_ok = succeeded(game) and game.get("entry_ms", 0) > 0 and game.get("map_sha") == receipt.get("published_sha256") \
        and game.get("formal_sha") == receipt.get("published_sha256") and bool(game.get("screenshot")) \
        and bool(game.get("model_texture_observation")) and not game.get("failure_epoch_s") and game.get("model_texture_sharing") is True
    transfer_ok = succeeded(transfer) and transfer.get("map_sha") == receipt.get("published_sha256") \
        and transfer.get("formal_sha") == receipt.get("published_sha256") and transfer.get("transfer_ok") is True \
        and transfer.get("transfer_end_epoch_s", 0) > 0 and bool(transfer.get("final_image")) and transfer.get("model_texture_sharing") is True
    verification_ok = postverify_ok(verification, receipt, args.receipt)
    index = []
    root_spot_checks = {"pennant_quality": "彩旗 quality 的旗帜细节", "shrub_spreading_pbr2k_albedo4k": "铺展灌木的叶片特写"}
    for row in rows:
        art = art_checks(row, visual)
        published, imported, plan = publication_for(row, receipt)
        catalog_ok = smoke_for(row, plan, receipt, smoke)
        compiled_ok = compiled_for(plan, receipt, compiled)
        final_pipeline = published and catalog_ok and compiled_ok
        integrated = final_pipeline and game_ok and transfer_ok and verification_ok
        item = {"version": 1, "label": row["label"], "display_name": plan.get("published_catalog_label", row["label"]),
            "identity": {key: row[key] for key in ("original", "original_sha256", "candidate", "candidate_sha256")},
            "published_identity": {"target": plan.get("target"), "source_sha256": plan.get("candidate_sha256"),
                "map_sha256": receipt.get("published_sha256"), "compiled_generator": receipt.get("compiled_generator"),
                "footprint_generator": receipt.get("footprint_generator"), "publication_passed": published},
            "resource_audit": art["resource_audit"], "visual_quality": art["visual_quality"],
            "runtime_pipeline": state(final_pipeline, bool(smoke.get("stage") == "finished") and published,
                "当前版本原字节导入、native/footprint构建和发布后真实编辑器/缩略图读取；历史管线结果单独列出。",
                receipt=args.receipt, final_catalog_smoke=args.catalog_smoke,
                final_compile_report=args.compiled_report, compiled_batch_and_target_passed=compiled_ok,
                generator_binding="generator引用发布回执；最终32模型重建报告绑定同一地图SHA，代码守恒由postverify独立验证。",
                isolated_history=art["isolated_pipeline"], exact_source_copy=imported.get("exact_source_copy"),
                import_preparation=imported.get("import_preparation"),
                current_native_bytes=imported.get("native", {}).get("bytes"),
                current_full_peak_admission_bytes_estimate=imported.get("footprint", {}).get("estimated_bytes")),
            "game_editor_integration": state(integrated,
                published and bool(smoke.get("stage") == "finished") and bool(game.get("screenshot")) and bool(transfer.get("final_image")) and bool(verification),
                "按发布 SHA 的临时地图验证游戏进入、编辑器 HTTP、素材目录、源守恒；未完成的正式后验收保持待验。",
                publication=published, catalog_editor_smoke=catalog_ok, game_smoke=game_ok, transfer_smoke=transfer_ok, postpublication_conservation=verification_ok,
                evidence=[args.receipt, args.catalog_smoke, args.game_smoke, args.transfer_smoke, args.postverify],
                editor_scope="11件逐一完整SHA、目录/HTTP发现、真实缩略图与全城加载；新增/删除/撤销/保存重开使用彩旗代表样本，不声称逐件重复同类交互。"),
            "root_additional_visual_inspection": {"inspected": row["label"] in root_spot_checks,
                "scope": root_spot_checks.get(row["label"], "没有记录根代理对本件额外逐图复看"),
                "provenance": "根代理本轮明确陈述的抽查范围；生成器不看图，不扩大检查覆盖。"},
            "limitations": ["各资源原版、母版与回退版保留。", "磁盘源压缩不等于解码/显存压缩；预算不等于实际RSS/VRAM。",
                "不将共享纹理预算乘实例数，也不在启用共享后把单件预算相加当显存实测。",
                "固定风时刻不证明连续运动无闪烁；并非所有视角、光照和曝光均已验收。",
                "本工具仅整理已有报告，未重新hash或加载任何模型、图片或派生缓存。"]}
        target = output / (row["label"] + ".json")
        target.write_text(json.dumps(item, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        index.append({"label": row["label"], "source_sha256": row["candidate_sha256"], "report": target.as_posix(),
                      "statuses": {category: item[category]["status"] for category in
                                   ("resource_audit", "visual_quality", "runtime_pipeline", "game_editor_integration")}})
    summary = {"version": 1, "created_utc": datetime.now(timezone.utc).isoformat(), "scope": "11 preferred assets; metadata-only alternatives are not published by this review",
        "evidence": {"handoff": str(HANDOFF), "visual_review": str(VISUAL), "receipt": args.receipt,
                     "catalog_smoke": args.catalog_smoke, "compiled_report": args.compiled_report, "game_smoke": args.game_smoke,
                     "transfer_smoke": args.transfer_smoke, "postverify": args.postverify},
        "models": index, "status_counts": {category: dict(Counter(model["statuses"][category] for model in index)) for category in index[0]["statuses"]},
        "preferred_source_saved_bytes": 1497622136,
        "source_size_scope": "11件被引用的新版本比原版本合计少1,497,622,136字节；原版保留，不是磁盘已释放，更不是VRAM节省。",
        "root_extra_visual_scope": "额外看了彩旗 quality 旗帜细节、铺展灌木叶片特写及整城固定视角；未声明根代理看遍所有单模型图。",
        "current_pipeline_generator": receipt.get("compiled_generator"), "no_engine_image_model_reads_or_hashes": True}
    (output / "index.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"index": str(output / "index.json"), "status_counts": summary["status_counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
