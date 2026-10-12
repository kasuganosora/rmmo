"""Offline analysis of existing reports only; never invokes Godot or opens assets."""
import json
import math
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPORTS = Path("D:/code/rmmo_runtime/review_artifacts/deferred_final_20261010")
NAMES = [f"{state}_{variant}" for state in ("warm", "rebuild")
         for variant in ("old_a", "new_a", "new_b", "old_b")] + ["final_default"]
PRIMARY = {"warm_new_a", "warm_new_b", "final_default"}


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def union_us(intervals):
    intervals = sorted((a, b) for a, b in intervals if b > a)
    end = -math.inf
    result = 0
    for a, b in intervals:
        result += max(0, b - max(a, end))
        end = max(end, b)
    return result


def occupancy(intervals, a, b):
    changes = defaultdict(int)
    changes[a] = 0
    changes[b] = 0
    for x, y in intervals:
        x, y = max(a, x), min(b, y)
        if y > x:
            changes[x] += 1
            changes[y] -= 1
    histogram = defaultdict(float)
    previous = a
    active = 0
    timeline = []
    for t, delta in sorted(changes.items()):
        if t > previous:
            histogram[active] += (t - previous) / 1000
            timeline.append({"start_us": previous, "end_us": t, "active": active})
        active += delta
        previous = t
    wall_ms = (b-a)/1000
    return {"wall_ms": wall_ms, "active_task_ms": sum(k*v for k, v in histogram.items()),
            "mean_active_tasks": sum(k*v for k, v in histogram.items()) / wall_ms if wall_ms else 0,
            "peak_active_tasks": max(histogram, default=0),
            "wall_ms_by_active_tasks": dict(sorted(histogram.items())),
            "intervals": timeline}


def interpolate(samples, t, field):
    for left, right in zip(samples, samples[1:]):
        if left["epoch_s"] <= t <= right["epoch_s"]:
            if field not in left or field not in right:
                return None
            fraction = (t-left["epoch_s"])/(right["epoch_s"]-left["epoch_s"])
            return left[field] + fraction*(right[field]-left[field])
    return None


def hardware_window(hardware, epoch, origin, a, b):
    start = epoch+(a-origin)/1e6
    end = epoch+(b-origin)/1e6
    samples = hardware["samples"]
    inside = [s for s in samples if start <= s["epoch_s"] <= end]
    ca, cb = interpolate(samples, start, "cpu_s"), interpolate(samples, end, "cpu_s")
    main_samples = []
    for s in samples:
        t = next((v for v in s.get("threads", []) if v["id"] == hardware["main_thread_id"]), None)
        if t:
            main_samples.append({"epoch_s": s["epoch_s"], "cpu_s": t["cpu_s"]})
    ma, mb = interpolate(main_samples, start, "cpu_s"), interpolate(main_samples, end, "cpu_s")
    gaps = [r["epoch_s"]-l["epoch_s"] for l, r in zip(samples, samples[1:])
            if l["epoch_s"] <= end and r["epoch_s"] >= start]
    wall = (b-a)/1e6
    return {"wall_ms": wall*1000, "cpu_seconds": None if ca is None or cb is None else cb-ca,
            "process_cpu_core_equivalents": None if ca is None or cb is None or not wall else (cb-ca)/wall,
            "main_thread_cpu_seconds_estimate": None if ma is None or mb is None else mb-ma,
            "main_thread_cpu_core_equivalents_estimate": None if ma is None or mb is None or not wall else (mb-ma)/wall,
            "inside_sample_count": len(inside), "max_overlapping_sample_gap_ms": max(gaps, default=0)*1000,
            "coarse_short_window": wall < 1 or len(inside) < 2,
            "sampled_peak_rss_bytes": max((x["rss_bytes"] for x in inside), default=None),
            "sampled_peak_private_bytes": max((x["private_bytes"] for x in inside), default=None)}


def analyze(name):
    report = read(REPORTS/f"{name}.json")
    hardware = read(REPORTS/f"{name}.hardware.json")
    world = report["world_profile"]
    mp = report["map_profile"]
    session = report["session_profile"]
    trace = report["monitor"]["trace"]
    origin = int(round(world["entry_core_resources_ready_us"]-report["entry_core_ready_ms"]*1000))
    end = origin+report["entry_ms"]*1000
    core = world["entry_core_resources_ready_us"]
    safety = world["entry_safety_ready_us"]
    playable = world["entry_playable_ready_us"]
    events = [e for e in trace["events"] if e["start_us"] <= end and e["end_us"] >= origin]

    def first(label):
        return next(e for e in events if e["label"] == label)

    def stage(label, start, finish):
        return {"name": label, "start_ms": (start-origin)/1000, "end_ms": (finish-origin)/1000,
                **hardware_window(hardware, report["entry_epoch_s"], origin, start, finish)}

    admission = mp["asset_admission_details"]
    parse = first("game.parse")
    build = first("game.build")
    initial_intervals = [(s["worker_started_us"], s["worker_finished_us"])
                         for t in admission["tasks"].values() for s in t["stages"]]
    initial_start = min(a for a, b in initial_intervals)
    initial_finish = max(b for a, b in initial_intervals)
    phases = [stage("entry_to_parser_start", origin, parse["start_us"]),
              stage("parser_before_first_initial_model", parse["start_us"], initial_start),
              stage("initial_model_workers_envelope", initial_start, initial_finish),
              stage("after_initial_workers_to_build", initial_finish, build["start_us"]),
              stage("main_build_to_core_ready", build["start_us"], core),
              stage("core_to_safety", core, safety),
              stage("safety_to_playable_ready", safety, playable),
              stage("playable_to_entry_finished", playable, end)]
    if any(x["wall_ms"] < 0 for x in phases):
        raise ValueError(f"{name}: major stage overlap needs distinct accounting")
    post_markers = [("safety_ready", safety), ("player_created", world["player"]*1000),
                    ("environment_complete", world["environment"]*1000),
                    ("navigation_complete", world["navigation"]*1000),
                    ("events_complete", world["events"]*1000), ("hud_complete", world["hud"]*1000),
                    ("batches_gate_complete", world["batches"]*1000),
                    ("radar_and_materials_complete", world["radar"]*1000),
                    ("playable_ready", playable), ("first_frame_drawn", session["first_frame_ms"]*1000),
                    ("transition_finished", session["finished_ms"]*1000), ("probe_finished", end)]
    tail = [stage(f"{a[0]}__{b[0]}", a[1], b[1]) for a, b in zip(post_markers, post_markers[1:])]
    active_all = [(e["start_us"], e["end_us"]) for e in events if e["label"] in ("model.parse", "deferred.job")]
    initial_occ = occupancy(initial_intervals, admission["started_us"], admission["finished_us"])
    for span in initial_occ["intervals"]:
        span["start_ms"] = (span.pop("start_us")-origin)/1000
        span["end_ms"] = (span.pop("end_us")-origin)/1000

    task_rows = []
    for path, task in admission["tasks"].items():
        row = {"path": path, "queue_ms": task["queue_us"]/1000,
               "blocked_ms_by_reason": {k: v/1000 for k,v in task["blocked_us_by_reason"].items()},
               "compiled": task["compiled"], "payload_bytes": task["compiled_payload_bytes"],
               "retained_charge_bytes": task["retained_charge_bytes"], "stages": []}
        for st in task["stages"]:
            x = {k: (v-origin)/1000 for k,v in st.items() if k in
                 ("dispatched_us", "worker_started_us", "worker_finished_us", "joined_us")}
            x = {k.replace("_us", "_ms"): v for k,v in x.items()}
            x.update({"worker_wall_ms": st["worker_us"]/1000,
                      "finished_to_join_ms": (st["joined_us"]-st["worker_finished_us"])/1000,
                      "finished_to_all_initial_ms": (initial_finish-st["worker_finished_us"])/1000,
                      "raw_import_lock_wait_ms": st["raw_import_lock_wait_us"]/1000})
            selected = [e for e in events if e.get("details",{}).get("path") == path
                        and e["start_us"] >= st["worker_started_us"]-30
                        and e["end_us"] <= st["worker_finished_us"]+30 and e["label"].startswith("compiled.")]
            x["native_subspans"] = [{"label": e["label"], "start_ms": (e["start_us"]-origin)/1000,
                                      "end_ms": (e["end_us"]-origin)/1000,
                                      "wall_ms": e["duration_us"]/1000} for e in selected]
            row["stages"].append(x)
        task_rows.append(row)
    task_rows.sort(key=lambda r:r["stages"][-1]["worker_finished_ms"])

    initial_native = {}
    model_spans = [e for e in events if e["label"] == "model.parse"]
    for label in ("compiled.payload_sha", "compiled.native_read", "compiled.source_sha", "compiled.read"):
        es = [e for e in events if e["label"] == label and any(
            e["thread_id"] == m["thread_id"] and e["start_us"] >= m["start_us"] and e["end_us"] <= m["end_us"]
            for m in model_spans)]
        initial_native[label] = {"count":len(es), "overlapping_call_sum_ms":sum(e["duration_us"] for e in es)/1000,
                                 "wall_union_ms":union_us([(e["start_us"],e["end_us"]) for e in es])/1000}
    direct_keys = ["cooked_restore_us", "asset_generate_us", "asset_instantiate_us", "mesh_us", "spec_us", "final_integrity_us", "cache_pack_us"]
    direct = sum(mp.get(k,0) for k in direct_keys)
    known = direct+mp["index_worker_us"]
    build_labels = {"game.cooked_restore", "game.asset_generate", "game.asset_instantiate", "game.mesh", "game.spec", "game.index_wait", "game.reference_integrity", "game.cache_pack"}
    build_events = [e for e in events if e["thread_id"] == 1 and e["label"] in build_labels
                    and e["start_us"] >= build["start_us"] and e["end_us"] <= build["end_us"]]
    build_coverage = {"wall_ms":mp["build_total_us"]/1000,"loop_yield_count":mp["frames"],
                      "measured_non_yield_call_wall_ms":direct/1000,"index_wait_wall_ms":mp["index_worker_us"]/1000,
                      "parts_ms":{k.removesuffix("_us"):mp.get(k,0)/1000 for k in direct_keys},
                      "recorded_trace_call_union_ms":union_us([(e["start_us"],e["end_us"]) for e in build_events])/1000,
                      "recorded_trace_call_counts":dict(Counter(e["label"] for e in build_events)),
                      "unattributed_yield_and_other_wall_upper_bound_ms":(mp["build_total_us"]-known)/1000,
                      "unattributed_per_yield_upper_bound_ms":(mp["build_total_us"]-known)/1000/mp["frames"],
                      "cache_pack_executed":"cache_pack_us" in mp,
                      "note":"Direct call wall includes internal native/driver waits, not measured CPU. Unattributed remainder includes process_frame yields, other main callbacks/prefetch pump and uninstrumented setup; it is only an upper bound on frame-idle time. index_wait includes frame yields and is not direct CPU."}

    groups = defaultdict(list)
    for e in events:
        if e.get("duration_us",0) > 0:
            groups[e["label"]].append(e)
    label_stats = {}
    for label, es in groups.items():
        intervals = [(max(origin,e["start_us"]),min(end,e["end_us"])) for e in es]
        label_stats[label] = {"count":len(es), "clipped_wall_union_ms":union_us(intervals)/1000,
                              "clipped_overlapping_sum_ms":sum(b-a for a,b in intervals)/1000,
                              "max_span_ms":max(e["duration_us"] for e in es)/1000,
                              "threads":sorted({e["thread_id"] for e in es})}
    main = [e for e in events if e["thread_id"] == 1 and e.get("duration_us",0) > 0
            and e["label"] not in ("monitor.render_frame_span", "game.build", "model.queue")]
    main.sort(key=lambda e:e["duration_us"],reverse=True)
    main_long = [{"label":e["label"],"start_ms":(e["start_us"]-origin)/1000,
                  "duration_ms":e["duration_us"]/1000,"details":e.get("details",{})} for e in main[:25]]
    overlapping = {}
    for label in ("game.hydrate","game.validate","game.mesh_cache_wait","game.texture_decode",
                  "game.actor_prepare","game.asset_preparation","game.cooked_restore","game.index_wait"):
        es = [e for e in events if e["label"] == label]
        overlapping[label] = [stage(label,e["start_us"],e["end_us"]) for e in es]

    timeline = [{"label":e["label"], "start_ms":(e["start_us"]-origin)/1000,
                 "end_ms":(e["end_us"]-origin)/1000,"duration_ms":e.get("duration_us",0)/1000,
                 "thread_id":e["thread_id"],"details":e.get("details",{}),
                 "crosses_entry_boundary":e["start_us"]<origin or e["end_us"]>end} for e in events]
    timeline.sort(key=lambda e:(e["start_ms"],e["end_ms"]))
    result = {"name":name,"report":str(REPORTS/f"{name}.json"),"origin_ticks_us":origin,
              "flags":{k:report.get(k) for k in ("deferred_native_preparation","deferred_native_budget",
                      "deferred_ready_worker_yield","prepared_collision_faces","collision_face_prefetch","reset_derived_cache")},
              "entry_ms":report["entry_ms"],"core_ms":(core-origin)/1000,
              "safety_ms":(safety-core)/1000,"post_safety_ms":(end-safety)/1000,
              "entry_hardware":hardware_window(hardware,report["entry_epoch_s"],origin,origin,end),
              "major_disjoint_phases":phases,"post_safety_disjoint_markers":tail,
              "overlapping_recorded_stages":overlapping,
              "initial_admission":{"worker_limit":mp["asset_admission"]["worker_limit"],
                     "byte_limit":mp["asset_admission"]["inflight_budget_bytes"],
                     "blocked_ms_by_reason":{k:v/1000 for k,v in admission["blocked_us_by_reason"].items()},
                     "task_wait_sum_ms":admission["task_queue_us"]/1000,
                     "max_task_wait_ms":admission["max_task_queue_us"]/1000,
                     "occupancy":initial_occ,"tasks_by_finish":task_rows},
              "task_activity_by_stage":{},"trace_label_stats":label_stats,"main_thread_long_recorded_spans":main_long,
              "initial_native_substage_intervals":initial_native,"build_coverage":build_coverage,
              "reference_index_read_wall_ms":mp["reference_index_read_us"]/1000,
              "selected_records":mp["reference_selected_count"],"conservative_global_records":mp["entry_conservative_global_records"],
              "wind":world["wind_materials"],"lamp":world["lamp_materials"],
              "navigation_markers":report["navigation_profile"],
              "integrity":{"failures":report["failures"],"trace_dropped":trace["dropped"],
                           "trace_minimum_event_us":trace["minimum_event_us"],"map_sha":report["map_sha"],
                           "formal_sha":report["formal_sha"],"authored_records":report["authored_record_count"],
                           "initial_model_count":len(task_rows),"initial_native_hits":mp["asset_admission"]["native_cache_hits"],
                           "engine_build":report["engine_build"],"hardware_errors":hardware["errors"]}}
    for label,a,b in [("core",origin,core),("initial_worker_envelope",initial_start,initial_finish),
                       ("build",build["start_us"],core),("safety",core,safety),("post_safety",safety,end)]:
        activity=occupancy(active_all,a,b);activity.pop("intervals")
        result["task_activity_by_stage"][label]={**activity,**hardware_window(hardware,report["entry_epoch_s"],origin,a,b)}
    # Preserve all recorded entry trace points, including instant events and
    # render spans, for the three requested detailed reconstructions.
    if name in PRIMARY:
        result["complete_recorded_entry_timeline"]=timeline
    return result


def means(runs):
    out={}
    for label in ("warm_old","warm_new","rebuild_old","rebuild_new"):
        selected=[r for r in runs if r["name"].startswith(label)]
        out[label]={k:statistics.mean(r[k] for r in selected) for k in
                    ("entry_ms","core_ms","safety_ms","post_safety_ms")}
        out[label]["major_phases"]=[{"name":p["name"],"wall_ms":statistics.mean(r["major_disjoint_phases"][i]["wall_ms"] for r in selected),
            "cpu_core_equivalents":statistics.mean(r["major_disjoint_phases"][i]["process_cpu_core_equivalents"] for r in selected)}
            for i,p in enumerate(selected[0]["major_disjoint_phases"])]
    return out


def findings():
    return [
        {"id":"core_breakdown","status":"confirmed","priority":"high",
         "claim":"Warm production core mean about 9.732s is not only a nine-model load. Disjoint means: entry/parser start about 0.533s, initial models not yet started about 1.891s, model worker envelope about 4.678s, post-worker/build transition about 0.141s, main build about 2.489s. Exact values are in means.warm_new.major_phases.",
         "evidence":["warm_new_a/b.major_disjoint_phases","MapLoader starts early models only after authenticated dependency index selection at map_loader.gd:135-153; recorded index read is 1395.771/1483.554ms."],
         "decoupling_candidate":"Keep full trust validation but investigate authenticated dependency-index validation/selection cost before first model dispatch. Geometry/resource-product validation and any overlap must keep snapshot/closure/source identity checks; no unchecked path or bounds hint may authorize publication.",
         "not_proven":"The index stage lacks its own exact trace interval and internal timing, so the whole 1.89s must not be attributed to index CPU or filesystem access."},
        {"id":"initial_workers_vs_cpu","status":"confirmed","priority":"high",
         "claim":"Initial model envelopes are 4683.010/4673.033ms, average active tasks 3.719/3.677 with peak 4; process CPU is 3.992/4.009 core equivalents over the envelope, including concurrent reference/texture/cache work. Initial admission recorded only worker_limit waiting (3820.186/3874.711ms), not byte/exclusive waiting.",
         "evidence":["initial_admission.occupancy","task_activity_by_stage.initial_worker_envelope","initial_admission.blocked_ms_by_reason"],
         "decoupling_candidate":"Separate per-task CPU decode/hash from native resource submission/driver wait before increasing workers. Replay or instrument admission with the same memory ceiling and critical-path ordering; a higher worker cap is not justified solely by machine-wide idle cores.",
         "not_proven":"The 4-core process measurement does not mean four model workers each consume one CPU core. The original hardware thread samples cannot associate Godot trace thread IDs with Win32 thread IDs. Rebuild envelopes consume 7.52/7.68 process cores due to additional concurrent work, so a single average loading CPU percentage obscures real parallel phases."},
        {"id":"initial_read_hash_and_final_tail","status":"confirmed","priority":"high",
         "claim":"All nine initial products are native hits. Native-read calls sum to 11785.955/11443.507ms but their wall unions are 3746.387/3710.751ms. Full source SHA sums 3518.336/3763.181ms with overlapping wall unions 1477.432/1441.563ms. These are not additive wall savings.",
         "evidence":["initial_native_substage_intervals","initial_admission.tasks_by_finish"],
         "decoupling_candidate":"Measure native read subphases (compressed bytes read, decompress, resource deserialization, texture allocation/upload, mesh creation, rendering synchronization) with per-thread CPU and wait reason. Keep the full final source SHA and fixed-product identity.",
         "not_proven":"compiled.native_read is not a disk-only span. Existing traces cannot distinguish CPU, filesystem wait, allocator/ResourceLoader lock or RenderingServer/driver synchronization."},
        {"id":"last_small_model_and_transaction_barrier","status":"confirmed_with_counterfactual_unproven","priority":"medium",
         "claim":"c9c641df... is dispatched last after queueing 3972.575/4021.897ms, then runs 710.766/651.447ms. It is the final initial result in both warm runs; the envelope ends with 417.554/481.087ms with only one task active. Finished results join in about 0.4-8ms, so completed-worker polling is not the seconds-long bottleneck.",
         "evidence":["initial_admission.tasks_by_finish","model_parse_preparation.gd:105-124,174-205","map_loader.gd:363-390"],
         "decoupling_candidate":"A bounded ordering experiment could prioritize a known small final dependency earlier, or introduce unpublished per-result CPU preparation once the closure is validated. Preserve deterministic final ordering, full failure/cancel joins, memory residency accounting and no premature scene publication.",
         "not_proven":"Reordering changes contention and may delay another model; the single-task tail is an observed opportunity, not a guaranteed 0.45s saving. Early results cannot simply bypass the synchronous all-result identity transaction."},
        {"id":"main_build_native_work_vs_frame_yield","status":"confirmed_boundary_unknown_wait_cause","priority":"highest",
         "claim":"Warm build is 2336.700/2641.168ms over 27/28 loop yields. Measured non-yield call wall already covers 1958.213/2154.821ms; index wait adds 38.003/31.878ms. The entire unaccounted remainder is only 340.484/454.469ms (12.61/16.23ms per yield upper bound), including other callbacks and setup. Intentional process_frame yields alone cannot explain the build duration.",
         "evidence":["build_coverage","map_loader.gd:767-839,845-879"],
         "decoupling_candidate":"First split doc._mesh and resource instantiation/material restoration into CPU geometry/descriptor work versus rendering/resource creation. Move only immutable CPU work to admitted workers; schedule engine-affine commits behind the cover and retain the first-visible-frame gate.",
         "not_proven":"Average process CPU is 1.432/1.194 cores during build despite 5.845/5.634 live background model tasks. Main-thread CPU estimates are only 0.37/0.18 cores from coarse samples. This is compatible with native waits plus frame yielding but does not prove which lock or GPU call is responsible. Warm cache pack/write is not executed."},
        {"id":"known_long_main_calls","status":"confirmed_wall_not_cpu","priority":"highest",
         "claim":"Two warm runs record water town_water_10_4 mesh calls of 364.434/370.305ms, terrain town_terrain_5_4 calls of 358.727/335.243ms, and bridge stone_e_0be972769041dbc9 publication of 480.544/481.371ms, including prefab work 431.460/433.674ms. These are indivisible calls exceeding the per-frame budget; more budget cannot preempt or remove them.",
         "evidence":["main_thread_long_recorded_spans","map_loader.gd:816-819","deferred.publication details.prefab_us"],
         "decoupling_candidate":"Add per-call CPU/native wait split and counts for mesh arrays/material/texture construction, then consider private CPU prefab packets or reusable compiled products without altering author geometry, pose, material, collision or cache ownership.",
         "not_proven":"The longer actor preparation call (1217/1255ms) overlaps the early parser/index period, so deleting its duration from entry would overstate savings. Its internal threading/wait is not separately recorded here."},
        {"id":"post_safety_2_52_seconds","status":"confirmed","priority":"high",
         "claim":"Warm safety-to-entry means 2521.734ms. Safety-to-world-playable is 2126.519/2124.011ms; its coarse sequential markers include navigation 791/802ms, environment 318/314ms, player 103.606/85.221ms and material/radar gate 807/825ms. Wind itself records 789.782/813.898ms, of which make-call wall is 480.164/491.760ms for 26 materials and the longest single make is 170.790/171.948ms.",
         "evidence":["post_safety_disjoint_markers","wind","world_3d.gd:314-359","wind_material_preparer.gd:13-48"],
         "decoupling_candidate":"Prepare validated local navigation source data and wind material descriptors/variant keys while core/safety prerequisites arrive; reuse those products at the final gate. Perform resource/shader API work only on its safe thread, keep movement blocked until local navigation/collision and final visual variants are ready, and do not let background work preempt core demand.",
         "not_proven":"Navigation's 0.80s is an outer awaited stage, not 0.80s pure Recast CPU; HUD initialization can overlap its yields. Wind elapsed minus make_ms includes scan, frame pacing and other callbacks, not solely idle time. Merely removing wind preparation would change first-frame behavior."},
        {"id":"transition_presentation_not_load_cpu","status":"confirmed","priority":"medium",
         "claim":"Playable-to-entry remains 405.027/387.904ms. First rendered frame follows playable in 18.087/21.214ms, then first-frame-to-transition-finished is 370/337ms. The source explicitly awaits two process frames and a 0.2s fade before unlocking input. Final_default has the same structure (437.126ms final segment).",
         "evidence":["post_safety_disjoint_markers","scripts/net/game_session.gd:258-277","tools/profile_game_entry.gd:145-156"],
         "decoupling_candidate":"Report technical playable readiness separately from user-visible input unlock. A fade/lock UX change is a distinct product decision, not a CPU loading optimization.",
         "not_proven":"The whole roughly 0.4s cannot be labeled shader compilation, disk wait or a removable fixed sleep."},
        {"id":"default_run_and_scope_limits","status":"confirmed","priority":"context",
         "claim":"final_default complete entry about 16.525s (read the exact per-run field as source of truth) has the same nine model products and overall phase shape. Its build is 3114.924ms with 34 loop yields and 786.621ms unaccounted upper bound, showing timing variability in publication/pacing even with stable model read time. All nine reports retain failures=0, trace drops=0 and matching author/formal map hashes.",
         "evidence":["final_default.major_disjoint_phases","final_default.build_coverage","integrity"],
         "not_proven":"These reports use Godot editor/debug Forward+ build. They are not release/export benchmarks. Subsequent WCT/instrumented diagnostics are intentionally excluded from all timings and means here."},
    ]


def next_monitoring():
    return [
        {"priority":1,"target":"main build and bridge publication",
         "add":"Record monotonic begin/end and same-thread OS CPU deltas per doc._mesh subphase, Cook.restore materials, asset instantiate and bridge prefab publication; add bounded engine/driver wait markers if available.",
         "reason":"Separate observed non-yield wall from CPU, driver/renderer waits and allocator/ResourceLoader locks. Use wait-chain capture only diagnostically and compare a low-overhead control because instrumentation can perturb synchronization."},
        {"priority":1,"target":"native model read",
         "add":"Record native compressed-read/decompress/deserialize/image conversion/upload/mesh upload/native validation timings and Windows thread ID at worker start/end; correlate with source/payload identity and memory stage.",
         "reason":"The existing native_read span combines all of these; more live workers is not proof of more useful CPU work."},
        {"priority":1,"target":"build coroutine pacing",
         "add":"Record each batch start/end, records advanced, remaining budget, direct work elapsed, exact before-await and resumed timestamps, prefetch pump interval and process/render frame IDs.",
         "reason":"Current frames count constrains the maximum unexplained yield gap but cannot distinguish frame pacing from callback/native wait time or attribute the larger default-run remainder."},
        {"priority":2,"target":"initial dependency index and model transaction",
         "add":"Trace index read/parse/path preflight/closure validation/selection separately; log all model enqueue/reserve reasons, worker completion, join, per-result CPU-ready/commit-ready, byte ownership and rejected stale identities.",
         "reason":"Measure whether safe per-result preparation or changed ordering can shorten the observed final single-task tail without bypassing full input checks or memory admission."},
        {"priority":2,"target":"navigation and wind material tail",
         "add":"Split navigation snapshot/source collection/bake/native publication and HUD overlap; log each unique material variant lookup/make/compile or sync, exact frame yields and reusable generation key.",
         "reason":"Potential overlap is real at dependency level but its gain cannot be predicted by summing nested outer stage counters."},
        {"priority":2,"target":"benchmark reporting",
         "add":"Keep core-resources, safety geometry, technical playable, first visible frame and input-unlocked timestamps separate. Preserve process CPU, private/RSS, trace drops, identical map/source/payload hashes, geometry and visual equivalence, failure/cancel/revisit checks.",
         "reason":"Do not improve the number by suppressing content or moving required work after the player's first frame."},
    ]


def main():
    runs=[analyze(n) for n in NAMES]
    result={"schema":1,"generated_utc":datetime.now(timezone.utc).isoformat(),
            "scope":"Offline report/source review only; no Godot, assets, new source hashes or production changes.",
            "units":"All relative timestamps are milliseconds from measured entry start. Godot trace thread IDs are not Windows thread IDs.",
            "methodology":[
                "Disjoint phases sum to entry wall time. Overlapping stage/event sums are never treated as additional wall or CPU time.",
                "Process CPU core equivalents interpolate cumulative process CPU seconds at stage boundaries and divide by wall seconds; this includes all process threads.",
                "Initial/deferred task activity is interval occupancy, not CPU utilization. A live ResourceLoader call can block on I/O, locks, rendering or driver work.",
                "Hardware samples are coarse (about 0.6 seconds); subsecond stage CPU is only a boundary-interpolated estimate. No runnable/wait stacks or CPU attribution inside native reads exist.",
                "Thread CPU can miss short-lived threads. Main-thread CPU uses recorded Windows main_thread_id, never Godot trace ID 1 as an OS ID.",
                "Trace excludes durations below 500 microseconds despite zero drops. Full recorded entry timelines are preserved for warm_new_a/b and final_default, including boundary-crossing events.",
                "world_profile msec markers have roughly one-millisecond quantization. The wind elapsed metric includes frame yields; make_ms is measured call wall time, not proven shader CPU time.",
                "The eight-run comparison toggles five features together; neither CPU improvement nor full-entry benefit can be attributed solely to native budgeting.",
            ],"means":means(runs),"runs":runs,"findings":findings(),"next_monitoring":next_monitoring()}
    (ROOT/"timeline_review.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"artifact":str(ROOT/"timeline_review.json"),"runs":len(runs),"means":result["means"],
                      "primary": [{"name":r["name"],"initial_occupancy":{k:v for k,v in r["initial_admission"]["occupancy"].items() if k!='intervals'},
                                   "task_activity":r["task_activity_by_stage"],"tail":r["post_safety_disjoint_markers"]}
                                  for r in runs if r["name"] in PRIMARY]},ensure_ascii=False))


if __name__=="__main__":
    main()
