"""Freeze the current projection chain and add diagnostic-only phase probes."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "review_artifacts/road_projection_20261017"
RES = "res://review_artifacts/road_projection_20261017/"


def main():
    DEST.mkdir(exist_ok=False)
    sources = {
        "terrain_projection": "scripts/world3d/terrain_projection.gd",
        "road_terrain_fit": "scripts/world3d/road_terrain_fit.gd",
        "road_tools": "scripts/world_editor/road_tools.gd",
    }
    manifest = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "files": {}}
    for name, path in sources.items():
        raw = (ROOT / path).read_bytes()
        (DEST / (name + ".gd.txt")).write_bytes(raw)
        source = raw.decode().replace("\r\n", "\n")
        for mode in ["ref", "profile"]:
            value = source
            if name == "road_tools":
                value = value.replace("res://scripts/world3d/road_terrain_fit.gd", RES + "road_terrain_fit_" + mode + ".gd")
            elif name == "road_terrain_fit":
                value = value.replace("res://scripts/world3d/terrain_projection.gd", RES + "terrain_projection_" + mode + ".gd")
            elif mode == "profile":
                value = value.replace("static func fit(", "static func _fit(")
                value += '''
static var trace:Dictionary={}
static func add(key:String,value:float)->void:
	trace[key]=float(trace.get(key,0.))+value
static func fit(record:Dictionary,terrains:Array,offset:float=.025,max_grade:float=.15)->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:=_fit(record,terrains,offset,max_grade)
	add("fit_calls",1);add("fit_us",Time.get_ticks_usec()-started)
	if result.get("code","")=="terrain_projection_piece_limit":add("budget_retries",1)
	return result
'''
                value = value.replace("\t\t\t\tvar cell:=T.cell(terrain,x,z)", "\t\t\t\tvar tick:=Time.get_ticks_usec()\n\t\t\t\tvar cell:=T.cell(terrain,x,z)\n\t\t\t\tadd(\"cell_us\",Time.get_ticks_usec()-tick);add(\"cells\",1)")
                value = value.replace("\t\t\t\t\tvar triangle:Array=", "\t\t\t\t\ttick=Time.get_ticks_usec()\n\t\t\t\t\tvar triangle:Array=")
                value = value.replace("\n\t\t\t\t\tif not triangle_bounds", "\n\t\t\t\t\tadd(\"triangle_setup_us\",Time.get_ticks_usec()-tick);add(\"triangles\",1)\n\t\t\t\t\tif not triangle_bounds")
                value = value.replace("\t\t\t\t\t\tvar overlap:=P.intersection(polygon,boundary)", "\t\t\t\t\t\ttick=Time.get_ticks_usec()\n\t\t\t\t\t\tvar overlap:=P.intersection(polygon,boundary)\n\t\t\t\t\t\tadd(\"clip_us\",Time.get_ticks_usec()-tick);add(\"clips\",1)")
                value = value.replace("\t\t\t\t\t\tvar raw:Array=[]", "\t\t\t\t\t\ttick=Time.get_ticks_usec()\n\t\t\t\t\t\tvar raw:Array=[]")
                value = value.replace("\t\t\t\t\t\tif output.size()", "\t\t\t\t\t\tadd(\"output_us\",Time.get_ticks_usec()-tick);add(\"overlaps\",1)\n\t\t\t\t\t\tif output.size()")
                value = value.replace('\tfor kerb:Dictionary in next[field]', '\tvar kerb_started:=Time.get_ticks_usec()\n\tfor kerb:Dictionary in next[field]')
                value = value.replace("\t\t\t\tfor terrain:Dictionary in terrains:", "\t\t\t\tfor terrain:Dictionary in terrains:\n\t\t\t\t\tadd(\"kerb_samples\",1)")
                value = value.replace('\tnext.terrain_follow=', '\tadd("kerb_us",Time.get_ticks_usec()-kerb_started)\n\tnext.terrain_follow=')
            (DEST / (name + "_" + mode + ".gd")).write_text(value, encoding="utf-8", newline="\n")
    for path in sorted(DEST.iterdir()):
        manifest["files"][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    (DEST / "reference.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
