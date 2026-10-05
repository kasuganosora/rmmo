extends RefCounted
## Authored geometry, not a disposable runtime cache. Source recipes are provenance.
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")

static func fortification(records:Array)->Dictionary:
	if records.is_empty():return Data.fail("没有城防构件")
	var prepared:Array=[];var groups:Dictionary={};var centers:Dictionary={}
	var owner:String=records[0].fortification.id
	for source:Dictionary in records:
		if source.get("prefab_locked",false):return Data.fail("城防已经是固定预制件")
		if source.get("fortification",{}).get("id","")!=owner:return Data.fail("城防身份不一致")
		var r:=source.duplicate(true);var p:=Frozen.vec(r.position)
		# Spatial render groups do not change world streaming cells. Keep towers'
		# semantic centers for automatic layout, and every hinge as a separate leaf.
		var tower:bool=r.fortification.role in ["tower_stair","corner_tower"]
		var key:=str([floori(p.x/32),floori(p.z/32),r.get("collision","block"),r.get("fixture",{}).get("id",""),r.get("fixture",{}).get("angle",0),r.uuid if tower else ""])
		if not groups.has(key):groups[key]=groups.size()
		var group:int=groups[key]
		if tower:centers[group]=[p.x,p.z]
		r.building={"id":owner,"part":"main/structure","role":"shell","floor":group,"floor_y":0.0}
		prepared.append(r)
	var baked:=Frozen.bake(prepared)
	if not baked.ok:return baked
	for r:Dictionary in baked.records:
		var group:int=r.building.floor;r.erase("building")
		r.uuid="fort_"+owner.sha256_text().left(16)+"_baked_"+str(group)
		r.fortification={"id":owner,"part":"baked_"+str(group),"role":"prefab"}
		r.editor_group=owner
		if centers.has(group):r.prefab_tower_center=centers[group]
	return baked

static func bridge(source:Dictionary)->Dictionary:
	if source.has("house_prefab"):return Data.fail("桥梁已经是固定预制件")
	if not preload("res://scripts/world3d/bridge_data.gd").valid(source) or not source.has("bridge_mesh"):return Data.fail("桥梁数据无效")
	for role in ["deck","masonry","trim"]:
		if not source.get("bridge_materials",{}).has(role):return Data.fail("桥梁材质缺失："+role)
	if source.has("event") or source.has("event_template") or source.has("surface_paint"):return Data.fail("含手工刷面或事件的桥梁不能自动烘焙")
	var mesh:Mesh=preload("res://scripts/world3d/bridge_mesh.gd").new().build(source)
	if mesh==null:return Data.fail("桥梁模型无法生成")
	var cpu:Mesh=Frozen.Cpu.capture(mesh)
	var cache:Dictionary={};cache[[0]]={"mesh":cpu,"source":cpu}
	var data:=Frozen.Cook.pack(cache,"","bridge_prefab_v1")
	if data.entries.size()!=1:return Data.fail("桥梁材质不能序列化")
	Frozen.compact_data(data)
	var bytes:=var_to_bytes(data)
	var r:=source.duplicate(true)
	r.house_prefab={"version":1,"sha256":Frozen.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	r.prefab_locked=true;r.prefab_materials=[]
	for material:Dictionary in data.materials:
		if material.has("paint") and not r.prefab_materials.has(material.paint):r.prefab_materials.append(material.paint)
	return {"ok":true,"record":r,"component_count":1}

static func refresh_bindings(metadata:Dictionary,records:Array)->void:
	var layout:Dictionary=metadata.get("editor_layout",{});var indexed:Dictionary={}
	for r:Dictionary in records:indexed[r.uuid]=r
	for edge:Dictionary in layout.get("roads",{}).get("edges",[]):
		if edge.has("stone_bridge") and indexed.has(edge.stone_bridge.id):edge.stone_bridge.signature=Data.token(indexed[edge.stone_bridge.id])
	for region:Dictionary in layout.get("waterways",[]):
		for part:Dictionary in region.parts:
			if indexed.has(part.id) and indexed[part.id].has("bridge_mesh"):part.signature=Data.token(indexed[part.id])
	if layout.has("road_surface"):layout.road_surface.graph_token=Data.token(layout.roads)
