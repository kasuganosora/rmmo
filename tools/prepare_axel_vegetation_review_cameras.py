"""Prepare 3 outdoor detail cameras from saved native vegetation placements.
No map edits/GPU. Requires a native final-record export envelope:
{"map_sha256": "<build output SHA>", "records": [Doc.records ...]}.
Default prints proposal; --apply atomically appends/replaces only our three IDs.
"""
import argparse
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import numpy as np

OUT = Path("D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016")
IDS = {"vegetation_tree_roots", "vegetation_shrub_detail", "vegetation_crop_detail"}

def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def basis(record):
    x,y,z = np.radians(record.get("rotation", [0,0,0]))
    cx,sx,cy,sy,cz,sz = math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    return np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]]) @ np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]]) @ np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])

def bounds(record):
    if record.get("kind") == "asset":
        if "bounds_position" not in record or "bounds_size" not in record:
            raise ValueError("Missing native asset bounds: " + str(record.get("uuid")))
        lo=np.array(record["bounds_position"]); size=np.array(record["bounds_size"])
        scale=np.array(record.get("size",[1,1,1]))
    else:
        size=np.array(record.get("size",[1,1,1]));lo=-size/2;scale=np.ones(3)
    points=np.array([basis(record) @ ((lo+size*np.array(c))*scale)+record["position"] for c in itertools.product([0,1],repeat=3)])
    return points.min(axis=0),points.max(axis=0)

def ground(records,x,z):
    for r in records:
        if "terrain_mesh" not in r:continue
        if any(abs(v)>1e-7 for v in r.get("rotation",[0,0,0])):continue
        t=r["terrain_mesh"];c,n=int(t["columns"]),int(t["rows"]);sx,sy,sz=r["size"];px,py,pz=r["position"]
        u=(x-px+sx/2)/sx*c;v=(z-pz+sz/2)/sz*n
        if not (0<=u<c and 0<=v<n):continue
        i,j=int(u),int(v)
        if t["holes"][j*c+i]:continue
        a,b=u-i,v-j;h=t["heights"];h00=h[j*(c+1)+i];h10=h[j*(c+1)+i+1];h11=h[(j+1)*(c+1)+i+1];h01=h[(j+1)*(c+1)+i]
        return py+sy*(h00+(h10-h00)*a+(h11-h10)*b if a>=b else h00+(h11-h01)*a+(h01-h00)*b)
    raise ValueError("No supported terrain beneath camera")

def safe_actor_anchor(eye, records, obstacles):
    # Keep the chosen camera unchanged. Actor relocation has a separate ground anchor.
    offsets=[(0.,0.)]
    for radius in [.75,1.5,2.25,3.,4.]:
        offsets.extend((radius*math.sin(math.radians(a)),radius*math.cos(math.radians(a))) for a in range(0,360,30))
    for dx,dz in offsets:
        x,z=float(eye[0]+dx),float(eye[2]+dz)
        try:height=ground(records,x,z)
        except ValueError:continue
        if not math.isfinite(height):continue
        # Entire XZ projection + 0.40 m: capsule radius ~0.35 m plus clearance.
        # Deliberately conservative even when an asset crown is above the actor.
        if any(lo[0]-.40<=x<=hi[0]+.40 and lo[2]-.40<=z<=hi[2]+.40 for lo,hi in obstacles):continue
        return [x,z]
    raise ValueError("No capsule-safe anchor near unchanged camera eye")

def choose(identifier,target,records,obstacles,min_radius,eye_height,purpose):
    for radius in [min_radius,min_radius+1.5,min_radius+3]:
        for degree in range(0,360,30):
            angle=math.radians(degree);x=target[0]+radius*math.sin(angle);z=target[2]+radius*math.cos(angle)
            try:y=ground(records,x,z)+eye_height
            except ValueError:continue
            eye=np.array([x,y,z]);blocked=False
            # Conservative actual full bounds, including tree crown; no trunk-only exemption.
            for lo,hi in obstacles:
                if np.all(eye>=lo-.25) and np.all(eye<=hi+.25):blocked=True;break
            if blocked:continue
            return {"id":identifier,"eye":eye.tolist(),"target":list(target),"anchor":safe_actor_anchor(eye,records,obstacles),"fov":55,"purpose":purpose,"camera_clearance_method":"Final native record full world AABBs; eye terrain sampled from same snapshot. Actor anchor avoids full XZ bounds plus 0.40m; runtime resolves actual ground Y. Conservative, no GPU visibility guarantee."}
    raise ValueError("No safe eye for "+identifier)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build",type=Path,default=OUT/"functional_vegetation_build.json")
    parser.add_argument("--records",type=Path,required=True)
    parser.add_argument("--cameras",type=Path,default=OUT/"functional_extra_cameras.json")
    parser.add_argument("--apply",action="store_true")
    args=parser.parse_args();build=read(args.build);snapshot=read(args.records);old=read(args.cameras)
    assert build.get("saved") and build.get("native_reopen_passed") and build.get("failures")==0,"Successful native apply receipt required"
    assert snapshot.get("map_sha256")==build["output_sha256"],"Stale native record export"
    assert digest(Path(build["map_path"]))==build["output_sha256"],"Candidate changed after vegetation build; export/rebase receipt explicitly"
    records=snapshot["records"];byid={r["uuid"]:r for r in records};obstacles=[]
    for r in records:
        if any(k in r for k in ["terrain_mesh","channel_mesh","road_mesh"]):continue
        if r.get("kind")=="asset" or r.get("building") or r.get("fortification"):
            obstacles.append(bounds(r))
    generated=[]
    for kind,identifier,height,radius in [("tree","vegetation_tree_roots",.9,6.5),("shrub","vegetation_shrub_detail",.5,2.5)]:
        choices=[p for p in build["placements"] if p["kind"]==kind]
        assert choices,"No actual "+kind+" placements"
        if kind == "tree":
            # Inspect the most uneven actual root support first, rather than
            # letting the first flat-ground instance stand in for hill trees.
            choices.sort(key=lambda p: float(p.get("basal_support", {}).get("ground_max", 0))
                         - float(p.get("basal_support", {}).get("ground_min", 0)), reverse=True)
        for placement in choices:
            r=byid[placement["ids"][0]];lo,hi=bounds(r);center=(lo+hi)/2;target=[float(center[0]),float(lo[1]+height),float(center[2])]
            try:
                camera=choose(identifier,target,records,obstacles,radius,1.7,"Actual "+kind+" roots/foliage exterior detail")
                camera["subject_ids"]=placement["ids"]
                if kind == "tree":camera["subject_basal_support"]=placement.get("basal_support", {})
                generated.append(camera);break
            except ValueError:continue
        else:raise ValueError("No safe "+kind+" camera")
    crop_hashes=("471669ea645b302b","5dde353b2492a61b")
    crops=[r for r in records if any(h in str(r.get("asset_path","")) for h in crop_hashes)]
    assert crops,"Actual native crop instances missing; export expanded scatter records, do not substitute planned field centers"
    for crop in crops:
        lo,hi=bounds(crop);center=(lo+hi)/2;target=[float(center[0]),float(lo[1]+.8),float(center[2])]
        try:camera=choose("vegetation_crop_detail",target,records,obstacles,3.,1.8,"Actual wheat stems/ears and field density");camera["subject_ids"]=[crop["uuid"]];generated.append(camera);break
        except ValueError:continue
    assert len(generated)==3,"No safe crop camera"
    retained=[c for c in old["cameras"] if c["id"] not in IDS];assert len(retained)>=6,"Original six views must exist"
    result={**old,"cameras":retained+generated,"vegetation_camera_evidence":{"build":str(args.build),"build_sha256":digest(args.build),"records":str(args.records),"records_sha256":digest(args.records),"map_sha256":build["output_sha256"],"status":"CPU camera proposal; actual Q90 viewing pending"}}
    assert len(result["cameras"])<=16
    if args.apply:
        temporary=args.cameras.with_suffix(".json.tmp");temporary.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8");os.replace(temporary,args.cameras)
    print(json.dumps({"applied":args.apply,"added":generated,"preserved_camera_ids":[c["id"] for c in retained]},ensure_ascii=False,indent=2))

if __name__=="__main__":main()
