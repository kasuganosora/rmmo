"""Summarize axel cold-start reports without confusing entry and full readiness.
Engine ticks begin inside Godot, not at the external launcher's process creation.
This tool reads completed reports only; it never flushes caches or starts a game.
"""
import argparse,bisect,json,math
from pathlib import Path

def summary(path):
 r=json.loads(path.read_text(encoding="utf-8"));ready=r.get("origin_first_ready",{}).get("at_ms")
 result={"file":path.name,"initialize_ms":r.get("startup",{}).get("initialize_us",0)/1000,"loader_ms":r.get("loader_ms"),"entry_ms":r.get("entry_ms"),"full_ready_ms":ready,"engine_start_to_full_ready_ms":None if ready is None else r["begin_ticks_us"]/1000+ready,"failures":r.get("failures",[]),"indexed_top":r.get("indexed_terrain_top"),"resource_bundle_enabled":r.get("controls",{}).get("resource_bundles"),"resource_bundle_mounted":r.get("resource_bundle",{}).get("mounted",False),"source_snapshot_equal":None if not r.get("sources") or not r.get("sources_after") else r["sources"]==r["sources_after"],"map_sha_equal":None if not r.get("map_sha") or not r.get("map_sha_after") else r["map_sha"]==r["map_sha_after"],"frames":{}}
 for phase in sorted({f["phase"] for f in r.get("frames",[])}):
  values=sorted(f["ms"] for f in r["frames"] if f["phase"]==phase)
  if values:result["frames"][phase]={"count":len(values),"p50_ms":values[math.ceil(.5*len(values))-1],"p95_ms":values[math.ceil(.95*len(values))-1],"max_ms":values[-1]}
 mp=r.get("map_profile",{});result["cache_observations"]={k:mp.get(k) for k in ["reference_index_hit","mesh_cache_candidate","terrain_context_cache_hit","metadata_cache_hit","entry_road_cache_hits"]}
 result["entry_work"]={k:mp.get(k) for k in ["parse_us","hydrate_us","reference_index_rebuild_build_us","terrain_context_worker_us","terrain_join_wait_us","entry_surface_bounds"]}
 if ready is not None:
  q=next((q for q in r.get("queues",[]) if q["at_ms"]>=ready),None)
  if q:
   pr=q.get("deferred",{}).get("profile",{});result["work"]={k:pr.get(k) for k in ["reference_reads_started","reference_handoff_records","instances","specs","models","reference_prefab_faces_prepared_vertices","reference_road_cache_hits","reference_worker_us","native_surface_worker_us"]}
 result["render"]={k:v for k,v in r.get("render_sources",{}).items() if not isinstance(v,(dict,list))}
 cp=path.with_suffix(".cpu.json")
 if ready is not None and cp.exists():
  c=json.loads(cp.read_text(encoding="utf-8"));a=r["cpu_time_anchor"];times=[x[0]//1000 for x in c["samples"]];tid=c["metadata"]["main_win32_tid"]
  def at(ms):
   stamp=a["unix_us"]+r["begin_ticks_us"]-a["ticks_us"]+ms*1000
   index=bisect.bisect_left(times,stamp);index=min(index,len(times)-1)
   if index>0 and abs(times[index-1]-stamp)<abs(times[index]-stamp):index-=1
   return dict(c["samples"][index][2])
  if times:
   begin=at(0);entry=at(r["entry_ms"]);end=at(ready)
   result["cpu_ms"]={"load_main":(end[tid]-begin[tid])/1000,"load_process":(end[0]-begin[0])/1000,"tail_main":(end[tid]-entry[tid])/1000,"tail_process":(end[0]-entry[0])/1000,"scope":"nearest owned-process samples; scheduler CPU granularity, not exclusive function cost"}
 return result

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument("files",nargs="+",type=Path);p.add_argument("--output",type=Path);a=p.parse_args()
 rows=[summary(f) for f in a.files];text=json.dumps(rows,ensure_ascii=False,indent=2)
 if a.output:a.output.write_text(text,encoding="utf-8")
 print(text)
if __name__=="__main__":main()
