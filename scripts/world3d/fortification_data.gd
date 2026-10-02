extends RefCounted
const W=preload("res://scripts/world3d/waterway_data.gd")
const S=preload("res://scripts/world3d/document_schema.gd")
static func gate_schema() -> Dictionary:
	return W.obj({"id":W.text(),"segment":S.number(0,31,true),"t":S.number(0,1),"angle":S.number(0,359.999),"width":S.number(3,10),"height":S.number(3,9),"open":S.number(0,1)},["id","width","height","open"])
static func settings_schema() -> Dictionary:
	return W.obj({"id":W.text(),"name":W.text(120),"points":W.arr(W.arr(S.number(-10000,10000),2,2),32),"shape":{"type":"string","enum":["path","ellipse"]},"center_x":S.number(-10000,10000),"center_z":S.number(-10000,10000),"radius_x":S.number(15,200),"radius_z":S.number(15,200),"rotation":S.number(-180,180),"tower_count":S.number(4,24,true),"closed":{"type":"boolean"},"base_height":S.number(-1000,1000),"height":S.number(4,12),"thickness":S.number(1.5,4),"foundation":S.number(.5,3),"corner_towers":{"type":"boolean"},"battlements":{"type":"boolean"},"stone_material_id":W.text(256),"door_material_id":W.text(256),"gates":W.arr(gate_schema(),16)})
static func defaults() -> Dictionary:
	return {"name":"城墙","points":[],"shape":"path","center_x":0.0,"center_z":0.0,"radius_x":40.0,"radius_z":40.0,"rotation":0.0,"tower_count":8,"closed":false,"base_height":0.0,"height":6.0,"thickness":2.5,"foundation":1.0,"corner_towers":true,"battlements":true,"stone_material_id":"","door_material_id":"","gates":[]}

static func required_settings() -> Array:
	# Existing path recipes remain valid; ring-specific fields were added later.
	return ["id","name","points","closed","base_height","height","thickness","foundation","corner_towers","battlements","stone_material_id","door_material_id","gates"]
static func request_schema() -> Dictionary:
	var schema:=settings_schema(); schema.properties.plan_token=W.text(64); schema.required=["id"]; return schema
static func valid_settings(value: Dictionary) -> bool:
	var schema:=settings_schema(); schema.required=required_settings()
	if not S.validate(value,schema).is_empty() or value.id.is_empty() or not value.id.is_valid_identifier(): return false
	var ring: bool=value.get("shape","path")=="ellipse"
	if not ring and (value.points.size()<2 or value.closed and value.points.size()<3): return false
	var ids:={}
	for gate in value.gates:
		if gate.id.is_empty() or not gate.id.is_valid_identifier() or ids.has(gate.id) or gate.height>value.height-.5: return false
		if ring:
			if not gate.has("angle") or gate.has("segment") or gate.has("t"): return false
		elif not gate.has("segment") or not gate.has("t") or gate.has("angle") or gate.segment>=value.points.size()-(0 if value.closed else 1): return false
		ids[gate.id]=true
	return true
static func manifest_schema() -> Dictionary:
	var schema:=settings_schema(); schema.required=required_settings()
	return W.arr(W.obj({"version":S.number(1,1,true),"settings":schema,"parts":W.arr(W.obj({"id":W.text(100),"signature":W.text(64)},["id","signature"]),4096,1)},["version","settings","parts"]),64)
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
	if not r.has("fortification"): return true
	return r.get("kind")=="box" and not r.has("building") and S.validate(r.fortification,W.obj({"id":W.text(80),"part":W.text(100),"role":W.text(40)},["id","part","role"])).is_empty()
