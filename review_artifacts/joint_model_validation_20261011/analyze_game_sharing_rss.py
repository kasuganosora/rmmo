"""Align existing game-sharing memory observations; no target process access."""
import json
from pathlib import Path
from statistics import mean

from analyze_results import read_json

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = Path(__file__).with_name("game_sharing_rss_analysis.json")
NAMES = ["game_sharing_off_a1_v2", "game_sharing_on_b1_v2", "game_sharing_on_b2_v2", "game_sharing_off_a2_v2"]
runs = []
for name in NAMES:
    d = read_json(ROOT / (name+".json"))
    h = read_json(ROOT / (name+".hardware.json"))
    m = d["monitor"]
    a, b = d["entry_epoch_s"], d["entry_end_epoch_s"]
    conv = lambda tick: m["start_epoch_s"]+(tick-m["start_ticks_us"])/1e6
    events = m["trace"]["events"]
    main_id = m["main_thread_id"]
    origin = h["samples"][0]
    hardware_samples = [{**s, "aligned_epoch_s": origin["epoch_s"]+s["monotonic_s"]-origin["monotonic_s"]} for s in h["samples"]]
    monitor_samples = [{**s, "epoch_s": conv(s["ticks_us"])} for s in m["samples"]]
    tasks = d["map_profile"]["asset_admission_details"]["tasks"]
    def point(s):
        epoch = s["aligned_epoch_s"]
        tick = m["start_ticks_us"]+(epoch-m["start_epoch_s"])*1e6
        nearest_monitor = min(monitor_samples, key=lambda v: abs(v["epoch_s"]-epoch))
        active_jobs = [e for e in events if e["label"]=="deferred.job" and e["start_us"]<=tick<e["end_us"]]
        initial_active = [{"path": path, "bytes": stage["reserved_bytes"]} for path, task in tasks.items() for stage in task["stages"] if stage["dispatched_us"]<=tick<stage["joined_us"]]
        initial_joined = [path for path, task in tasks.items() if all(stage["joined_us"]<=tick for stage in task["stages"])]
        jobs_done = [e for e in events if e["label"]=="deferred.job" and e["end_us"]<=tick]
        spans = [e for e in events if e["start_us"]<=tick<e["end_us"] and e["label"] in ("game.build", "game.asset_instantiate", "compiled.native_read", "compiled.payload_sha", "compiled.source_sha", "deferred.compiled_instantiate", "deferred.cpu_capture")]
        return {"after_entry_start_ms": (epoch-a)*1000, "after_entry_end_ms": (epoch-b)*1000,
                "rss_bytes": s["rss_bytes"], "private_bytes": s["private_bytes"],
                "nearest_monitor": {key: nearest_monitor[key] for key in ("phase", "static_memory_bytes", "render_texture_bytes", "render_buffer_bytes", "objects", "details")},
                "monitor_offset_ms": (nearest_monitor["epoch_s"]-epoch)*1000,
                "initial_active_tasks": initial_active, "initial_joined_count": len(initial_joined),
                "initial_retained_charge_after_join_bound": sum(tasks[path]["retained_charge_bytes"] for path in initial_joined),
                "deferred_active_worker_jobs": [{"path": e["details"].get("path"), "need_model": e["details"].get("need_model"), "native_reference": e["details"].get("native"), "worker_thread_id": e["thread_id"]} for e in active_jobs],
                "deferred_worker_jobs_finished_so_far": len(jobs_done),
                "overlapping_spans": [{"label": e["label"], "path": e["details"].get("path"), "main_thread": e["thread_id"]==main_id} for e in spans]}
    exact = [s for s in hardware_samples if a<=s["aligned_epoch_s"]<=b]
    endpoint_indices = set()
    for i in range(1, len(hardware_samples)):
        if max(a, hardware_samples[i-1]["aligned_epoch_s"])<min(b, hardware_samples[i]["aligned_epoch_s"]):endpoint_indices.update((i-1, i))
    endpoint_samples = [hardware_samples[i] for i in endpoint_indices]
    background_end = m["start_epoch_s"]+m["span_ms"]/1000
    def nearest(target):return point(min(hardware_samples, key=lambda s: abs(s["aligned_epoch_s"]-target)))
    entry_monitor = max((s for s in monitor_samples if s["epoch_s"]<=b), key=lambda s:s["epoch_s"])
    final_monitor = monitor_samples[-1]
    runs.append({"name": name, "variant": "on" if d["model_texture_sharing"] else "off",
                 "entry_ms": d["entry_ms"], "core_ready_ms": d["entry_core_ready_ms"],
                 "exact_window_rss_peak": point(max(exact, key=lambda s:s["rss_bytes"])),
                 "exact_window_private_peak": point(max(exact, key=lambda s:s["private_bytes"])),
                 "including_boundary_endpoints_rss_peak": point(max(endpoint_samples, key=lambda s:s["rss_bytes"])),
                 "including_boundary_endpoints_private_peak": point(max(endpoint_samples, key=lambda s:s["private_bytes"])),
                 "aligned_points": {"entry_start": nearest(a), "entry_end": nearest(b), "entry_plus_1s": nearest(b+1),
                                    "entry_plus_5s": nearest(b+5), "background_finish": nearest(background_end)},
                 "monitor_entry_last": {key: entry_monitor[key] for key in ("epoch_s", "phase", "static_memory_bytes", "render_texture_bytes", "render_buffer_bytes", "objects")},
                 "monitor_background_last": {key: final_monitor[key] for key in ("epoch_s", "phase", "static_memory_bytes", "render_texture_bytes", "render_buffer_bytes", "objects", "details")},
                 "hardware_timeline_before_probe": [point(s) for s in hardware_samples if a-1<=s["aligned_epoch_s"]<=background_end],
                 "residency_limit": "The trace gives worker durations, initial dispatch/join reservation, and final aggregate ledger. A finished deferred.job is not proof that its accepted/result/native ownership has retired; no full resident-owner or per-lease release history exists in these reports. Initial retained charge is a conservative bound, not actual RSS."})

groups = {kind: [r for r in runs if r["variant"]==kind] for kind in ("off", "on")}
comparison = {}
for label in runs[0]["aligned_points"]:
    comparison[label] = {field: {kind: mean(r["aligned_points"][label][field] for r in groups[kind]) for kind in groups} for field in ("rss_bytes", "private_bytes")}
    for field in comparison[label]:comparison[label][field]["on_minus_off"]=comparison[label][field]["on"]-comparison[label][field]["off"]
for label in ("monitor_entry_last", "monitor_background_last"):
    comparison[label] = {field: {kind: mean(r[label][field] for r in groups[kind]) for kind in groups} for field in ("static_memory_bytes", "render_texture_bytes", "render_buffer_bytes", "objects")}
    for field in comparison[label]:comparison[label][field]["on_minus_off"]=comparison[label][field]["on"]-comparison[label][field]["off"]
result = {"scope": "Detailed read-only memory follow-up to game sharing v2. Uses existing hardware and 200ms engine monitor counters, not new process sampling or source hashing.",
          "runs": runs, "comparison": comparison,
          "findings": [
              "The +315MiB mean entry RSS peak cannot be dismissed as boundary sampling alone: both on runs retain about +256MiB RSS at entry end and through the subsequent ten-second runtime, with nearly identical private commit and Godot static-memory counters. Before entry both variants are around 777MiB RSS/798MiB private. The persistent difference appears during core construction/native preparations, not as a preexisting process baseline difference.",
              "Peak timing is not equivalent: B1/B2 reach about 3546/3544MiB at 9.594/9.845s in game.build while several deferred native reads overlap. A1's strict-window maximum occurs near entry end (~3149MiB) and A2 at9.454s (~3282MiB). All nine initial jobs have joined at these peaks; active native work is deferred. Task overlap contributes to peak differences, but cannot explain away the stable later ~256MiB gap.",
              "Engine monitor already proves renderer texture savings by entry: off last entry samples2654.8MiB, on2206.8/2222.8MiB; final background2657.2 versus2209.2/2225.2MiB. Godot static CPU memory stays~863MiB at entry and~896MiB at background finish; renderer buffers are effectively equal. Therefore the RSS increase does not track more live Godot-managed CPU bytes or more renderer texture allocation. Neither monitor is an exhaustive process/driver allocation census.",
              "Static apply/weak-pool review finds no persistent strong-reference pool or new image allocation: _textures stores only bounded WeakRefs, apply retains original/shared references in local seen/retired through one main-thread force_sync and clears both before return. AssetLibrary.cache_scene clears compiled owner after packing and scene disposal. First native instantiation only rebinds materials once per template; worker calls return before sharing. WeakRef object-count growth of~60 is consistent with60 pool keys and far too small to explain256MiB.",
              "Real synchronization side effects remain plausible: the on path adds force_sync before releasing replaced textures. That may change execution/retirement overlap, driver allocations and which existing committed or mapped pages are physically resident. The current reports contain no per-apply/force_sync timestamps, Windows working-set page categories, page-fault events, mapping allocation identities or driver residency counters. Calling this a proven driver cache, benign paging effect, memory leak or fixed-size staging block would exceed the evidence.",
              "Windows RSS here is psutil memory_info.rss (working set); private is psutil memory_info.private (private commit). Working set counts physically resident pageable pages and can change while private committed address space remains constant. This distinction explains why equal private values do not contradict greater RSS, but does not by itself establish that the increase has no cost or is harmless."
          ],
          "decision": {"previous_no_blocker_conclusion_scope": "Earlier local functional/texture identity checks remain passed; they were not proof of no RSS side effect.",
                       "recommendation": "Do not finalize the default-on release as having no negative impact yet. Keep derived build work as preparatory and run a focused same-product/off-on page-classification pair. If higher RSS maps to extra live private allocation or retained mappings caused by sharing, fix or bound it before activation; if it is working-set redistribution with no extra commitment/live ownership, document that evidence and evaluate the actual memory tradeoff.",
                       "targeted_probe": "Read-only QueryWorkingSet + VirtualQueryEx aggregation by MEM_PRIVATE/MAPPED/IMAGE, shared bit/share count and allocation base; GetProcessMemoryInfo before/after. Trigger only after entry, ten-second monitor and physics, paired with renderer/static/object counters; do not touch pages, trim working set, or change engine gates.",
                       "if_probe_insufficient": "A second targeted per-apply diagnostic should sample before rebind, before/after the existing synchronize_transfer, and after retired.clear, with allocation-region snapshots or WPR/ETW page-fault/allocation evidence. Do not remove a lifetime-safety synchronization merely to lower RSS."},
          "primary_sources": [{"url":"https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex", "supports":"WorkingSetSize is current working set; PrivateUsage is private commit charge."},
                              {"url":"https://learn.microsoft.com/en-us/windows/win32/memory/working-set", "supports":"Working set represents pageable pages currently resident in physical memory; page faults and trimming affect residency independently of commitment."}],
          "static_locations": [{"path":"tools/profile_load_hardware.py","line":112,"finding":"rss/private collected directly from psutil memory_info."},
                               {"path":"scripts/world3d/model_texture_cache.gd","line":67,"finding":"Main-only apply retains only temporary old/new resource references, force_sync then clears them."},
                               {"path":"scripts/world3d/model_texture_cache.gd","line":97,"finding":"Weak pool bounded256 keys; no strong texture residency owner."},
                               {"path":"scripts/world_editor/asset_library.gd","line":224,"finding":"Validated template rebind once, later instances use shared template materials."},
                               {"path":"scripts/world_editor/asset_library.gd","line":284,"finding":"cache_scene repacks/disposes scene and releases temporary compiled keepalive."}],
          "limits": ["No engine or process probe was run for this report; forthcoming memory-pages results remain required.",
                     "Trace suppresses spans shorter than500us; absence of a game.asset_instantiate event is not absence of an instance or sharing call.",
                     "Engine monitor samples and OS samples are asynchronous; nearest monitor offsets are persisted, not assumed simultaneous.",
                     "Deferred task completion is not lease/resource retirement; no exact resident ledger replay is possible from these logs."]}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output":str(OUT),"comparison":comparison,"decision":result["decision"]},ensure_ascii=False,indent=2))
