extends RefCounted
## Plain-data cooked geometry. No scripts or Objects are deserialized from disk.
## Source file and generator hashes invalidate it; materials rebuild from their
## authored definitions so textures are still validated and loaded normally.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Envelope=preload("res://scripts/world3d/map_metadata_cache.gd")
const DIR:="user://world3d_meshes"
const MAGIC:="RMMOMESH2"
const HEADER_SIZE:=113 # magic, length, source identity, generator identity, checksum

static func _identity(value:String)->PackedByteArray:
	return Envelope.checksum(value.to_utf8_buffer())

static func _checksum(source:PackedByteArray,generator:PackedByteArray,bytes:PackedByteArray)->PackedByteArray:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	context.update(source);context.update(generator);context.update(bytes)
	return context.finish()

static func generator_key()->String:
	var hashes:Array=[Engine.get_version_info().hash]
	for file in ["house_prefab.gd","world_document.gd","surface_materials.gd","ground_cpu_mesh.gd","runtime_mesh_cache.gd","world_stream.gd","stream_index.gd","stream_landscape.gd","streetlamp_banner.gd","streetlamp_lights.gd","building_fixtures.gd","wind_response.gd","building_blueprint.gd","house_wall_mesh.gd","curtain_mesh.gd","linen_curtain_data.gd","joined_box_mesh.gd","candle_sconce_mesh.gd","candle_sconce_data.gd","timber_door_mesh.gd","interior_door_mesh.gd","interior_door_layout.gd","roof_mesh.gd","fortification_art.gd","fortification_stair_mesh.gd"]:
		hashes.append(FileAccess.get_sha256("res://scripts/world3d/"+file))
	for file in ["terrain_surface.gd","terrain_furrows.gd","terrain_neighbors.gd","terrain_regions.gd","terrain_context_cache.gd","road_surface.gd","road_kerb.gd","channel_surface.gd","rock_bank_mesh.gd"]:
		hashes.append(FileAccess.get_sha256("res://scripts/world3d/"+file))
	return str(hashes).sha256_text()

static func cache_path(path:String)->String:
	return DIR.path_join(path.replace("\\","/").simplify_path().sha256_text()+".bin")

static func read(path:String,digest:String,generator:String,diagnostics:Variant=null)->Dictionary:
	if diagnostics!=null:diagnostics.payload_bytes_read=0;diagnostics.reason="missing_or_header"
	var file:=FileAccess.open(cache_path(path),FileAccess.READ)
	# Old envelopes are disposable misses. Reject stale identities before
	# reading/checksumming/deserializing a potentially 256 MB geometry payload.
	if file==null or file.get_length()<=HEADER_SIZE or file.get_buffer(9).get_string_from_ascii()!=MAGIC:return {}
	var length:=file.get_64()
	if length<=0 or length>268435456 or length+HEADER_SIZE!=file.get_length():return {}
	var source_key:=file.get_buffer(32);var generator_key_:=file.get_buffer(32)
	if source_key!=_identity(digest) or generator_key_!=_identity(generator):
		if diagnostics!=null:diagnostics.reason="identity_mismatch"
		return {}
	var checksum:=file.get_buffer(32);var bytes:=file.get_buffer(length)
	if diagnostics!=null:diagnostics.payload_bytes_read=bytes.size();diagnostics.reason="checksum"
	if _checksum(source_key,generator_key_,bytes)!=checksum:return {}
	var data:Variant=bytes_to_var(bytes)
	if diagnostics!=null:diagnostics.reason="payload_identity"
	if not data is Dictionary or data.get("digest")!=digest or data.get("generator")!=generator:return {}
	if diagnostics!=null:diagnostics.reason="invalid_data"
	if not valid_data(data):return {}
	if diagnostics!=null:diagnostics.reason="hit"
	return data

static func index_valid(value:Variant,count:int)->bool:
	return value is int and value>=0 and value<count

static func valid_data(data:Dictionary)->bool:
	if not data.get("materials") is Array or not data.get("meshes") is Array or not data.get("entries") is Array or not data.get("specs",[]) is Array:return false
	for value in data.materials:
		if not value is Dictionary:return false
		if value.has("paint"):
			if not value.paint is Dictionary or not value.get("cull") is int or value.cull<0 or value.cull>2:return false
			if value.has("vertex_color") and not value.vertex_color is bool:return false
		elif value.has("values"):
			if not value["values"] is Dictionary or value["values"].has("script") or value["values"].has("resource_path"):return false
		elif value.get("null")!=true:return false
	for value in data.meshes:
		if not value is Dictionary or not value.get("surfaces") is Array or not value.get("materials") is Array:return false
		if not value.get("bounds") is AABB or not value.bounds.position.is_finite() or not value.bounds.size.is_finite():return false
		if not value.get("box_size") is Vector3 or not value.box_size.is_finite() or value.box_size.x<0 or value.box_size.y<0 or value.box_size.z<0:return false
		if value.materials.size()!=value.surfaces.size():return false
		for id in value.materials:
			if not index_valid(id,data.materials.size()):return false
		for arrays in value.surfaces:
			if not arrays is Array or arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:return false
			var count:int=arrays[Mesh.ARRAY_VERTEX].size()
			if count==0:return false
			for slot in Mesh.ARRAY_MAX:
				var channel:Variant=arrays[slot]
				if channel==null:continue
				if slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL]:
					if not channel is PackedVector3Array or channel.size()!=count:return false
				elif slot==Mesh.ARRAY_TANGENT:
					if not channel is PackedFloat32Array or channel.size()!=count*4:return false
				elif slot==Mesh.ARRAY_COLOR:
					if not channel is PackedColorArray or channel.size()!=count:return false
				elif slot in [Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
					if not channel is PackedVector2Array or channel.size()!=count:return false
				elif slot==Mesh.ARRAY_INDEX:
					if not channel is PackedInt32Array or channel.size()%3!=0:return false
					# Bounds are a native reduction, not millions of interpreted iterations.
					if not channel.is_empty():
						var bounds:Array=Array(channel)
						if bounds.min()<0 or bounds.max()>=count:return false
				else:return false # Static authoring geometry has no skin/custom channels.
	for entry in data.entries:
		if not entry is Array or entry.size()!=2 or not entry[0] is Array or not entry[1] is Array or entry[1].size()!=2:return false
		for id in entry[1]:
			if not index_valid(id,data.meshes.size()):return false
	for row in data.get("specs",[]):
		if row is Dictionary and row.get("fallback")==true:
			if not row.get("uuid") is String:return false
			continue
		if not row is Dictionary or not row.get("spec") is Dictionary or not row.get("batch") is bool or not index_valid(row.get("mesh"),data.meshes.size()):return false
		var spec:Dictionary=row.spec
		if not spec.get("uuid") is String or not spec.get("extras") is Dictionary or not spec.get("native_visual") is bool or not spec.get("cast_shadow") is int:return false
		if not spec.get("transform") is Transform3D or not spec.transform.is_finite() or not spec.get("position") is Vector3 or not spec.get("rotation") is Vector3:return false
		for field in ["chunk","chunk_min","chunk_max"]:
			if not spec.get(field) is Vector2i:return false
		if spec.chunk_max.x<spec.chunk_min.x or spec.chunk_max.y<spec.chunk_min.y or (spec.chunk_max-spec.chunk_min).length()>4096:return false
		if spec.get("material_override")!=null or not spec.get("surface_overrides") is Array or spec.surface_overrides.any(func(v):return v!=null):return false
		if spec.has("closed_transform") and (not spec.closed_transform is Transform3D or not spec.closed_transform.is_finite()):return false
		if spec.extras.has("fixture") and not spec.has("closed_transform"):return false
		if row.has("box") and (not row.box is Vector3 or not row.box.is_finite() or row.box.x<=0 or row.box.y<=0 or row.box.z<=0):return false
		if row.has("collision") and not index_valid(row.collision,data.meshes.size()):return false
	return true

static func material_data(material:Material)->Dictionary:
	if material==null:return {"null":true}
	if not material is StandardMaterial3D:return {}
	if material.has_meta("runtime_paint_definition"):
		var result:={"paint":material.get_meta("runtime_paint_definition"),"cull":material.cull_mode}
		if material.vertex_color_use_as_albedo:result.vertex_color=true
		return result
	var values:Dictionary={}
	for property in material.get_property_list():
		if not property.usage & PROPERTY_USAGE_STORAGE or property.name in ["script","resource_path"] or str(property.name).begins_with("metadata/"):continue
		var value:Variant=material.get(property.name)
		if value is Object:return {} # Unsupported custom texture/material: regenerate it.
		values[property.name]=value
	return {"values":values}

static func pack(cache:Dictionary,digest:String,generator:String,library:Array=[])->Dictionary:
	var materials:Array=[];var meshes:Array=[];var entries:Array=[]
	var material_ids:Dictionary={};var mesh_ids:Dictionary={}
	for key:Array in cache:
		var ids:Array=[];var supported:=true
		for field in ["mesh","source"]:
			var mesh:Mesh=cache[key][field]
			var mid:=mesh.get_instance_id()
			if not mesh_ids.has(mid):
				var cpu:Mesh=Cpu.capture(mesh);var slots:Array=[]
				for material:Material in cpu.materials:
					var id:=material.get_instance_id() if material!=null else 0
					if not material_ids.has(id):
						var value:=material_data(material)
						if value.is_empty():supported=false;break
						material_ids[id]=materials.size();materials.append(value)
					slots.append(material_ids[id])
				if not supported:break
				mesh_ids[mid]=meshes.size()
				mesh_ids[cpu.get_instance_id()]=meshes.size()
				meshes.append({"surfaces":cpu.surfaces,"materials":slots,"bounds":cpu.bounds,"box_size":cpu.box_size})
			ids.append(mesh_ids[mid])
		if supported:entries.append([key,ids])
	var specs:Array=[];var skipped:=""
	for spec:Dictionary in library:
		if spec.get("material_override")!=null or spec.surface_overrides.any(func(value):return value!=null) or not mesh_ids.has(spec.mesh.get_instance_id()):skipped="render:"+str(spec.uuid);specs.append({"fallback":true,"uuid":spec.uuid});continue
		var copy:=spec.duplicate()
		for field in ["mesh","collision_mesh","ground_batch_record","render_bounds","render_supports","render_dependents","render_building"]:copy.erase(field)
		var row:={"spec":copy,"mesh":mesh_ids[spec.mesh.get_instance_id()],"batch":spec.has("ground_batch_record")}
		var collision:Mesh=spec.get("collision_mesh")
		if collision is BoxMesh:row.box=collision.size
		elif collision!=null:
			if not mesh_ids.has(collision.get_instance_id()):skipped="collision:"+str(spec.uuid);specs.append({"fallback":true,"uuid":spec.uuid});continue
			row.collision=mesh_ids[collision.get_instance_id()]
		specs.append(row)
	return {"digest":digest,"generator":generator,"materials":materials,"meshes":meshes,"entries":entries,"specs":specs,"specs_skip_reason":skipped}


static func restore(data:Dictionary,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null)->Dictionary:
	var profile_mark:int=Time.get_ticks_usec() if timings!=null else 0
	if data.is_empty():return {}
	# A pool belongs to one immutable runtime load. Editor restores remain local.
	if material_pool==null:material_pool={}
	var materials:Array[Material]=[];var meshes:Array=[];var result:Dictionary={}
	for value:Dictionary in data.materials:
		var identity:Array=[value]
		if material_pool.has(identity):materials.append(material_pool[identity]);continue
		var material:StandardMaterial3D
		if value.has("paint"):
			if not Paint.material_valid(value.paint,false,"",paint_validation):data.clear();return {}
			material=Paint.make_material(value.paint,value.cull)
			if value.get("vertex_color",false):
				# Do not change the shared un-tinted paint used by walls and other assets.
				material=material.duplicate();material.vertex_color_use_as_albedo=true
		elif value.has("values"):
			if not material_pool.has("schema"):
				var schema:Dictionary={};var prototype:=StandardMaterial3D.new()
				for property in prototype.get_property_list():
					if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script","resource_path"]:schema[property.name]=property.type
				material_pool.schema=schema
			var allowed:Dictionary=material_pool.schema
			material=StandardMaterial3D.new()
			for key in value["values"]:
				var property:Variant=value["values"][key]
				if not allowed.has(key) or (typeof(property)!=allowed[key] and not (property==null and allowed[key]==TYPE_OBJECT)):data.clear();return {}
				material.set(key,property)
		material_pool[identity]=material
		materials.append(material)
	if timings!=null:timings.materials_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	for value:Dictionary in data.meshes:
		var mesh:=Cpu.new();mesh.surfaces=value.surfaces;mesh.bounds=value.bounds;mesh.box_size=value.box_size
		for id:int in value.materials:mesh.materials.append(materials[id])
		meshes.append(mesh)
	for entry:Array in data.entries:result[entry[0]]={"mesh":meshes[entry[1][0]],"source":meshes[entry[1][1]]}
	data["_restored_meshes"]=meshes
	if timings!=null:timings.cpu_meshes_ms=(Time.get_ticks_usec()-profile_mark)/1000.
	return result

static func restore_specs(data:Dictionary,records:Array)->Array:
	var rows:Array=data.get("specs",[])
	if not data.has("_restored_meshes"):return []
	var result:Array=[];var solids:Dictionary={};var meshes:Array=data._restored_meshes
	var by_id:Dictionary={}
	for row:Dictionary in rows:
		var id:String=row.uuid if row.get("fallback")==true else row.spec.uuid
		if by_id.has(id):return []
		by_id[id]=row
	var expected:Dictionary={};var seen:Dictionary={}
	for record:Dictionary in records:
		var id:String=record.uuid
		if seen.has(id):return []
		seen[id]=true
		# This is precisely MapLoader's independently imported asset branch.
		# It never appends to the cooked library. No other missing row is valid.
		if record.get("kind")=="asset" and not record.has("house_prefab"):continue
		expected[id]=true
	if by_id.size()!=expected.size():return []
	for id:String in by_id:
		if not expected.has(id):return []
	for i in records.size():
		if records[i].get("kind")=="asset" and not records[i].has("house_prefab"):
			result.append({});continue
		if not by_id.has(records[i].uuid):return []
		var row:Dictionary=by_id[records[i].uuid]
		if row.get("fallback")==true:
			if row.uuid!=records[i].uuid:return []
			result.append({});continue
		var spec:Dictionary=row.spec.duplicate(true)
		if spec.uuid!=records[i].uuid:return []
		spec.mesh=meshes[row.mesh]
		if row.has("box"):
			if not solids.has(row.box):
				var box:=BoxMesh.new();box.size=row.box;solids[row.box]=box
			spec.collision_mesh=solids[row.box]
		elif row.has("collision"):spec.collision_mesh=meshes[row.collision]
		if row.batch:spec.ground_batch_record=records[i]
		result.append(spec)
	return result

static func write(path:String,data:Dictionary)->void:
	if not data.get("digest") is String or not data.get("generator") is String:return
	if DirAccess.make_dir_recursive_absolute(DIR)!=OK:return
	var bytes:=var_to_bytes(data)
	if bytes.size()>268435456:return
	var target:=cache_path(path);var temporary:=target+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return
	var source_key:=_identity(data.digest);var generator_key_:=_identity(data.generator)
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_64(bytes.size())
	file.store_buffer(source_key);file.store_buffer(generator_key_)
	file.store_buffer(_checksum(source_key,generator_key_,bytes));file.store_buffer(bytes);file.close()
	if DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
