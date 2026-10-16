extends RefCounted
## Persist authoring deltas, not another rendered terrain. Unrelated sculpting
## survives a river reroute; edits to owned samples are explicit conflicts.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const W=preload("res://scripts/world3d/waterway_data.gd")
const APPEARANCE_FIELDS=["terrain_depth_blend","terrain_slope_blend"]
static func request_schema()->Dictionary:
	return W.obj({"id":W.text(80),"terrain_ids":W.arr(W.text(128),64,1),"points":W.arr(W.arr(T.S.number(-10000,10000),2,2),128,2),"width":T.S.number(3,60),"bank_width":T.S.number(1,20),"water_level":T.S.number(-1000,1000),"water_levels":W.arr(T.S.number(-1000,1000),128,2),"outlet":W.obj({"river_id":W.text(80),"endpoint":{"type":"string","enum":["end"]}},["river_id"]),"depth":T.S.number(.5,12),"curved":{"type":"boolean"},"natural_materials":{"type":"boolean"}},["id","terrain_ids","points","water_level"])

static func snapshots_valid(before:Dictionary,after:Dictionary)->bool:
	for record:Dictionary in [before,after]:
		if not record.get("uuid") is String or record.uuid.is_empty() or record.uuid.length()>128 or not record.has("terrain_mesh"):return false
		for field:String in ["position","rotation"]:
			if not T.S.validate(record.get(field),T.S.vector(-100000,100000)).is_empty():return false
		if not T.valid(record) or not T.Paint.valid(record):return false
	# A river changes heights and the two optional river/slope materials only.
	# Persisted snapshots must never be allowed to rewrite identity, transforms,
	# grid shape, holes, protection flags or unrelated authoring metadata.
	var a:=before.duplicate();var b:=after.duplicate()
	for key:String in ["terrain_mesh"]+APPEARANCE_FIELDS:a.erase(key);b.erase(key)
	if not same(a,b):return false
	a=before.terrain_mesh.duplicate();b=after.terrain_mesh.duplicate()
	a.erase("heights");b.erase("heights")
	return same(a,b)

static func restore(current:Dictionary,before:Dictionary,after:Dictionary)->Dictionary:
	if not snapshots_valid(before,after) or not T.valid(current) or current.get("uuid")!=after.uuid:return T.fail("河道恢复图层的地形快照无效")
	var next:=current.duplicate(true)
	for key:String in ["position","rotation","size"]:
		if not same(current.get(key),after.get(key)):return T.fail("河道地形的变换已改变，请先恢复变换")
	for key:String in ["columns","rows","floor","version"]:
		if current.terrain_mesh.get(key)!=after.terrain_mesh.get(key):return T.fail("河道地形网格已改变")
	for field:String in ["heights","holes"]:
		for i in before.terrain_mesh[field].size():
			if same(before.terrain_mesh[field][i],after.terrain_mesh[field][i]):continue
			if not same(current.terrain_mesh[field][i],after.terrain_mesh[field][i]):return T.fail("河道控制的地形采样已手改或被另一河道使用，请先撤销该冲突修改")
			next.terrain_mesh[field][i]=before.terrain_mesh[field][i]
	var keys:Array=before.keys()
	for key in after:
		if key not in keys:keys.append(key)
	for key in keys:
		if key=="terrain_mesh" or same(before.get(key),after.get(key)):continue
		if not same(current.get(key),after.get(key)):return T.fail("河道控制的材质或属性已手改："+str(key))
		if before.has(key):next[key]=before[key].duplicate(true) if before[key] is Dictionary or before[key] is Array else before[key]
		else:next.erase(key)
	return {"ok":true,"record":next}

static func same(a:Variant,b:Variant)->bool:
	# JSON metadata uses doubles while native records retain their numeric types.
	if (a is float or a is int) and (b is float or b is int):return absf(float(a)-float(b))<.00000001
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	return a==b

static func valid(meta:Dictionary)->bool:
	var layers:Variant=meta.get("terrain_rivers",[])
	if not layers is Array or layers.size()>64:return false
	var ids:Dictionary={}
	for layer:Variant in layers:
		if not layer is Dictionary or layer.get("version")!=1 or not layer.get("id") is String or ids.has(layer.id):return false
		ids[layer.id]=true
		if not layer.id.is_valid_identifier() or layer.id.length()>80:return false
		if not layer.get("request") is Dictionary or not T.S.validate(layer.request,request_schema()).is_empty() or layer.request.id!=layer.id:return false
		if not preload("res://scripts/world3d/terrain_river_profile.gd").validate(layer.request).is_empty():return false
		var seeds:Dictionary={}
		for id:String in layer.request.terrain_ids:
			if id.is_empty() or seeds.has(id):return false
			seeds[id]=true
		if not layer.get("terrains") is Array or layer.terrains.is_empty() or layer.terrains.size()>64 or not layer.get("water") is Array or layer.water.is_empty() or layer.water.size()>4096:return false
		var terrain_ids:Dictionary={}
		for item:Variant in layer.terrains:
			if not item is Dictionary or not item.get("before") is Dictionary or not item.get("after") is Dictionary:return false
			if not snapshots_valid(item.before,item.after) or terrain_ids.has(item.after.uuid):return false
			terrain_ids[item.after.uuid]=true
		var water_ids:Dictionary={}
		for water:Variant in layer.water:
			if not water is Dictionary or not water.get("id") is String or not water.id.begins_with("river_"+layer.id+"_") or not water.get("signature") is String or water.signature.length()!=64 or not water.signature.is_valid_hex_number(false) or water_ids.has(water.id):return false
			water_ids[water.id]=true
	return preload("res://scripts/world3d/terrain_river_outlet.gd").valid_links(meta)

static func snapshot_records(meta:Dictionary)->Array:
	# Callers validate metadata before using this dependency list. References
	# suffice: discovery never mutates authoring snapshots or copies height grids.
	var records:Array=[]
	for layer:Dictionary in meta.get("terrain_rivers",[]):
		for item:Dictionary in layer.terrains:records.append(item.before);records.append(item.after)
	return records
