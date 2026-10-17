extends RefCounted
## Frozen render/collision groups, stored as plain data in the native document.
## No source pieces or generator calls are required when an instance is loaded.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Merge=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")
static var _meshes:Dictionary={}
static var _render_meshes:Dictionary={}
static var _decoded:Dictionary={}
static var _decoded_bytes:=0
static var _decode_mutex:=Mutex.new()
static var _decode_issuer:=RefCounted.new()
static func evict_geometry(digests:Dictionary)->void:
	var meshes:Dictionary={}
	for key:String in _meshes.keys():
		if not digests.has(key.get_slice(":",0)):continue
		meshes[_meshes[key].mesh.get_instance_id()]=true;_meshes.erase(key)
	# The independent 512-entry caches can evict at different times (painted
	# variants only occupy _meshes). Retire orphan render-cache owners as well.
	var live:Dictionary={}
	for entry:Dictionary in _meshes.values():live[entry.mesh.get_instance_id()]=true
	for key:String in _render_meshes.keys():
		var id:int=_render_meshes[key].get_instance_id()
		if meshes.has(id) or not live.has(id):_render_meshes.erase(key)
	_decode_mutex.lock()
	for key:String in digests:
		if _decoded.has(key):_decoded_bytes-=int(_decoded[key].length);_decoded.erase(key)
	_decode_mutex.unlock()
const DECODE_MAX_DEPTH:=64
const DECODE_MAX_VALUES:=2000000
const DECODE_BUDGET=536870912
const TEXTURE_PROPERTIES={"texture_path":"albedo_texture","normal_path":"normal_texture","roughness_path":"roughness_texture","metallic_path":"metallic_texture","ao_path":"ao_texture","height_path":"heightmap_texture"}

static func texture_tickets(sources:Dictionary,material_pool:Variant=null)->Dictionary:
	# Main only: a load's material pool and the render cache can retain complete
	# materials after either small Paint LRU or the prefab cache has evicted them.
	# Snapshot their actual GPU owners without reading pixels, making materials,
	# or installing prepared Images. The worker still verifies current source SHA.
	assert(Thread.is_main_thread())
	var result:Dictionary={};var seen:Dictionary={}
	for key:Variant in sources:
		if not key is String:continue
		var texture:Variant=Cook.Paint._textures.get(key)
		var ticket:=_texture_ticket(texture)
		if not ticket.is_empty():result[key]=ticket
	if result.size()==sources.size():return result
	if material_pool is Dictionary:
		_material_texture_tickets(material_pool.values(),sources,result,seen)
		if result.size()==sources.size():return result
	_material_texture_tickets(Cook.Paint._materials.values(),sources,result,seen)
	if result.size()==sources.size():return result
	for entry:Dictionary in _meshes.values():
		for mesh:Mesh in [entry.mesh,entry.source]:
			_material_texture_tickets(mesh.materials,sources,result,seen)
			if result.size()==sources.size():return result
	for mesh:Mesh in _render_meshes.values():
		_material_texture_tickets(mesh.materials,sources,result,seen)
		if result.size()==sources.size():return result
	return result

static func _texture_digest_valid(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for character in value:
		if character not in "0123456789abcdef":return false
	return true

static func _texture_ticket(texture:Variant)->Dictionary:
	if not texture is Texture2D:return {}
	var digest:Variant=texture.get_meta("runtime_source_sha256","")
	return {"texture":texture,"source_sha":digest} if _texture_digest_valid(digest) else {}

static func _material_texture_tickets(materials:Array,sources:Dictionary,result:Dictionary,seen:Dictionary)->void:
	for material:Variant in materials:
		if not material is StandardMaterial3D or seen.has(material.get_instance_id()):continue
		seen[material.get_instance_id()]=true
		var definition:Variant=material.get_meta("runtime_paint_definition",{})
		if not definition is Dictionary:continue
		for field:String in TEXTURE_PROPERTIES:
			var path:Variant=definition.get(field,"")
			if not path is String or path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			var key:String=path+("|flip_y" if flip else "")
			if not sources.has(key) or result.has(key):continue
			var ticket:=_texture_ticket(material.get(TEXTURE_PROPERTIES[field]))
			if not ticket.is_empty():result[key]=ticket
		if result.size()==sources.size():return

static func tickets_valid(tickets:Dictionary,sources:Dictionary)->bool:
	for key:String in tickets:
		var ticket:Dictionary=tickets[key];var texture:Texture2D=ticket.get("texture")
		var path:String=key.trim_suffix("|flip_y")
		if texture==null or texture.get_meta("runtime_source_sha256","")!=ticket.get("source_sha") or sources.get(path)!=ticket.get("source_sha"):return false
		var current:Texture2D=Cook.Paint._textures.get(key)
		if current!=null and current.get_meta("runtime_source_sha256","")!=ticket.source_sha:return false
	return true

static func _stale_material_keys(materials:Array,sources:Dictionary)->Dictionary:
	var changed:Dictionary={}
	for value:Variant in materials:
		if not value is StandardMaterial3D:continue
		var definition:Dictionary=value.get_meta("runtime_paint_definition",{})
		for field:String in TEXTURE_PROPERTIES:
			var path:String=definition.get(field,"")
			if not sources.has(path):continue
			var texture:Texture2D=value.get(TEXTURE_PROPERTIES[field])
			if texture!=null and texture.get_meta("runtime_source_sha256","")==sources[path]:continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			changed[path+("|flip_y" if flip else "")]=true
	return changed

static func invalidate_texture_materials(keys:Dictionary)->void:
	# Drop only cache references. Existing instances keep their immutable materials
	# and geometry until their owning view is replaced normally.
	if keys.is_empty():return
	for key in _meshes.keys():
		var entry:Dictionary=_meshes[key]
		if _uses_textures(entry.mesh,keys) or _uses_textures(entry.source,keys):_meshes.erase(key)
	for key in _render_meshes.keys():
		if _uses_textures(_render_meshes[key],keys):_render_meshes.erase(key)

static func _uses_textures(mesh:Mesh,keys:Dictionary)->bool:
	for material in mesh.materials:
		if material==null or not material.has_meta("runtime_paint_definition"):continue
		var definition:Dictionary=material.get_meta("runtime_paint_definition")
		for field in Cook.Paint.MAP_FIELDS:
			var path:=str(definition.get(field,""))
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			if keys.has(path+("|flip_y" if flip else "")):return true
	return false

static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func arr(v:Vector3)->Array:return [v.x,v.y,v.z]

static func decode(value:Dictionary)->Dictionary:
	# Preserve the public plain-data API; derived identities live only in the
	# retained packet, not in the serialized prefab schema. Packed arrays are
	# reference values even inside read-only containers: a public decode owns a
	# deep copy, never the cache's signature-bearing geometry storage.
	return _decode_packet(value).get("data",{}).duplicate(true)

static func warm(value:Dictionary)->bool:
	# Validation/prewarming needs no editable copy of the packed channels.
	return not _decode_packet(value).is_empty()

static func source_slot(value:Dictionary)->int:
	var packet:=_decode_packet(value)
	return -1 if packet.is_empty() else int(packet.data.entries[0][1][1])

static func local_bounds(value:Dictionary)->Dictionary:
	# Return math values only. Inspect actual vertices rather than trusting the
	# serialized bounds, preserving dependency-directory safety validation.
	var packet:=_decode_packet(value)
	if packet.is_empty():return {"known":false}
	var bounds:=AABB();var first:=true
	for mesh:Dictionary in packet.data.meshes:
		if mesh.box_size!=Vector3.ZERO:
			var box:=AABB(-mesh.box_size/2.0,mesh.box_size)
			bounds=box if first else bounds.merge(box);first=false
		for surface:Array in mesh.surfaces:
			for point:Vector3 in surface[Mesh.ARRAY_VERTEX]:
				if not point.is_finite():return {"known":false}
				bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
	return {"known":false} if first else {"known":true,"bounds":bounds}

static func _packet_matches(packet:Dictionary,digest:String,encoded:String,length:int)->bool:
	return packet.get("issuer")==_decode_issuer and packet.is_read_only() and packet.get("sha256")==digest and packet.get("encoded")==encoded and packet.get("length")==length and packet.get("data") is Dictionary and packet.data.is_read_only() and packet.get("geometry_keys") is Array and packet.geometry_keys.is_read_only()

static func _decode_packet(value:Dictionary)->Dictionary:
	if value.get("version")!=1 or not value.get("data") is String or not value.get("sha256") is String:return {}
	var length:int=int(value.get("length",0))
	var encoded:String=value.data;var digest:String=value.sha256
	if length<=0 or length>16777216 or encoded.length()>24000000:return {}
	_decode_mutex.lock()
	var cached:Dictionary=_decoded.get(digest,{})
	if _packet_matches(cached,digest,encoded,length):
		_decode_mutex.unlock();return cached
	_decode_mutex.unlock()
	var compressed:=Marshalls.base64_to_raw(encoded)
	var bytes:=compressed.decompress(length,FileAccess.COMPRESSION_ZSTD)
	if bytes.size()!=length or Cook.Envelope.checksum(bytes).hex_encode()!=digest:return {}
	var data:Variant=bytes_to_var(bytes)
	if not data is Dictionary or not Cook.valid_data(data) or data.entries.size()!=1:return {}
	# Seal every nested container before issuing the proof. A matching SHA or
	# container identity alone cannot validate a previously mutable cache entry.
	# Packed channels themselves cannot be made read-only. Keep this canonical
	# storage private, with deep ownership copies at every public/resource exit.
	if not _seal_decoded(data,0,[],[DECODE_MAX_VALUES]):return {}
	var geometry_keys:Array=[]
	for mesh:Dictionary in data.meshes:geometry_keys.append(Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[])))
	geometry_keys.make_read_only()
	var packet:={"issuer":_decode_issuer,"sha256":digest,"encoded":encoded,"length":length,"data":data,"geometry_keys":geometry_keys}
	packet.make_read_only()
	_decode_mutex.lock()
	# Concurrent readers may have decoded the same immutable payload. Publish
	# only one owner; callers keep its data/keys together even after LRU eviction.
	cached=_decoded.get(digest,{})
	if _packet_matches(cached,digest,encoded,length):
		_decode_mutex.unlock();return cached
	if _decoded.has(digest):_decoded_bytes-=int(_decoded[digest].length);_decoded.erase(digest)
	while not _decoded.is_empty() and _decoded_bytes+length>DECODE_BUDGET:
		var oldest:String=_decoded.keys()[0];_decoded_bytes-=_decoded[oldest].length;_decoded.erase(oldest)
	_decoded[digest]=packet;_decoded_bytes+=length
	_decode_mutex.unlock()
	return packet

static func _seal_decoded(value:Variant,depth:int,ancestors:Array,budget:Array)->bool:
	budget[0]-=1
	if depth>DECODE_MAX_DEPTH or budget[0]<0:return false
	if value is Dictionary or value is Array:
		for ancestor in ancestors:
			if is_same(ancestor,value):return false
		ancestors.append(value)
		if value is Dictionary:
			for key in value:
				if not _seal_decoded(key,depth+1,ancestors,budget) or not _seal_decoded(value[key],depth+1,ancestors,budget):ancestors.pop_back();return false
		else:
			for child in value:
				if not _seal_decoded(child,depth+1,ancestors,budget):ancestors.pop_back();return false
		ancestors.pop_back();value.make_read_only();return true
	return not (typeof(value) in [TYPE_OBJECT,TYPE_CALLABLE,TYPE_SIGNAL,TYPE_RID])

static func valid(record:Dictionary)->bool:
	if not record.has("house_prefab"):return true
	var owner:bool=record.has("building") or record.has("fortification") or record.has("bridge_mesh")
	if record.get("kind") not in ["box","asset"] or not record.house_prefab is Dictionary or not owner or record.get("prefab_locked")!=true or record.has("building_shape"):return false
	if record.has("surface_paint") and not record.has("building"):return false
	var packet:=_decode_packet(record.house_prefab)
	if packet.is_empty():return false
	var data:Dictionary=packet.data
	# Texture dependencies remain visible to native validation, packs and prefetch.
	var paints:Array=[]
	for material:Dictionary in data.materials:
		if material.has("paint") and not paints.has(material.paint):paints.append(material.paint)
	return record.get("prefab_materials",[])==paints

static func requires_source_model(record:Dictionary)->bool:
	# A complete validated frozen mesh owns its render/collision data. The old
	# kit path remains authoring provenance and still obeys resource-root rules.
	return record.get("kind")=="asset" and not (record.has("house_prefab") and valid(record))

static func prepare_cpu(record:Dictionary,collision_candidates:Dictionary={})->Dictionary:
	# Worker-owned plain data. Keep the arrays alive in the admitted task even
	# when the shared decoded cache is evicted before main-thread publication.
	var packet:=_decode_packet(record.house_prefab)
	if packet.is_empty():return {}
	var data:Dictionary=packet.data
	var faces:Array=[];var keys:Array=packet.geometry_keys
	for mesh_id:int in data.meshes.size():
		var mesh:Dictionary=data.meshes[mesh_id]
		if collision_candidates.has(mesh_id):
			# A candidate is private CPU data only. The enclosing reference worker
			# must still pass its final source/closure gate before this packet can
			# reach publish_prepared and receive a typed sealed collision product.
			faces.append(collision_candidates[mesh_id].faces);continue
		var triangles:=PackedVector3Array();var count:=0
		for arrays:Array in mesh.surfaces:
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		triangles.resize(count);var at:=0
		for arrays:Array in mesh.surfaces:
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			if indices!=null and not indices.is_empty():
				for index:int in indices:triangles[at]=vertices[index];at+=1
			else:
				for vertex:Vector3 in vertices:triangles[at]=vertex;at+=1
		faces.append(triangles)
	# A worker result is owned by its admitted job. Its packed arrays must not
	# alias the canonical cache even though no production consumer edits them.
	var owned_data:Dictionary=data.duplicate(true)
	if not _seal_decoded(owned_data,0,[],[DECODE_MAX_VALUES]):return {}
	return {"sha256":packet.sha256,"data":owned_data,"geometry_keys":keys,"collision_faces":faces}

static func publish_prepared(record:Dictionary,prepared:Dictionary,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null,texture_packet:Dictionary={})->bool:
	# Installation and resource caches are main-thread-only. Scope the supplied
	# CPU images to this one synchronous publication; unconsumed pixels remain in
	# the charged job, never a global dictionary after its admission is released.
	var publication_started:=Time.get_ticks_usec();var previous:Variant=null
	var resident:Dictionary=texture_packet.get("resident_textures",{})
	if not tickets_valid(resident,texture_packet.get("sources",{})):return false
	if not resident.is_empty():
		var source_ids:Dictionary=texture_packet.sources
		var stale:Dictionary=_stale_material_keys(Cook.Paint._materials.values(),source_ids)
		if material_pool!=null:stale.merge(_stale_material_keys(material_pool.values(),source_ids),true)
		var entry:Dictionary=_meshes.get(record.house_prefab.sha256,{})
		for name_:String in ["mesh","source"]:
			if entry.has(name_):stale.merge(_stale_material_keys(entry[name_].materials,source_ids),true)
		if not stale.is_empty():
			invalidate_texture_materials(stale);Cook.Paint._materials.clear()
			if material_pool!=null:material_pool.clear()
	# A ticket is an existing immutable GPU object, never an Image manufactured
	# on the worker. Restore evicted LRU entries without reading/uploading pixels.
	for key:String in resident:
		if not Cook.Paint._textures.has(key):
			if Cook.Paint._textures.size()>=64:Cook.Paint._textures.erase(Cook.Paint._textures.keys()[0])
			Cook.Paint._textures[key]=resident[key].texture
	if not texture_packet.get("images",{}).is_empty():
		# Cook's caller-owned pool can outlive a texture's small global LRU too.
		# Its old materials must not bypass the image-generation invalidation.
		if material_pool!=null:
			for key:String in texture_packet.images:
				if not Cook.Paint._textures.has(key) or Cook.Paint._textures[key].get_meta("runtime_source_sha256","")!=texture_packet.images[key].get_meta("runtime_source_sha256",""):
					material_pool.clear();break
		previous=load("res://scripts/world_editor/terrain_texture_preparation.gd").install({"images":texture_packet.images,"failed":[]})
	var result:=_publish_prepared(record,prepared,paint_validation,material_pool,timings)
	if previous!=null:load("res://scripts/world_editor/terrain_texture_preparation.gd").restore(previous)
	preload("res://scripts/world3d/load_trace.gd").elapsed("prefab_pixels.publish",publication_started,{"uuid":record.get("uuid",""),"images":texture_packet.get("images",{}).size(),"parts_ms":timings if timings!=null else {}})
	return result

static func _publish_prepared(record:Dictionary,prepared:Dictionary,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null)->bool:
	# Main-thread resource/material publication only. Never place this packet in
	# an authored record or serialize it; it belongs to the scheduler lease.
	var profile_mark:int=Time.get_ticks_usec() if timings!=null else 0
	var key:String=record.house_prefab.sha256
	if _meshes.has(key):
		if timings!=null:timings.geometry_cache_hit=true
		return true
	if prepared.get("sha256")!=key or not prepared.get("data") is Dictionary:return false
	var data:Dictionary=prepared.data
	if prepared.get("geometry_keys",[]).size()!=data.meshes.size() or prepared.get("collision_faces",[]).size()!=data.meshes.size():return false
	var restored:=Cook.restore(data.duplicate(),paint_validation,material_pool,timings)
	if timings!=null:timings.cook_restore_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	if restored.is_empty():return false
	var entry:Dictionary=restored.values()[0]
	var render_id:int=data.entries[0][1][0];var source_id:int=data.entries[0][1][1]
	entry.mesh._collision_faces=prepared.collision_faces[render_id]
	entry.source._collision_faces=prepared.collision_faces[source_id]
	for row:Array in [[entry.mesh,render_id],[entry.source,source_id]]:
		var product:Variant=prepared.get("collision_products",{}).get(row[1])
		if product is CollisionProducts.Product and not product.kind().is_empty():row[0].set_meta("runtime_collision_product",product)
	if timings!=null:timings.collision_handoff_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	_cache_geometry(key,entry,prepared.geometry_keys,data)
	if timings!=null:timings.render_identity_ms=(Time.get_ticks_usec()-profile_mark)/1000.
	return true

static func _cache_geometry(key:String,entry:Dictionary,geometry_keys:Array,data:Dictionary)->void:
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
	if _meshes.size()>=512:_meshes.erase(_meshes.keys()[0])
	_meshes[key]=entry

static func geometry(record:Dictionary,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null)->Dictionary:
	var profile_mark:int=Time.get_ticks_usec() if timings!=null else 0
	var key:String=record.house_prefab.sha256
	if not record.get("surface_paint",[]).is_empty():
		key += ":paint:"+var_to_str(record.surface_paint).sha256_text()
		if _meshes.has(key):return _meshes[key]
		var plain:=record.duplicate();plain.erase("surface_paint")
		var original:=geometry(plain,paint_validation,material_pool,timings)
		if original.is_empty():return {}
		var node:=MeshInstance3D.new();node.mesh=original.mesh
		var painted:=Cook.Paint.painted_mesh(node,record.surface_paint,true)
		node.free()
		if not painted.ok:return {}
		var decorated:={"mesh":Cpu.capture(painted.mesh),"source":original.source}
		if _meshes.size()>=512:_meshes.erase(_meshes.keys()[0])
		_meshes[key]=decorated
		return decorated
	if _meshes.has(key):
		if timings!=null:timings.geometry_cache_hit=true
		return _meshes[key]
	var packet:=_decode_packet(record.house_prefab)
	if timings!=null:timings.decode_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	if packet.is_empty():return {}
	var data:Dictionary=packet.data
	# CpuMesh exposes surface packed arrays to its consumers; it owns a copy and
	# must not provide a mutation route back into the canonical decode packet.
	var restored:=Cook.restore(data.duplicate(true),paint_validation,material_pool,timings)
	if timings!=null:timings.cook_restore_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	if restored.is_empty():return {}
	var entry:Dictionary=restored.values()[0]
	_cache_geometry(key,entry,packet.geometry_keys,data)
	if timings!=null:timings.render_identity_ms=(Time.get_ticks_usec()-profile_mark)/1000.
	return entry

static func retarget_materials(record:Dictionary)->void:
	# Resource-pack relocation changes only texture references, never geometry.
	if not record.has("house_prefab"):return
	var data:=decode(record.house_prefab);var originals:Array=[]
	for material:Dictionary in data.materials:
		if not material.has("paint"):continue
		if not originals.has(material.paint):originals.append(material.paint)
		material.paint=record.prefab_materials[originals.find(material.paint)].duplicate(true)
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}

static func visual(record:Dictionary,effects:bool,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=record.uuid
	var entry:=geometry(record,paint_validation,material_pool,timings)
	if entry.is_empty():node.set_meta("paint_error","无效的房屋预制件数据");node.mesh=BoxMesh.new();return node
	var profile_mark:int=Time.get_ticks_usec() if timings!=null else 0
	node.mesh=entry.mesh.restore() if effects else entry.mesh
	if not record.get("surface_paint",[]).is_empty():
		var plain:=record.duplicate();plain.erase("surface_paint")
		var original:=geometry(plain,paint_validation,material_pool)
		node.set_meta("paint_source",original.mesh)
		node.set_meta("paint_source_materials",original.mesh.materials)
	if timings!=null:timings.gpu_restore_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	node.set_meta("collision_solid",entry.source)
	node.transform=Fixtures.transform(record)
	if record.get("kind")=="asset":node.scale=vec(record.size)
	node.set_meta("extras",{"uuid":record.uuid,"kind":record.kind,"surface_id":record.surface_id,"rmmo_collision":record.collision})
	for field in ["building","fortification"]:
		if record.has(field):node.get_meta("extras")[field]=record[field].duplicate(true)
	if record.has("fixture"):node.get_meta("extras").fixture=record.fixture.duplicate(true)
	node.set_meta("house_prefab",true)
	node.set_meta("ground_batch_record",record)
	if timings!=null:timings.node_metadata_ms=(Time.get_ticks_usec()-profile_mark)/1000.
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
		var fixture:Dictionary={};var pivot:=Vector3.ZERO;var portals:Array=[]
		for record:Dictionary in sources:
			var closed_portal_pose:=Transform3D(Basis.from_euler(vec(record.rotation)*PI/180),vec(record.position))
			for hint:Dictionary in record.get("residential_portals",[]):
				portals.append(hint.merged({"position":arr(closed_portal_pose*vec(hint.position)),"outward":arr(closed_portal_pose.basis*vec(hint.outward))},true))
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
		if not portals.is_empty():
			for hint:Dictionary in portals:hint.position=arr(vec(hint.position)-center)
			record.residential_portals=portals
		result.append(record)
	return {"ok":true,"records":result,"source_count":records.size(),"component_count":result.size()}

static func compact_data(data:Dictionary)->void:
	# Native indexing deduplicates identical attributes, without simplification,
	# triangle removal, position quantization or changing triangle order.
	for value:Dictionary in data.meshes:
		if value.box_size!=Vector3.ZERO:continue
		var cpu:=Cpu.new();cpu.surfaces=value.surfaces;cpu.materials.resize(value.surfaces.size())
		for i in value.surfaces.size():
			# Imported LOD buffers reference this exact vertex order. Reindexing
			# without a complete old->new map would silently corrupt them.
			if not value.get("lods",[]).is_empty() and not value.lods[i].is_empty():continue
			var builder:=SurfaceTool.new();builder.create_from(cpu,i);builder.index()
			var indexed:=builder.commit_to_arrays()
			if not indexed.is_empty():value.surfaces[i]=indexed
