extends SceneTree
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const S=preload("res://scripts/world3d/document_schema.gd")
var failed:=0
func _initialize()->void:call_deferred("run")
# Frozen pre-optimization validator: compare semantic boundaries, not internals.
func reference(record:Dictionary)->bool:
	if not record.has("terrain_mesh"):return not record.has("terrain_material")
	if not record.get("kind") is String or record.kind!="box":return false
	for key in ["tile3d","building","building_shape","fixture","road_mesh","channel_mesh","road_source","fortification","waterway"]:
		if record.has(key):return false
	var schema:={"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"columns":S.number(2,64,true),"rows":S.number(2,64,true),"floor":S.number(-100,-1),"heights":{"type":"array","minItems":9,"maxItems":4225,"items":S.number(-100,1000)},"holes":{"type":"array","minItems":4,"maxItems":4096,"items":{"type":"boolean"}}},"required":["version","columns","rows","floor","heights","holes"]}
	if not S.validate(record.terrain_mesh,schema).is_empty() or not S.validate(record.get("size"),S.vector(.01,100000)).is_empty():return false
	var t:Dictionary=record.terrain_mesh
	if t.heights.size()!=(int(t.columns)+1)*(int(t.rows)+1) or t.holes.size()!=int(t.columns)*int(t.rows):return false
	for height in t.heights:
		if height<t.floor+.1:return false
	return t.holes.has(false)
func run()->void:
	var base:={"kind":"box","size":[4,1,4],"terrain_mesh":{"version":1,"columns":2,"rows":2,"floor":-4.,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}}
	var cases:Array=[{}, {"terrain_material":{}},base];var values:Array=[null,true,false,"bad",{},[],0,1,1.0,1.5,2,2.5,64,65,-100,-1,NAN,INF]
	for field in ["version","columns","rows","floor","heights","holes"]:
		var removed:Dictionary=base.duplicate(true);removed.terrain_mesh.erase(field);cases.append(removed)
		for value in values:
			var r:Dictionary=base.duplicate(true);r.terrain_mesh[field]=value;cases.append(r)
	for field in ["kind","size","terrain_mesh"]:
		for value in values:
			var r:Dictionary=base.duplicate(true);r[field]=value;cases.append(r)
	for field in ["tile3d","building","building_shape","fixture","road_mesh","channel_mesh","road_source","fortification","waterway"]:
		var r:Dictionary=base.duplicate(true);r[field]={};cases.append(r)
	for value in values+[-4.,-3.900001,-3.9,1000.,1000.0001]:
		for field in ["heights","holes"]:
			var r:Dictionary=base.duplicate(true);r.terrain_mesh[field][-1]=value;cases.append(r)
	for value in [.0099,.01,100000.,100000.1,NAN,INF,false,"bad"]:
		var r:Dictionary=base.duplicate(true);r.size[2]=value;cases.append(r)
	var extra:Dictionary=base.duplicate(true);extra.terrain_mesh.unexpected=true;cases.append(extra)
	var empty:Dictionary=base.duplicate(true);empty.terrain_mesh.holes.fill(true);cases.append(empty)
	for r:Dictionary in cases:
		if Terrain.valid(r)!=reference(r):failed+=1;push_error("terrain validator mismatch: "+str(r))
	var Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf";var metadata:=Cache.read(path,FileAccess.get_sha256(path))
	var old_us:=0;var new_us:=0;var count:=0
	for r:Dictionary in metadata.rmmo_records:
		if not r.has("terrain_mesh"):continue
		var start:=Time.get_ticks_usec();var expected:=reference(r);old_us+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var actual:=Terrain.valid(r);new_us+=Time.get_ticks_usec()-start;count+=1
		if actual!=expected:failed+=1
	print("TERRAIN_VALIDATION ",JSON.stringify({"failures":failed,"boundaries":cases.size(),"town_patches":count,"old_us":old_us,"new_us":new_us}));quit(1 if failed else 0)
