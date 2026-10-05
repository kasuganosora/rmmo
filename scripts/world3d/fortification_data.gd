extends RefCounted
const W=preload("res://scripts/world3d/waterway_data.gd")
const S=preload("res://scripts/world3d/document_schema.gd")
static func gate_schema(min_height:=3.0) -> Dictionary:
	return W.obj({"id":W.text(),"segment":S.number(0,127,true),"t":S.number(0,1),"angle":S.number(0,359.999),"kind":{"type":"string","enum":["land","water"]},"width":S.number(3,64),"height":S.number(min_height,9),"open":S.number(0,1)},["id","width","height","open"])
static func settings_schema() -> Dictionary:
	return W.obj({"id":W.text(),"name":W.text(120),"points":W.arr(W.arr(S.number(-10000,10000),2,2),128),"tower_indices":W.arr(S.number(0,127,true),128),"shape":{"type":"string","enum":["path","ellipse"]},"center_x":S.number(-10000,10000),"center_z":S.number(-10000,10000),"radius_x":S.number(15,200),"radius_z":S.number(15,200),"rotation":S.number(-180,180),"tower_count":S.number(0,24,true),"tower_spacing":S.number(50,120),"tower_layout":{"type":"string","enum":["automatic","manual"]},"layout_version":S.number(0,1,true),"closed":{"type":"boolean"},"base_height":S.number(-1000,1000),"height":S.number(4,12),"thickness":S.number(1.5,4),"terrain_foundation":{"type":"boolean"},"foundation":S.number(.5,3),"corner_towers":{"type":"boolean"},"battlements":{"type":"boolean"},"arrow_slits":{"type":"boolean"},"wall_access":{"type":"boolean"},"tower_door_open":S.number(0,1),"interior_side":{"type":"string","enum":["left","right"]},"style":{"type":"string","enum":["plain","medieval_stone"]},"floor_material_id":W.text(256),"trim_material_id":W.text(256),"stone_material_id":W.text(256),"door_material_id":W.text(256),"gates":W.arr(gate_schema(),16)})
static func defaults() -> Dictionary:
	return {"name":"城墙","points":[],"shape":"path","center_x":0.0,"center_z":0.0,"radius_x":40.0,"radius_z":40.0,"rotation":0.0,"tower_count":8,"tower_spacing":60.0,"tower_layout":"manual","layout_version":0,"closed":false,"base_height":0.0,"height":6.0,"thickness":2.5,"terrain_foundation":false,"foundation":1.0,"corner_towers":true,"battlements":true,"arrow_slits":false,"wall_access":false,"tower_door_open":1.0,"interior_side":"left","style":"plain","floor_material_id":"","trim_material_id":"","stone_material_id":"","door_material_id":"","gates":[]}

static func required_settings() -> Array:
	# Existing path recipes remain valid; ring-specific fields were added later.
	return ["id","name","points","closed","base_height","height","thickness","foundation","corner_towers","battlements","stone_material_id","door_material_id","gates"]
static func request_schema() -> Dictionary:
	var schema:=settings_schema(); schema.properties.gates=W.arr(gate_schema(5.0),16); schema.properties.erase("layout_version"); schema.properties.plan_token=W.text(64); schema.required=["id"]; return schema
static func valid_settings(value: Dictionary) -> bool:
	var schema:=settings_schema(); schema.required=required_settings()
	if not S.validate(value,schema).is_empty() or value.id.is_empty() or not value.id.is_valid_identifier(): return false
	if value.get("wall_access",false) and (not value.corner_towers or value.thickness<3.2 or value.height<7.5 or value.get("style","plain")!="medieval_stone"): return false
	if value.get("arrow_slits",false) and value.get("style","plain")!="medieval_stone": return false
	var ring: bool=value.get("shape","path")=="ellipse"
	if not ring and (value.points.size()<2 or value.closed and value.points.size()<3): return false
	if value.has("tower_indices"):
		if ring: return false
		var seen:={}
		for index in value.tower_indices:
			if index>=value.points.size() or seen.has(index): return false
			seen[index]=true
	var ids:={}
	for gate in value.gates:
		if value.get("style","plain")=="medieval_stone" and gate.height<5.0: return false
		if gate.get("kind","land")=="land" and gate.width>32: return false
		if gate.get("kind","land")=="water" and ring: return false
		if gate.id.is_empty() or not gate.id.is_valid_identifier() or ids.has(gate.id) or gate.height>value.height-.5: return false
		if ring:
			if not gate.has("angle") or gate.has("segment") or gate.has("t"): return false
		elif not gate.has("segment") or not gate.has("t") or gate.has("angle") or gate.segment>=value.points.size()-(0 if value.closed else 1): return false
		ids[gate.id]=true
	return true
static func manifest_schema() -> Dictionary:
	var schema:=settings_schema(); schema.required=required_settings()
	return W.arr(W.obj({"version":S.number(1,1,true),"baked":{"type":"boolean"},"source_part_count":S.number(1,100000,true),"settings":schema,"parts":W.arr(W.obj({"id":W.text(100),"signature":W.text(64)},["id","signature"]),8192,1)},["version","settings","parts"]),64)
static func valid(regions: Array) -> bool:
	if not S.validate(regions,manifest_schema()).is_empty(): return false
	var ids:={}; var members:={}
	for region in regions:
		if not valid_settings(region.settings) or ids.has(region.settings.id): return false
		ids[region.settings.id]=true
		for part in region.parts:
			if part.id.is_empty() or members.has(part.id) or part.signature.length()!=64: return false
			members[part.id]=true
	return true
static func valid_record(r: Dictionary) -> bool:
	if r.has("fortification_art"):
		var schema:=W.obj({"version":S.number(1,1,true),"module":{"type":"string","enum":["wall","parapet","battlement","gate_lintel","door","round_tower","corner_tower","joint","hinge","hinge_mount","embrasure","tower_stair"]},"asset_path":W.text(2048)},["version","module","asset_path"])
		if r.get("kind")!="box" or not S.validate(r.fortification_art,schema).is_empty(): return false
		if not preload("res://scripts/world3d/map_paths.gd").allowed(r.fortification_art.asset_path): return false
	if not r.has("fortification"): return true
	return r.get("kind")=="box" and not r.has("building") and S.validate(r.fortification,W.obj({"id":W.text(80),"part":W.text(100),"role":W.text(40)},["id","part","role"])).is_empty()
