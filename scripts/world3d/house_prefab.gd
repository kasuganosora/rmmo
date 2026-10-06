extends RefCounted
## Frozen render/collision groups, stored as plain data in the native document.
## No source pieces or generator calls are required when an instance is loaded.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Merge=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
static var _meshes:Dictionary={}
static var _render_meshes:Dictionary={}
static var _decoded:Dictionary={}
static var _decoded_bytes:=0
static var _decode_mutex:=Mutex.new()
const DECODE_BUDGET=536870912

static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func arr(v:Vector3)->Array:return [v.x,v.y,v.z]

static func decode(value:Dictionary)->Dictionary:
	if value.get("version")!=1 or not value.get("data") is String or not value.get("sha256") is String:return {}
	var length:int=int(value.get("length",0))
	if length<=0 or length>16777216 or value.data.length()>24000000:return {}
	_decode_mutex.lock()
	if _decoded.has(value.sha256) and _decoded[value.sha256].encoded==value.data and _decoded[value.sha256].length==length:
		var cached:Dictionary=_decoded[value.sha256].data
		_decode_mutex.unlock();return cached
	_decode_mutex.unlock()
	var compressed:=Marshalls.base64_to_raw(value.data)
	var bytes:=compressed.decompress(length,FileAccess.COMPRESSION_ZSTD)
	if bytes.size()!=length or Cook.Envelope.checksum(bytes).hex_encode()!=value.sha256:return {}
	var data:Variant=bytes_to_var(bytes)
	if not data is Dictionary or not Cook.valid_data(data) or data.entries.size()!=1:return {}
	# Compute immutable geometry identities beside decompression, before any
	# render resources exist. Keep these derived keys out of serialized data.
	var geometry_keys:Array=[]
	for mesh:Dictionary in data.meshes:geometry_keys.append(Cook.Envelope.checksum(var_to_bytes(mesh.surfaces)).hex_encode())
	_decode_mutex.lock()
	if _decoded.has(value.sha256):_decoded_bytes-=_decoded[value.sha256].length;_decoded.erase(value.sha256)
	while not _decoded.is_empty() and _decoded_bytes+length>DECODE_BUDGET:
		var oldest:String=_decoded.keys()[0];_decoded_bytes-=_decoded[oldest].length;_decoded.erase(oldest)
	_decoded[value.sha256]={"encoded":value.data,"length":length,"data":data,"geometry_keys":geometry_keys};_decoded_bytes+=length
	_decode_mutex.unlock()
	return data

static func valid(record:Dictionary)->bool:
	if not record.has("house_prefab"):return true
	var owner:bool=record.has("building") or record.has("fortification") or record.has("bridge_mesh")
	if record.get("kind") not in ["box","asset"] or not record.house_prefab is Dictionary or not owner or record.get("prefab_locked")!=true or record.has("building_shape") or record.has("surface_paint"):return false
	var data:=decode(record.house_prefab)
	if data.is_empty():return false
	# Texture dependencies remain visible to native validation, packs and prefetch.
	var paints:Array=[]
	for material:Dictionary in data.materials:
		if material.has("paint") and not paints.has(material.paint):paints.append(material.paint)
	return record.get("prefab_materials",[])==paints

static func geometry(record:Dictionary,paint_validation:Variant=null,material_pool:Variant=null)->Dictionary:
	var key:String=record.house_prefab.sha256
	if _meshes.has(key):return _meshes[key]
	var data:=decode(record.house_prefab)
	if data.is_empty():return {}
	var restored:=Cook.restore(data.duplicate(),paint_validation,material_pool)
	if restored.is_empty():return {}
	var entry:Dictionary=restored.values()[0]
	_decode_mutex.lock()
	var geometry_keys:Array=_decoded.get(key,{}).get("geometry_keys",[])
	_decode_mutex.unlock()
	if geometry_keys.size()==data.meshes.size():
		entry.mesh.set_meta("static_batch_geometry_signature",geometry_keys[data.entries[0][1][0]])
		entry.source.set_meta("static_batch_geometry_signature",geometry_keys[data.entries[0][1][1]])
	var identity:Array=[]
	for material:Material in entry.mesh.materials:identity.append(Cook.material_data(material))
	var render_key:String=entry.mesh.geometry_key()+var_to_str(identity).sha256_text()
	if _render_meshes.has(render_key):entry.mesh=_render_meshes[render_key]
	else:
		if _render_meshes.size()>=512:_render_meshes.erase(_render_meshes.keys()[0])
		_render_meshes[render_key]=entry.mesh
	# Bounded resource cache; live instances retain their own shared references.
	if _meshes.size()>=512:_meshes.erase(_meshes.keys()[0])
	_meshes[key]=entry
	return entry

static func retarget_materials(record:Dictionary)->void:
	# Resource-pack relocation changes only texture references, never geometry.
	if not record.has("house_prefab"):return
	var data:=decode(record.house_prefab).duplicate(true);var originals:Array=[]
	for material:Dictionary in data.materials:
		if not material.has("paint"):continue
		if not originals.has(material.paint):originals.append(material.paint)
		material.paint=record.prefab_materials[originals.find(material.paint)].duplicate(true)
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}

static func visual(record:Dictionary,effects:bool,paint_validation:Variant=null,material_pool:Variant=null)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=record.uuid
	var entry:=geometry(record,paint_validation,material_pool)
	if entry.is_empty():node.set_meta("paint_error","无效的房屋预制件数据");node.mesh=BoxMesh.new();return node
	node.mesh=entry.mesh.restore() if effects else entry.mesh
	node.set_meta("collision_solid",entry.source)
	node.transform=Fixtures.transform(record)
	if record.get("kind")=="asset":node.scale=vec(record.size)
	node.set_meta("extras",{"uuid":record.uuid,"kind":record.kind,"surface_id":record.surface_id,"rmmo_collision":record.collision})
	for field in ["building","fortification"]:
		if record.has(field):node.get_meta("extras")[field]=record[field].duplicate(true)
	if record.has("fixture"):node.get_meta("extras").fixture=record.fixture.duplicate(true)
	node.set_meta("house_prefab",true)
	node.set_meta("ground_batch_record",record)
	return node

static func bake(records:Array)->Dictionary:
	var doc=load("res://scripts/world3d/world_document.gd").new()
	doc.load_box_meshes={};doc.load_paint_validation={};doc.load_texture_checks={}
	var groups:Dictionary={};var result:Array=[];var material_keys:Dictionary={}
	for source:Dictionary in records:
		for field in ["event","event_template","seat","wind_response"]:
			if source.has(field):return {"ok":false,"error":"含事件、座位或风响应的建筑不能烘焙"}
		if source.has("house_prefab"):return {"ok":false,"error":"建筑已经烘焙"}
		var record:=source.duplicate(true)
		if record.get("building_shape")=="candle_sconce":
			record.prefab_locked=true;result.append(record);continue
		var b:Dictionary=record.building
		var section:String=b.part.get_slice("/",0)
		if section not in ["wing","wing_left","wing_right","workshop","yard"]:section="main"
		var role:String="floor" if b.role=="floor" else ("roof_tiles" if str(b.role).begins_with("roof") else "shell")
		if str(b.part).ends_with("/ceiling"):role="ceiling"
		var key:=str([section,b.floor,b.floor_y,role,record.get("fixture",{}).get("id","")])
		# Separate slab footprints preserve courtyard holes on the minimap, and
		# exact ceiling identities retain the roof-stair headhouse cutaway rule.
		if role in ["floor","ceiling"]:key+=str(b.part)
		if not groups.has(key):groups[key]=[]
		groups[key].append(record)
	for key:String in groups:
		var sources:Array=groups[key];var members:Array=[];var collision:=PackedVector3Array();var bounds:=AABB();var first:=true
		var fixture:Dictionary={};var pivot:=Vector3.ZERO
		for record:Dictionary in sources:
			if record.has("fixture"):
				fixture=record.fixture.duplicate(true)
				var closed:=Transform3D(Basis.from_euler(vec(record.rotation)*PI/180),vec(record.position))
				pivot=closed*vec(fixture.pivot);record.fixture.open=0.0
			var visual:MeshInstance3D=doc._mesh(record)
			if visual.has_meta("paint_error"):visual.free();return {"ok":false,"error":"预制件材质烘焙失败"}
			var cpu:Mesh=Cpu.capture(visual.mesh);var pose:Transform3D=visual.transform
			var box:AABB=pose*cpu.bounds;bounds=box if first else bounds.merge(box);first=false
			var keys:Array=[]
			for material:Material in cpu.materials:
				var packed:=Cook.material_data(material)
				if packed.is_empty():visual.free();return {"ok":false,"error":"预制件含不支持的动态材质"}
				if not material_keys.has(material):
					var resolved:=Merge.material_key(material)
					material_keys[material]=resolved if not resolved.is_empty() else var_to_str(packed)
				keys.append(material_keys[material])
			members.append({"record":record,"surfaces":cpu.surfaces,"materials":cpu.materials,"keys":keys,"transform":pose})
			if record.get("collision","block")!="none":
				var solid:Mesh=visual.get_meta("collision_solid",visual.get_meta("paint_source",visual.mesh))
				collision.append_array(pose*Cpu.capture(solid).collision_faces())
			visual.free()
		var center:=bounds.get_center()
		var merged:=Merge.build_fortification(members,center,true)
		var mesh:=Cpu.new();mesh.bounds=AABB(bounds.position-center,bounds.size)
		for slot:Dictionary in merged.slots:
			# Eliminate world-coordinate subtraction noise between identical leaves.
			# 10 micrometres is below the old render cache's 0.1 mm tolerance;
			# physics retains its unquantized exact source triangles.
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL]:
				if slot.arrays[channel]==null:continue
				var vectors:PackedVector3Array=slot.arrays[channel]
				for i in vectors.size():vectors[i]=vectors[i].snapped(Vector3.ONE*.00001)
				slot.arrays[channel]=vectors
			if slot.arrays[Mesh.ARRAY_TANGENT]!=null:
				var tangents:PackedFloat32Array=slot.arrays[Mesh.ARRAY_TANGENT]
				for i in tangents.size():tangents[i]=snappedf(tangents[i],.00001)
				slot.arrays[Mesh.ARRAY_TANGENT]=tangents
			mesh.surfaces.append(slot.arrays);mesh.materials.append(slot.material)
		var solid:=Cpu.new();solid.bounds=mesh.bounds
		if not collision.is_empty():
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=Transform3D(Basis.IDENTITY,-center)*collision
			solid.surfaces.append(arrays);solid.materials.append(null)
		else:solid=mesh
		var cache:Dictionary={};cache[[0]]={"mesh":mesh,"source":solid}
		var data:=Cook.pack(cache,"","house_prefab_v1")
		if data.entries.size()!=1:return {"ok":false,"error":"预制件材质不能序列化"}
		compact_data(data)
		var bytes:=var_to_bytes(data);var digest:=Cook.Envelope.checksum(bytes).hex_encode()
		var building:Dictionary=sources[0].building.duplicate(true)
		var section:String=building.part.get_slice("/",0)
		if section not in ["wing","wing_left","wing_right","workshop","yard"]:section="main"
		building.part=section+"/baked_"+str(result.size())+("/ceiling" if str(building.part).ends_with("/ceiling") else "")
		if sources[0].building.part=="roof/headhouse/ceiling":building.part="roof/headhouse/ceiling"
		if not str(building.role).begins_with("roof") and building.role!="floor":building.role="shell"
		var record:={"uuid":"baked_"+str(result.size()),"kind":"box","position":arr(center),"rotation":[0,0,0],"size":arr(bounds.size),"surface_id":sources[0].get("surface_id","block"),"collision":"none" if collision.is_empty() else "walk","building":building,"prefab_locked":true,"prefab_materials":[],"house_prefab":{"version":1,"sha256":digest,"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}}
		for material:Dictionary in data.materials:
			if material.has("paint") and not record.prefab_materials.has(material.paint):record.prefab_materials.append(material.paint)
		if not fixture.is_empty():fixture.pivot=arr(pivot-center);record.fixture=fixture
		result.append(record)
	return {"ok":true,"records":result,"source_count":records.size(),"component_count":result.size()}

static func compact_data(data:Dictionary)->void:
	# Native indexing deduplicates identical attributes, without simplification,
	# triangle removal, position quantization or changing triangle order.
	for value:Dictionary in data.meshes:
		if value.box_size!=Vector3.ZERO:continue
		var cpu:=Cpu.new();cpu.surfaces=value.surfaces;cpu.materials.resize(value.surfaces.size())
		for i in value.surfaces.size():
			var builder:=SurfaceTool.new();builder.create_from(cpu,i);builder.index()
			var indexed:=builder.commit_to_arrays()
			if not indexed.is_empty():value.surfaces[i]=indexed
