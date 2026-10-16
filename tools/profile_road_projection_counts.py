"""Create a counted copy of the candidate, leaving production probes off."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "review_artifacts/road_projection_20261017"
RES = "res://review_artifacts/road_projection_20261017/"


def main():
    source = (ROOT / "scripts/world3d/terrain_projection.gd").read_text(encoding="utf-8")
    source = source.replace("static func fit(", "static func _fit(")
    for row, column in [("upper", "column"), ("upper", "column+1"), ("lower", "column"), ("lower", "column+1")]:
        prefix = f"\t\t\t\tif {row}[{column}]==null:"
        lines = source.splitlines()
        source = "\n".join(line + ';add("world_points",1)' if line.startswith(prefix) else line for line in lines) + "\n"
    source = source.replace('\t\t\t\tvar column:=', '\t\t\t\tadd("cells",1);add("triangles",2)\n\t\t\t\tvar column:=')
    source = source.replace('if sampled_heights.has(world):y=sampled_heights[world]', 'if sampled_heights.has(world):y=sampled_heights[world];add("kerb_cache_hits",1)')
    source = source.replace('\t\t\t\t\tfor index in terrains.size():', '\t\t\t\t\tif sampled_heights.size()>=KERB_SAMPLE_CACHE_LIMIT:add("uncached_after_cap",1)\n\t\t\t\t\tfor index in terrains.size():\n\t\t\t\t\t\tadd("kerb_samples",1)')
    source = source.replace('sampled_heights[world]=y', 'sampled_heights[world]=y;trace.cache_peak=maxi(trace.get("cache_peak",0),sampled_heights.size())')
    source += '''
static var trace:Dictionary={}
static func add(key:String,value:int)->void:
	trace[key]=int(trace.get(key,0))+value
static func fit(record:Dictionary,terrains:Array,offset:float=.025,max_grade:float=.15)->Dictionary:
	add("fit_calls",1)
	return _fit(record,terrains,offset,max_grade)
'''
    (DEST / "terrain_projection_counted.gd").write_text(source, encoding="utf-8", newline="\n")
    for name, target in [("road_terrain_fit", "terrain_projection"), ("road_tools", "road_terrain_fit")]:
        value = (DEST / (name + "_ref.gd")).read_text(encoding="utf-8")
        value = value.replace(RES + target + "_ref.gd", RES + target + "_counted.gd")
        (DEST / (name + "_counted.gd")).write_text(value, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
