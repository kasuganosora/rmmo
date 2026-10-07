"""Correlate completed route/WCT/main-thread CPU reports; no process inspection."""
import argparse
from bisect import bisect_left, bisect_right
from collections import Counter
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--base", type=Path, default=Path("D:/code/rmmo_runtime/review_artifacts"))
parser.add_argument("--label", default="river_bridge_wait_chain_20261007")
parser.add_argument("--out", type=Path, required=True)
a = parser.parse_args()
r = json.loads((a.base / "town_street_entry_20261005" / (a.label + ".json")).read_text())
suffix = a.label.removesuffix("_20261007")
w = json.loads((a.base / (suffix + "_wct_20261007.json")).read_text())
c = json.loads((a.base / (suffix + "_thread_20261007.json")).read_text())
ct = [v[0] for v in c["samples"]]
mt = [v[0] for v in c["memory_samples"]]
off = r["unix_offset"]

def interval(name, first, last):
    begin, end = off + first / 1e6, off + last / 1e6
    item = dict(name=name, begin_us=first, end_us=last, wall_ms=(last-first)/1000)
    for tag, i, j in [("outer", bisect_right(ct,begin)-1, bisect_left(ct,end)),
                      ("inner", bisect_left(ct,begin), bisect_right(ct,end)-1)]:
        if 0 <= i < j < len(ct):
            x,y = c["samples"][i], c["samples"][j]
            item[tag] = dict(wall_ms=(y[0]-x[0])*1000, cpu_ms=(y[1]-x[1])*1000, cycles=y[2]-x[2])
    i,j=bisect_right(mt,begin)-1,bisect_left(mt,end)
    if 0 <= i < j < len(mt):
        x,y=c["memory_samples"][i],c["memory_samples"][j]
        item["memory_outer"] = dict(wall_ms=(y[0]-x[0])*1000,rss_delta=y[1]-x[1],page_fault_delta=y[3]-x[3])
    item["wct_queries_started_inside"]=[q for q in w["samples"] if begin <= q["unix_begin"] <= end]
    item["wct_queries_overlap"]=[q for q in w["samples"] if q["unix_begin"] <= end and q["unix_begin"]+q["query_ms"]/1000 >= begin]
    return item

peaks=[]
for s in r["samples"]:
    if s["ms"] <= 50:continue
    e=s["engine"]
    ranges=[("process_to_sample",e["process_begin_usec"],s["ticks_usec"]),
            ("postprocess_to_draw",e["process_end_usec"],e["draw_begin_usec"]),
            ("draw",e["draw_begin_usec"],e["draw_end_usec"])]
    wind=s.get("wind",{})
    if wind.get("ms",0)>20:
        ranges.append(("wind",wind["begin_usec"],wind["end_usec"]))
        for k in ("nodes","keys"):
            v=wind.get("cancel_timeline",{})
            if k+"_begin_usec" in v:ranges.append(("wind_cancel_"+k,v[k+"_begin_usec"],v[k+"_end_usec"]))
    peaks.append(dict(frame=e["frame"],position=s["position"],ms=s["ms"],radar=s["radar"],physics=s["physics_work"],
                      intervals=[interval(*row) for row in ranges]))
qms=sorted(q["query_ms"] for q in w["samples"])
output=dict(label=a.label,flags=w["flags"],wct_counts=dict(Counter(str((q["count"],q["nodes"][0]["status"] if q["nodes"] else "")) for q in w["samples"])),
            query_median=qms[len(qms)//2],query_p95=qms[int(len(qms)*.95)],query_max=max(qms),
            multichains=[dict(q,relative_us=(q["unix_begin"]-off)*1e6) for q in w["samples"] if q["count"]>1], peaks=peaks)
a.out.write_text(json.dumps(output,indent=2),encoding="utf-8")
for p in peaks:
    print("FRAME",p["frame"],p["ms"],p["position"])
    for v in p["intervals"]:
        print(v["name"],round(v["wall_ms"],3),"outer",v.get("outer"),"inner",v.get("inner"),"wct",[(q["count"],[n["status"] for n in q["nodes"]],q["query_ms"]) for q in v["wct_queries_started_inside"]])
print("WCT cost",output["query_median"],output["query_p95"],output["query_max"])
