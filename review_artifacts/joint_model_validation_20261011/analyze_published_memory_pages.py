"""Read completed published-map pair; do not sample processes or hash assets."""
from datetime import datetime, timezone
import json
from pathlib import Path

from analyze_results import hardware_span, read_json

HERE = Path(__file__).resolve().parent
ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = HERE / "published_memory_pages_analysis.json"


def cache_scope(d):
    p = d["map_profile"]
    events = d["monitor"]["trace"]["events"]
    return {**{k: d.get(k) for k in ("map", "map_sha", "cache_path", "cache_scope", "cache_candidate", "cache_existed", "reset_derived_cache", "reset_cache_scope", "native_entry_prefetch")},
            **{k: p.get(k) for k in ("terrain_context_cache_hit", "reference_index_hit", "reference_index_rebuilt_before_models")},
            "trace_spans_ms": {label: sum(e["end_us"]-e["start_us"] for e in events if e["label"] == label)/1000
                               for label in ("game.mesh_cache_wait", "game.cooked_restore")}}


def physics_results(p):
    def phase(x):
        return {k: x[k] for k in ("ok", "camera_fractions", "character_collided")}
    return {"baseline": phase(p["baseline"]), "candidate_count": p["candidate_count"],
            "candidates": [{"uuid": x["uuid"], **{k: phase(x[k]) for k in ("before", "without", "after")}}
                           for x in p["candidates"]], "restoration": p["restoration"]}


runs = []
for variant in ("off", "on"):
    name = f"published_memory_{variant}_probe"
    d = read_json(ROOT / (name + ".json"))
    h = read_json(ROOT / (name + ".hardware.json"))
    p = read_json(ROOT / (name + ".memory-pages.json"))
    m = d["memory_pages"]
    assert p["ok"] and p["complete"] and not p["errors"] and not p["unknown_or_noncommitted_pages"]
    assert d["failures"] == 0 and all(d["physics_probe"]["restoration"].values())
    origin = h["samples"][0]
    samples = [{**s, "aligned_epoch_s": origin["epoch_s"]+s["monotonic_s"]-origin["monotonic_s"]} for s in h["samples"]]
    def nearest(epoch):
        s = min(samples, key=lambda x: abs(x["aligned_epoch_s"]-epoch))
        return {"offset_ms": (s["aligned_epoch_s"]-epoch)*1000,
                "rss_bytes": s["rss_bytes"], "private_bytes": s["private_bytes"]}
    end = d["entry_end_epoch_s"]
    monitor_end = d["monitor"]["start_epoch_s"]+d["monitor"]["span_ms"]/1000
    logs = (ROOT / (name + ".log")).read_text(encoding="utf-8", errors="replace").splitlines()
    runs.append({"variant": variant, "report": str(ROOT / (name+".json")),
                 "hardware_report": str(ROOT / (name+".hardware.json")), "page_report": str(ROOT / (name+".memory-pages.json")),
                 "sharing_enabled": d["model_texture_sharing"], "collision_geometry": d["collision_geometry"],
                 "background_record_progress": {k: d.get(k) for k in ("resident_record_count", "remaining_deferred")},
                 "failures": d["failures"], "cache": cache_scope(d), "entry_ms": d["entry_ms"],
                 "entry_hardware": hardware_span(h, d["entry_epoch_s"], end),
                 "aligned_points": {"entry_end": nearest(end), "entry_plus_5s": nearest(end+5), "monitor_end": nearest(monitor_end)},
                 "playable_frames_ms": d["monitor"]["phase_frame_percentiles_ms"]["playable_background"],
                 "physics": physics_results(d["physics_probe"]),
                 "texture_observation": d["model_texture_observation"],
                 "probe_engine": {k: v for k, v in m.items() if k not in ("probe", "process_output")},
                 "page_observation": {k: p[k] for k in ("ok", "complete", "elapsed_ms", "enumerated_pages", "classified_pages", "enumerated_resident_bytes",
                                                        "error_count", "unknown_or_noncommitted_pages", "memory_before", "memory_after", "memory_delta",
                                                        "by_region_type", "by_ws_shared_flag", "by_ws_share_count", "region_shared_cross", "top_allocations",
                                                        "enumerated_minus_rss_before_bytes", "enumerated_minus_rss_after_bytes")},
                 "avatar_hidden_after_measurement": d["screenshot_avatar_hidden"],
                 "warnings": [line for line in logs if "WARNING:" in line]})

off, on = runs
assert off["cache"]["map"] == on["cache"]["map"] and off["cache"]["map_sha"] == on["cache"]["map_sha"]
assert off["physics"] == on["physics"]


def diff(a, b):
    return {"off": a, "on": b, "on_minus_off": b-a, "on_minus_off_MiB": (b-a)/1048576}


comparison = {
    "entry_ms": {"off": off["entry_ms"], "on": on["entry_ms"], "on_minus_off": on["entry_ms"]-off["entry_ms"]},
    "entry_sampled_peaks": {k: diff(off["entry_hardware"][k], on["entry_hardware"][k]) for k in ("rss_peak_bytes", "private_peak_bytes")},
    "aligned_points": {label: {k: diff(off["aligned_points"][label][k], on["aligned_points"][label][k]) for k in ("rss_bytes", "private_bytes")}
                       for label in off["aligned_points"]},
    "late_process": {k: diff(off["page_observation"]["memory_before"][k], on["page_observation"]["memory_before"][k])
                     for k in ("WorkingSetSize", "PrivateUsage")},
    "resident_by_region_type": {k: diff(off["page_observation"]["by_region_type"][k]["bytes"], on["page_observation"]["by_region_type"][k]["bytes"])
                                for k in ("MEM_PRIVATE", "MEM_MAPPED", "MEM_IMAGE")},
    "late_engine": {k: diff(off["probe_engine"][k], on["probe_engine"][k])
                    for k in ("static_memory_before", "renderer_texture_bytes_before", "renderer_buffer_bytes_before")},
    "texture_counts": {k: {"off": off["texture_observation"][k], "on": on["texture_observation"][k]}
                       for k in ("texture_objects", "stamped_pixel_keys", "duplicate_stamped_objects", "pixel_keys_with_multiple_objects", "live_pool_keys")},
    "physics_results_and_restoration_exactly_equal": off["physics"] == on["physics"]}

old = []
for suffix in ("off_a1", "on_b1", "on_b2", "off_a2"):
    name = "game_sharing_"+suffix+"_v2"
    old.append({"report": str(ROOT/(name+".json")), **cache_scope(read_json(ROOT/(name+".json")))})
assert all(not x["reset_derived_cache"] and x["cache_candidate"] and x["cache_existed"] and x["trace_spans_ms"]["game.cooked_restore"] > 0 for x in old+[r["cache"] for r in runs])

report = {
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "scope": "Single OFF/ON pair on the same published map, rebuilt native generation and warm selected cooked/index caches; root ran engines. This script only reads existing small reports. ON uses the enabled default; OFF explicitly overrides it.",
    "runs": runs, "comparison": comparison, "historical_cache_scope": old,
    "cache_parity": "Both old sharing-v2 ABBA and this pair have reset_derived_cache=false, selected_reference_closure, existing candidate cache, game.cooked_restore, terrain-context and reference-index hits. reset_cache_scope describes what a requested reset would affect, not an executed reset. Old versus new map/source/native-generation/cache-path differs, so failure to reproduce the old RSS increase is not a causal proof of a fix. Within this pair the paths and source SHA match.",
    "findings": [
        "Final renderer-accounted textures decrease by452,574,720B (431.609MiB); the same60 pixel keys have24 duplicate stamped objects removed,127 total reachable texture objects become103. This is process-global renderer accounting at the test end, not measured entry VRAM or a per-model GPU-residency census.",
        "Post-measurement working set increases only6,434,816B (6.137MiB), while private commit decreases263,622,656B (251.410MiB). The resident-page delta is MEM_PRIVATE+6,438,912B, MEM_MAPPED-8192B, MEM_IMAGE unchanged. No additional256MiB region appears in the recorded large resident allocations, but only regions containing sampled resident pages are listed.",
        "Entry sampled RSS peak is34MiB lower and private peak253.8MiB lower. Nearest entry/monitor-end samples likewise do not show the old stable+256MiB working-set increase: monitor-end RSS is about7.8MiB higher, private commit about250MiB lower. Boundary sample offsets are preserved; endpoint maxima are not exact instantaneous peaks.",
        "Both Windows probes classify every enumerated resident page with zero unknown/errors; target working set, private commit, page-fault count and peak working set remain unchanged across each probe. Enumeration is49,152B below ProcessMemoryInfo RSS in each arm. This small equal discrepancy is retained, not silently forced to reconcile.",
        "Game functional failures are zero and all six candidate before/without/after character collision and camera-fraction arrays plus restoration match exactly. Playable p95/p99/max frames do not worsen in this pair. Entry is348.904ms slower with sharing; one pair is insufficient to infer a reliable time effect.",
        "Static ownership review still finds only bounded weak global texture references and local temporary keepalive through the required synchronization. It supplies no proof that the old RSS increase was a driver cache, harmless paging or a memory leak. Current process/static/renderer/page evidence finds no sustained large extra live allocation on the rebuilt generation; the historical anomaly remains unassigned."
    ],
    "recommendation": {"retain_default_model_texture_sharing": True,
                       "reason": "User authorized enabling significant benefits without established adverse impact. The rebuilt published generation retains ~432MiB renderer savings, reduces private commit ~251MiB, passes real functional checks and does not reproduce the previous sustained RSS increase. Keep the default enabled while retaining memory monitoring; this is a bounded single-pair acceptance, not proof of zero risk on all maps or a diagnosis/fix of the older generation.",
                       "picking_lod": False, "collision_geometry": False,
                       "historical_rss_investigation": str(HERE/"game_sharing_rss_analysis.json"),
                       "supersedes": "The historical report's pending-release recommendation is superseded for this tested rebuilt generation only; its observations and unanswered causal question remain valid."},
    "limits": ["Probe executes after entry, ten-second monitor, physics and author assertions, before avatar hiding/screenshot. Late process memory includes those probes' additional allocations; it must not be called entry RSS/VRAM.",
               "QueryWorkingSet excludes AWE/large pages outside ordinary working sets. VirtualQueryEx categorizes virtual region type, not allocation creator, engine ownership or GPU residency. Shared-bit means shareable; share count is capped at7.",
               "Top allocation extents cover queried regions with resident pages, not complete nonresident commitment. ASLR addresses cannot identify the same allocation across processes.",
               "OFF then ON is one pair, not randomized repeated ABBA. No reliable load-time speedup or universal memory bound is established. Continue investigating G1/G2 rather than enabling them.",
               "The tested point has133 character and133 camera queries per arm, including six temporary layer exclusions and restoration. These match exactly; this is not all-map physical equivalence. Background progress differs by four resident ordinary objects (628 versus632), so late process composition is not perfectly identical despite matching input/gates.",
               "One existing ObjectDB exit warning in each run remains; functional and budget acceptance are not leak-free-exit proof."],
    "primary_sources": ["https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-queryworkingset",
                        "https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-psapi_working_set_block",
                        "https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualqueryex",
                        "https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex"]}
OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output": str(OUT), "comparison": comparison, "recommendation": report["recommendation"]}, ensure_ascii=False, indent=2))
