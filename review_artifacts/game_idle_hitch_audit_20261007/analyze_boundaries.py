"""Read completed diagnostic JSON only; no project mutation or engine execution."""
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("source")
args = parser.parse_args()
with open(args.source, encoding="utf-8") as handle:
    report = json.load(handle)

def duration(row, first, last):
    begin, end = row.get(first, 0), row.get(last, 0)
    return round((end - begin) / 1000, 3) if begin and end >= begin else None

wrappers, skies = [], []
for sample in report["samples"]:
    frame = sample["engine"]["frame"]
    common = {"frame": frame, "frame_ms": sample["ms"], "position": sample["position"]}
    wrapper = sample.get("collision_wrapper", {})
    if wrapper.get("frame") == frame:
        for row in wrapper.get("calls", []):
            item = dict(common, uuid=row["uuid"], raw=row)
            for label, begin, end in [
                ("total", "outer_begin_us", "outer_end_us"),
                ("entry", "outer_begin_us", "wrapper_begin_us"),
                ("prefix", "wrapper_begin_us", "impl_begin_us"),
                ("impl", "impl_begin_us", "impl_end_us"),
                ("build_metadata", "impl_end_us", "publish_begin_us"),
                ("publish", "publish_begin_us", "publish_end_us"),
                ("return", "return_begin_us", "outer_end_us"),
            ]:
                item[label + "_ms"] = duration(row, begin, end)
            wrappers.append(item)
    sky = sample.get("sky_details", {})
    if sky.get("frame") == frame:
        for row in sky.get("calls", []):
            item = dict(common, polled=row["polled"], accepted=row["accepted"], raw=row)
            for label, begin, end in [
                ("total", "begin_us", "return_end_us"),
                ("setup", "begin_us", "setup_end_us"),
                ("provider", "provider_begin_us", "provider_end_us"),
                ("receive", "receive_begin_us", "receive_end_us"),
                ("sample", "sample_begin_us", "sample_end_us"),
                ("star_uniform", "sample_end_us", "star_uniform_end_us"),
                ("packed_arrays", "star_uniform_end_us", "arrays_end_us"),
                ("meteor_uniform", "arrays_end_us", "meteor_uniform_end_us"),
                ("return", "meteor_uniform_end_us", "return_end_us"),
            ]:
                item[label + "_ms"] = duration(row, begin, end)
            item["revision_ms"] = duration(row, "receive_end_us" if row["polled"] else "setup_end_us", "revision_end_us")
            skies.append(item)

print(json.dumps({
    "source": args.source,
    "wrapper_calls": len(wrappers),
    "sky_calls": len(skies),
    "worst_wrappers": sorted(wrappers, key=lambda row: row["total_ms"] or 0, reverse=True)[:8],
    "worst_skies": sorted(skies, key=lambda row: row["total_ms"] or 0, reverse=True)[:8],
}, ensure_ascii=False, indent=2))
