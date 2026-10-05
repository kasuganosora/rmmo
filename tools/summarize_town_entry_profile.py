"""Summarize captured town frame traces without discarding outliers.

Usage: python tools/summarize_town_entry_profile.py path/to/profile.json
Writes a reviewable sibling .md; the original per-frame JSON stays intact.
"""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    samples = report["samples"]
    lines = [
        "# 城镇跨区性能记录",
        "",
        f"原始数据：`{args.report.resolve().as_posix()}`",
        f"地图 SHA-256：`{report['map']}`",
        "",
        f"加载路径：{report['loader']}；失败数：{report['failures']}；"
        f"整图导航完成：{report.get('navigation_fully_ready', '未记录')}；"
        f"诊断暂停导航：{report.get('navigation_paused', False)}。",
        "",
        f"共 {len(samples):,} 帧；中位数 {report['median']:.3f} ms，"
        f"P95 {report['p95']:.3f} ms，P99 {report['p99']:.3f} ms，"
        f"最长 {report['max']:.3f} ms，超过 50 ms 共 {report['over50']} 帧。",
        "",
        f"导航缓存命中：{report.get('navigation_profile', {}).get('cache_hit', '未记录')}；"
        f"测量前等待全图导航：{report.get('waited_for_navigation', False)}；"
        f"测试关闭 VSync：{report.get('vsync_disabled', False)}；"
        f"路线后静止等待导航的采样帧：{report.get('navigation_drain_frames', 0)}。",
        "不删除尖峰；缓存、导航准备状态、VSync 或路线不同的报告不直接计算提速比例。",
        "",
        f"精确地面查询：{report.get('surface_queries', '未记录')}；"
        f"已证明支持点缓存命中：{report.get('surface_cache_hits', '未记录')}；"
        f"空间索引命中：{report.get('surface_index_hits', '未记录')}。",
        "",
        "|轮次|环境|中位数 ms|P95 ms|P99 ms|最长 ms|>50 ms|",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for row in report.get("per_pass", []):
        lines.append(
            f"|{row['pass'] + 1}|{'夜间' if row['night'] else '白天'}|"
            f"{row['median']:.3f}|{row['p95']:.3f}|{row['p99']:.3f}|"
            f"{row['max']:.3f}|{row['over50']}|"
        )
    if "terrain_slicing" in report:
        streams = sorted(row.get("parts", {}).get("stream", 0) for row in samples)
        lines += ["", f"地形碰撞分片：{report['terrain_slicing']}；"
                  f"流式/合批共享预算：{report.get('shared_stream_budget', False)}。",
                  f"采样中的流式阶段 P99 {streams[int(len(streams)*.99)]:.3f} ms，"
                  f"最长 {streams[-1]:.3f} ms。分段监视器可能来自邻近帧，不能相加。"]
    if samples and "pipelines" in samples[0]:
        before, after = samples[0]["pipelines"], samples[-1]["pipelines"]
        lines += ["", "管线计数（采样起点 → 终点）：" + "；".join(
            f"{key} {before[key]:.0f} → {after[key]:.0f}" for key in before) + "。",
            "这些计数只用于区分编译阶段；不能将后台 specialization 增加直接等同于同步编译尖峰。"]
    toggles = report.get("toggle_timings", [])
    if toggles:
        durations = sorted(row["ms"] for row in toggles)
        lines += ["", "## 连续昼夜切换", "",
                  f"切换 {len(toggles)} 次；请求耗时中位数 {durations[len(durations)//2]:.3f} ms，"
                  f"P99 {durations[int(len(durations)*.99)]:.3f} ms，最长 {durations[-1]:.3f} ms。",
                  "每次切换都核对全街区 33 盏灯；完整逐次分段计时保留在 JSON。",
                  "各轮实际均混合昼夜，上方环境列只表示轮次起始状态。"]
    clicks = report.get("click_timings", [])
    if clicks:
        lines += ["", f"点击请求 {len(clicks)} 次，最长 {max(row['ms'] for row in clicks):.3f} ms；"
                  "点击耗时包含在该段首帧中。"]
    lines += [
        "",
        "## 最慢的 20 帧",
        "",
        "阶段耗时是该采样附近的观测值，不相加，也不单凭相关性断言原因。",
        "导航阶段携带引擎帧编号，完整定位请查看 JSON 和对应 live.log。",
        "",
        "|帧 ms|位置|轮次|夜间|流式 ms|导航准备 ms|导航发布 ms|物理 ms|渲染 CPU ms|GPU ms|",
        "|---:|---|---:|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in sorted(samples, key=lambda sample: sample["ms"], reverse=True)[:20]:
        lines.append(
            f"|{row['ms']:.3f}|{row['position']}|{row.get('pass', 0) + 1}|"
            f"{row.get('night', False)}|{row['parts'].get('stream', 0):.3f}|"
            f"{row.get('nav_background', {}).get('ms', 0):.3f}|"
            f"{row.get('nav_publication', {}).get('ms', 0):.3f}|"
            f"{row['physics']:.3f}|{row.get('render_cpu', 0):.3f}|{row['gpu']:.3f}|"
        )
    output = args.report.with_suffix(".md")
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
