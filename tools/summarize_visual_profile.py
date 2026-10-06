"""Match a Godot visual-profiler capture to a town route by render-frame ID.

Usage: python tools/summarize_visual_profile.py CAPTURE.json ROUTE.json
Writes a sibling Markdown report; loading frames are excluded by route membership.
Native markers are cumulative timestamps, so adjacent differences are intervals,
not independent values to sum across nested scopes.
"""
import argparse
import json
from pathlib import Path
import statistics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("route", type=Path)
    args = parser.parse_args()
    capture = json.loads(args.capture.read_text(encoding="utf-8"))
    route = json.loads(args.route.read_text(encoding="utf-8"))
    frames = {row[0]: row for row in capture["frames"]}
    joined = []
    differences = []
    for sample in route["samples"]:
        raw = frames.get(sample.get("engine", {}).get("frame"))
        if raw is None or len(raw) != raw[1] + 2:
            continue
        markers = [raw[i:i + 3] for i in range(2, len(raw), 3)]
        begins = [row[1] for row in markers if row[0].startswith("vp_begin_")]
        ends = [row[1] for row in markers if row[0].startswith("vp_end_")]
        if not begins or not ends:
            continue
        differences.append(abs(ends[-1] - begins[-1] - sample["render_cpu"]))
        intervals = [(a[0], b[1] - a[1], b[2] - a[2])
                     for a, b in zip(markers, markers[1:])]
        joined.append((sample, intervals))
    if not joined or max(differences) > .01:
        raise RuntimeError("Render-frame alignment does not match viewport CPU timings")
    diagnostics = capture.get("errors", [])
    warnings = sum(len(row) > 9 and row[9] is True for row in diagnostics)
    lines = ["# 原生渲染分段诊断", "",
             f"硬件：{capture.get('hardware', [])}", "",
             f"匹配路线 {len(joined)} 帧；视口 CPU 计时差最大 {max(differences):.6f} ms。",
             f"引擎诊断：警告 {warnings} 条，错误 {len(diagnostics) - warnings} 条。",
             "分析器开启期间的数据仅用于定位，不作为普通帧率验收。",
             "按渲染帧编号匹配；相邻原生时间戳之差表示分段，不能重复累加嵌套范围。", "",
             "|整帧 ms|位置|渲染帧|最大 CPU 分段|CPU ms|GPU ms|",
             "|---:|---|---:|---|---:|---:|"]
    for sample, intervals in sorted(joined, key=lambda row: row[0]["ms"], reverse=True)[:20]:
        name, cpu, gpu = max(intervals, key=lambda row: row[1])
        lines.append(f"|{sample['ms']:.3f}|{sample['position']}|{sample['engine']['frame']}|"
                     f"{name}|{cpu:.3f}|{gpu:.3f}|")
    stages = {}
    for _, intervals in joined:
        totals = {}
        for name, cpu, _ in intervals:
            if not name.startswith((">", "<", "vp_")):
                totals[name] = totals.get(name, 0.) + cpu
        for name, value in totals.items():
            stages.setdefault(name, []).append(value)
    lines += ["", "|分段（同帧同名累计）|中位 ms|P99 ms|最大 ms|",
              "|---|---:|---:|---:|"]
    for name, values in sorted(stages.items(), key=lambda row: max(row[1]), reverse=True)[:15]:
        values.sort()
        lines.append(f"|{name}|{statistics.median(values):.3f}|"
                     f"{values[int(len(values)*.99)]:.3f}|{values[-1]:.3f}|")
    args.capture.with_suffix(".md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Matched", len(joined), "frames; maximum alignment error", max(differences), "ms")


if __name__ == "__main__":
    main()
