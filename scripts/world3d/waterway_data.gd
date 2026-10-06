extends RefCounted
const S=preload("res://scripts/world3d/document_schema.gd")
static func obj(p: Dictionary,r: Array=[]) -> Dictionary: return {"type":"object","properties":p,"required":r,"additionalProperties":false}
static func text(n:=80) -> Dictionary: return {"type":"string","maxLength":n}
static func arr(item: Dictionary,n: int,minimum:=0) -> Dictionary: return {"type":"array","items":item,"maxItems":n,"minItems":minimum}
static func bridge_schema() -> Dictionary:
	return obj({"id":text(),"segment":S.number(0,30,true),"t":S.number(0,1),"width":S.number(3,12),"approach":S.number(1,12),"rail_height":S.number(.9,1.5),"prefab_id":{"type":"string","enum":["legacy_flat","stone_segmental","stone_pointed","stone_rustic"]},"camber":S.number(0,5)},["id","segment","t","width","approach","rail_height"])
static func settings_schema() -> Dictionary:
	return obj({"id":text(),"name":text(120),"points":arr(arr(S.number(-10000,10000),2,2),32,2),"ground_ids":arr(text(100),32,1),"width":S.number(3,60),"bank_width":S.number(.5,8),"bank_height":S.number(-1000,1000),"water_drop":S.number(.5,5),"depth":S.number(.5,10),"bank_material_id":text(256),"bed_material_id":text(256),"bridge_material_id":text(256),"bridges":arr(bridge_schema(),16)})
static func request_schema() -> Dictionary:
	var value:=settings_schema(); value.properties.plan_token=text(64); value.required=["id"]; return value
static func defaults() -> Dictionary:
	return {"name":"城镇河道","width":12.0,"bank_width":2.0,"bank_height":0.0,"water_drop":1.2,"depth":1.5,"bank_material_id":"","bed_material_id":"","bridge_material_id":"","bridges":[]}
static func ground_schema() -> Dictionary:
	return obj({"uuid":text(100),"kind":{"type":"string","enum":["box"]},"surface_id":{"type":"string","enum":["ground","grass","dirt","stone","sand"]},"position":S.vector(-100000,100000),"rotation":S.vector(-360,360),"size":S.vector(.001,10000),"color":arr(S.number(0,1),3,3),"collision":{"type":"string","enum":["walk","block"]},"editor_name":text(2048)},["uuid","kind","surface_id","position","rotation","size"])
static func manifest_schema() -> Dictionary:
	var setting:=settings_schema(); setting.required=setting.properties.keys()
	return arr(obj({"version":S.number(1,1,true),"settings":setting,"sources":arr(ground_schema(),32,1),"parts":arr(obj({"id":text(100),"role":text(32),"signature":text(64)},["id","role","signature"]),2048,1)},["version","settings","sources","parts"]),32)
static func valid_settings(s: Dictionary) -> bool:
	var schema:=settings_schema(); schema.required=schema.properties.keys()
	if not S.validate(s,schema).is_empty() or s.id.is_empty() or not s.id.is_valid_identifier(): return false
	var seen:={}
	for id in s.ground_ids:
		if id.is_empty() or seen.has(id): return false
		seen[id]=true
	seen.clear()
	for b in s.bridges:
		if b.id.is_empty() or not b.id.is_valid_identifier() or seen.has(b.id) or b.segment>=s.points.size()-1: return false
		if b.get("prefab_id","legacy_flat")=="legacy_flat" and b.get("camber",0)!=0: return false
		seen[b.id]=true
	return true
static func valid(regions: Array) -> bool:
	if not S.validate(regions,manifest_schema()).is_empty(): return false
	var ids:={}; var members:={}; var sources:={}
	for region in regions:
		if not valid_settings(region.settings) or ids.has(region.settings.id): return false
		ids[region.settings.id]=true
		if region.sources.size()!=region.settings.ground_ids.size(): return false
		for source in region.sources:
			if source.uuid not in region.settings.ground_ids or sources.has(source.uuid) or not ground_valid(source,region.settings.bank_height): return false
			sources[source.uuid]=true
		for part in region.parts:
			if part.id.is_empty() or members.has(part.id) or part.signature.length()!=64: return false
			members[part.id]=true
	return true
static func ground_valid(r: Dictionary,y: float) -> bool:
	return S.validate(r,ground_schema()).is_empty() and r.size[0]<=1000 and r.size[2]<=1000 and absf(r.rotation[0])+absf(r.rotation[2])<.0001 and absf(r.position[1]+r.size[1]*.5-y)<.005
