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
static var _render_owner_aliases:Dictionary={} # Bounded weak aliases, never an additional geometry owner.
static var material_owner_reuse_enabled:=true
static var split_retirement_owner_units_enabled:=true # Diagnostic old compound retirement unit.
static var material_identity_reuses:=0
static var material_identity_scans:=0
static var texture_invalidation_material_scans:=0
static var _decoded:Dictionary={}
static var _decoded_bytes:=0
static var _decode_mutex:=Mutex.new()
static var _decode_issuer:=RefCounted.new()
static var coalesce_decodes:=true # Diagnostic control for concurrent cold requests.
static var trusted_metadata_reuse_enabled:=true
static var native_unindexed_faces_enabled:=true
static var raw_face_reuse_enabled:=true
static var prepared_face_handoff_enabled:=true # Diagnostic old cache-hit/alias publication order.
static var bounds_only_decode_enabled:=true
static var _decoding:Dictionary={}
class DecodeFlight extends RefCounted:
	var wake:=Semaphore.new()
	var waiters:=0
	var encoded:String
	var length:int
	var trusted_package:=false
	var packet:Dictionary={}
static func evict_geometry(digests:Dictionary)->void:
	var trace=preload("res://scripts/world3d/load_trace.gd")
	var phase:=Time.get_ticks_usec()
	var retired:Array=[]
	for key:String in _meshes.keys():
		if not digests.has(key.get_slice(":",0)):continue
		var retiring:Dictionary=_meshes[key]
		if split_retirement_owner_units_enabled:
			# geometry() can lend this dictionary to surviving callers. Keep both
			# known Resource edges before dropping our cache reference; separate
			# units need not destroy both direct owners in one minimum-budget step.
			# Never clear the entry or traverse its shared geometry/material graph.
			retired.append(retiring.mesh);retired.append(retiring.source)
		else:retired.append(retiring)
		_meshes.erase(key)
	trace.elapsed("prefab.retire_geometry",phase,{"digests":digests.size()});phase=Time.get_ticks_usec()
	# The independent 512-entry caches can evict at different times (painted
	# variants only occupy _meshes). Retire orphan render-cache owners as well.
	var live:Dictionary={}
	for entry:Dictionary in _meshes.values():live[entry.mesh.get_instance_id()]=true
	for key:String in _render_meshes.keys():
		var id:int=_render_meshes[key].get_instance_id()
		# Different definitions may share the same immutable render content.
		# Keep that lookup while any remaining definition still owns it.
		if not live.has(id):retired.append(_render_meshes[key]);_render_meshes.erase(key)
	trace.elapsed("prefab.retire_render",phase);phase=Time.get_ticks_usec()
	var decoded_values:Array=[];var decoded_bytes:=0
	_decode_mutex.lock()
	trace.elapsed("prefab.retire_decode_lock",phase);phase=Time.get_ticks_usec()
	for key:String in digests:
		if _decoded.has(key):
			var packet:Dictionary=_decoded[key];var bytes:=retained_decode_bytes(packet)
			if preload("res://scripts/world3d/resource_retirement.gd").background_decoded_release_enabled and packet.get("issuer")==_decode_issuer:
				# Only fields issued by our no-Object decoder cross the thread boundary.
				# The issuer remains on main; no GPU resources enter this donation.
				for field:String in ["data","collision_faces","encoded","geometry_keys","local_bounds"]:
					if packet.has(field):decoded_values.append(packet[field])
				decoded_bytes+=bytes
			else:retired.append(packet)
			_decoded_bytes-=bytes;_decoded.erase(key)
	_decode_mutex.unlock()
	trace.elapsed("prefab.retire_decoded",phase,{"digests":digests.size()})
	if not decoded_values.is_empty():preload("res://scripts/world3d/resource_retirement.gd").defer_cpu_values(decoded_values,decoded_bytes)
	# Logical eviction is synchronous; final immutable packet/mesh destruction
	# is distributed even when a small cache array owns large nested geometry.
	preload("res://scripts/world3d/resource_retirement.gd").defer_private_array(retired,true)
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
		# Live scenes may be the only strong owners after hot-cache eviction.
		# Capture the weak catalogue too, before admitting decode/upload work.
		var texture:Texture2D=Cook.Paint.retained_texture(key)
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
			var key:String=Cook.Paint.texture_key(path,flip,field=="normal_path")
			if not sources.has(key) or result.has(key):continue
			var ticket:=_texture_ticket(material.get(TEXTURE_PROPERTIES[field]))
			if not ticket.is_empty():result[key]=ticket
		if result.size()==sources.size():return

static func tickets_valid(tickets:Dictionary,sources:Dictionary)->bool:
	for key:String in tickets:
		var ticket:Dictionary=tickets[key];var texture:Texture2D=ticket.get("texture")
		var path:String=Cook.Paint.texture_source_path(key)
		if texture==null or texture.get_meta("runtime_source_sha256","")!=ticket.get("source_sha") or sources.get(path)!=ticket.get("source_sha"):return false
		var current:Texture2D=Cook.Paint._textures.get(key)
		if current!=null and current.get_meta("runtime_source_sha256","")!=ticket.source_sha:return false
	return true

static func _stale_material_keys(materials:Array,sources:Dictionary,prepared:Dictionary={})->Dictionary:
	var changed:Dictionary={}
	for value:Variant in materials:
		if not value is StandardMaterial3D:continue
		var definition:Dictionary=value.get_meta("runtime_paint_definition",{})
		for field:String in TEXTURE_PROPERTIES:
			var path:String=definition.get(field,"")
			if not sources.has(path):continue
			var texture:Texture2D=value.get(TEXTURE_PROPERTIES[field])
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			var key:String=Cook.Paint.texture_key(path,flip,field=="normal_path")
			if texture!=null and texture.get_meta("runtime_source_sha256","")==sources[path] and (not prepared.has(key) or Cook.Paint._same_prepared_texture(texture,prepared[key])):continue
			changed[key]=true
	return changed

static func invalidate_texture_materials(keys:Dictionary)->void:
	# Drop only cache references. Existing instances keep their immutable materials
	# and geometry until their owning view is replaced normally.
	if keys.is_empty():return
	# Many source/render aliases share the same material. Inspect each material
	# once for THIS notification; keep no stale answers across editor changes.
	var usage:Dictionary={}
	for key in _meshes.keys():
		var entry:Dictionary=_meshes[key]
		if _uses_textures(entry.mesh,keys,usage) or _uses_textures(entry.source,keys,usage):_meshes.erase(key)
	for key in _render_meshes.keys():
		if _uses_textures(_render_meshes[key],keys,usage):_render_meshes.erase(key)

static func _uses_textures(mesh:Mesh,keys:Dictionary,usage:Dictionary={})->bool:
	for material in mesh.materials:
		if material==null:continue
		var id:int=material.get_instance_id()
		if usage.has(id):
			if usage[id]:return true
			continue
		usage[id]=false
		texture_invalidation_material_scans+=1
		if not material.has_meta("runtime_paint_definition"):continue
		var definition:Dictionary=material.get_meta("runtime_paint_definition")
		for field in Cook.Paint.MAP_FIELDS:
			var path:=str(definition.get(field,""))
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			if keys.has(Cook.Paint.texture_key(path,flip,field=="normal_path")):
				usage[id]=true;return true
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
	# Authored packages already contain mesh bounds. Diagnostic verification
	# retains the vertex scan; callers receive only independent math values.
	var packet:=_decode_packet(value,false,true)
	if packet.is_empty():return {"known":false}
	return packet.local_bounds.duplicate()

static func _local_bounds(data:Dictionary)->Dictionary:
	var bounds:=AABB();var first:=true
	for mesh:Dictionary in data.meshes:
		if mesh.box_size!=Vector3.ZERO:
			var box:=AABB(-mesh.box_size/2.0,mesh.box_size)
			bounds=box if first else bounds.merge(box);first=false
		for surface:Array in mesh.surfaces:
			for point:Vector3 in surface[Mesh.ARRAY_VERTEX]:
				if not point.is_finite():return {"known":false}
				bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
	return {"known":false} if first else {"known":true,"bounds":bounds}

static func _stored_local_bounds(data:Dictionary)->Dictionary:
	# Frozen groups store conservative source AABBs; their rounded output
	# vertices may differ by a few micrometres. Keep that authoring envelope
	# with a 0.1 mm numerical margin, not another per-vertex reduction.
	var bounds:=AABB();var first:=true
	for mesh:Dictionary in data.meshes:
		if mesh.box_size!=Vector3.ZERO:
			var box:=AABB(-mesh.box_size/2.0,mesh.box_size)
			bounds=box if first else bounds.merge(box);first=false
		if not mesh.surfaces.is_empty():
			bounds=mesh.bounds if first else bounds.merge(mesh.bounds);first=false
	return {"known":false} if first else {"known":true,"bounds":bounds.grow(.0001)}

static func _seal_owned_containers(data:Variant)->void:
	# Only freshly decoded/duplicated private data enters here. Freezing keeps
	# the ownership contract; scalar revalidation and ancestor walks add no
	# information for a trusted package. Read-only containers are visited once.
	var pending:Array=[data]
	while not pending.is_empty():
		var container:Variant=pending.pop_back()
		if container.is_read_only():continue
		container.make_read_only()
		if container is Dictionary:
			for key in container:
				if key is Array or key is Dictionary:pending.append(key)
				var value:Variant=container[key]
				if value is Array or value is Dictionary:pending.append(value)
		else:
			for value in container:
				if value is Array or value is Dictionary:pending.append(value)

static func _packet_matches(packet:Dictionary,digest:String,encoded:String,length:int,trusted_package:bool,with_faces:bool=false,with_keys:bool=true)->bool:
	if with_faces and not _faces_ready(packet):return false
	if with_keys and not packet.get("geometry_ready",true):return false
	if not trusted_package and (not packet.get("verified",false) or packet.get("encoded")!=encoded):return false
	# Authored SHA/length identify a trusted immutable package. Comparing megabytes
	# of base64 again while holding the shared mutex serializes unrelated workers.
	# The issuer/sealed-owner checks still reject mutable or foreign cache entries.
	return packet.get("issuer")==_decode_issuer and packet.is_read_only() and packet.get("sha256")==digest and packet.get("length")==length and packet.get("data") is Dictionary and packet.data.is_read_only() and packet.get("geometry_keys") is Array and packet.geometry_keys.is_read_only() and packet.get("local_bounds") is Dictionary and packet.local_bounds.is_read_only()

static func retained_decode_bytes(packet:Dictionary)->int:
	return int(packet.get("retained_bytes",packet.get("length",0)))

static func raw_face_reuse_active()->bool:
	# Ordered collision triangles depend on geometry. Consumers retain all required
	# slots under the same bounded cache/flight and private-output ownership.
	return raw_face_reuse_enabled and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()

static func _decode_packet(value:Dictionary,with_faces:bool=false,bounds_only:bool=false)->Dictionary:
	if value.get("version")!=1 or not value.get("data") is String or not value.get("sha256") is String:return {}
	var length:int=int(value.get("length",0))
	var encoded:String=value.data;var digest:String=value.sha256
	if length<=0 or length>16777216 or encoded.length()>24000000:return {}
	var trusted_package:=preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	with_faces=with_faces and raw_face_reuse_active()
	var with_keys:=not (bounds_only and bounds_only_decode_enabled and trusted_package and trusted_metadata_reuse_enabled and not with_faces)
	_decode_mutex.lock()
	var cached:Dictionary=_decoded.get(digest,{})
	var upgrade:=_packet_matches(cached,digest,encoded,length,trusted_package,false,false)
	if upgrade and _packet_matches(cached,digest,encoded,length,trusted_package,with_faces,with_keys):
		_decode_mutex.unlock();return cached
	if coalesce_decodes and _decoding.has(digest):
		var active:DecodeFlight=_decoding[digest]
		if active.length==length and (trusted_package or (not active.trusted_package and active.encoded==encoded)):
			active.waiters+=1;_decode_mutex.unlock()
			var waited:=Time.get_ticks_usec();active.wake.wait()
			preload("res://scripts/world3d/load_trace.gd").elapsed("prefab.decode_join",waited,{"sha256":digest})
			# A metadata-only flight may finish first. Upgrade that exact decoded
			# owner through another coalesced flight, never decode its bytes again.
			return _decode_packet(value,with_faces,bounds_only) if not active.packet.is_empty() and not _packet_matches(active.packet,digest,encoded,length,trusted_package,with_faces,with_keys) else active.packet
	var flight:=DecodeFlight.new();flight.encoded=encoded;flight.length=length;flight.trusted_package=trusted_package
	var registered:bool=coalesce_decodes and not _decoding.has(digest)
	if registered:_decoding[digest]=flight
	_decode_mutex.unlock()
	var started:=Time.get_ticks_usec()
	var phase:String=("prefab.keys" if not cached.get("geometry_ready",true) else "prefab.faces") if upgrade else "prefab.decode"
	preload("res://scripts/world3d/load_trace.gd").instant(phase+"_begin",{"sha256":digest,"bytes":length})
	var packet:Dictionary=cached if upgrade else _decode_uncached(encoded,digest,length,trusted_package,with_keys)
	if with_keys and not packet.is_empty() and not packet.get("geometry_ready",true):packet=_with_geometry_keys(packet)
	if with_faces and not packet.is_empty() and not _faces_ready(packet):packet=_with_collision_faces(packet)
	preload("res://scripts/world3d/load_trace.gd").elapsed(phase,started,{"sha256":digest,"bytes":length,"ok":not packet.is_empty()})
	# Release the previous snapshot outside the mutex. Keep removed packets alive
	# through the cache transaction, including a duplicate result that lost a race.
	cached={}
	var retired:Array=[]
	_decode_mutex.lock()
	if not packet.is_empty():
		cached=_decoded.get(digest,{})
		if _packet_matches(cached,digest,encoded,length,trusted_package,with_faces,with_keys):retired.append(packet);packet=cached
		else:
			if _decoded.has(digest):retired.append(_decoded[digest]);_decoded_bytes-=retained_decode_bytes(_decoded[digest]);_decoded.erase(digest)
			var retained:=retained_decode_bytes(packet)
			while not _decoded.is_empty() and _decoded_bytes+retained>DECODE_BUDGET:
				var oldest:String=_decoded.keys()[0];retired.append(_decoded[oldest]);_decoded_bytes-=retained_decode_bytes(_decoded[oldest]);_decoded.erase(oldest)
			if retained<=DECODE_BUDGET:_decoded[digest]=packet;_decoded_bytes+=retained
	if registered:
		_decoding.erase(digest);flight.packet=packet
	_decode_mutex.unlock()
	if registered:
		for i in flight.waiters:flight.wake.post()
	retired.clear()
	return packet

static func _with_geometry_keys(packet:Dictionary)->Dictionary:
	# Spatial classification needs authored bounds only. Derive render identities
	# once when a real geometry consumer arrives, retaining the decoded owner.
	var result:=packet.duplicate();var keys:Array=[]
	for mesh:Dictionary in packet.data.meshes:keys.append(Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[])))
	keys.make_read_only();result.geometry_keys=keys;result.geometry_ready=true;result.make_read_only()
	return result

static func _faces_ready(packet:Dictionary)->bool:
	return packet.has("collision_faces")

static func _with_collision_faces(packet:Dictionary)->Dictionary:
	# Spatial queries retain decoded metadata only. The first geometry consumer
	# prepares every required slot once; job outputs still own private arrays.
	var result:=packet.duplicate();var faces:Array=[];var retained:int=packet.length
	for mesh:Dictionary in packet.data.meshes:
		var triangles:=preload("res://scripts/world3d/prefab_face_arrays.gd").build(mesh,native_unindexed_faces_enabled)
		faces.append(triangles);retained+=triangles.size()*12+16
	faces.make_read_only()
	result.collision_faces=faces;result.retained_bytes=retained;result.make_read_only()
	return result

static func _decode_uncached(encoded:String,digest:String,length:int,trusted_package:bool,with_keys:bool=true)->Dictionary:
	var compressed:=Marshalls.base64_to_raw(encoded)
	var bytes:=compressed.decompress(length,FileAccess.COMPRESSION_ZSTD)
	if bytes.size()!=length or (not trusted_package and Cook.Envelope.checksum(bytes).hex_encode()!=digest):return {}
	var data:Variant=bytes_to_var(bytes)
	if not data is Dictionary or not data.get("meshes") is Array or not data.get("materials") is Array or not data.get("entries") is Array or data.entries.size()!=1:return {}
	if not trusted_package and not Cook.valid_data(data):return {}
	# Seal every nested container before issuing the proof. A matching SHA or
	# container identity alone cannot validate a previously mutable cache entry.
	# Packed channels themselves cannot be made read-only. Keep this canonical
	# storage private, with deep ownership copies at every public/resource exit.
	if trusted_package and trusted_metadata_reuse_enabled:_seal_owned_containers(data)
	elif not _seal_decoded(data,0,[],[DECODE_MAX_VALUES]):return {}
	var geometry_keys:Array=[]
	if with_keys:
		for mesh:Dictionary in data.meshes:geometry_keys.append(Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[])))
	geometry_keys.make_read_only()
	var bounds:=_stored_local_bounds(data) if trusted_package and trusted_metadata_reuse_enabled else _local_bounds(data);bounds.make_read_only()
	var packet:={"issuer":_decode_issuer,"sha256":digest,"encoded":encoded,"length":length,"data":data,"geometry_keys":geometry_keys,"geometry_ready":with_keys,"local_bounds":bounds,"verified":not trusted_package}
	packet.make_read_only()
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
	if preload("res://scripts/world3d/runtime_package_policy.gd").trusted():return true
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
	var packet:=_decode_packet(record.house_prefab,true)
	if packet.is_empty():return {}
	var data:Dictionary=packet.data
	var faces:Array=[];var keys:Array=packet.geometry_keys;var canonical_slots:=0
	for mesh_id:int in data.meshes.size():
		if collision_candidates.has(mesh_id):
			# A candidate is private CPU data only. The enclosing reference worker
			# must still pass its final source/closure gate before this packet can
			# reach publish_prepared and receive a typed sealed collision product.
			faces.append(collision_candidates[mesh_id].faces);continue
		if packet.has("collision_faces"):
			faces.append(packet.collision_faces[mesh_id].duplicate());canonical_slots+=1;continue
		faces.append(preload("res://scripts/world3d/prefab_face_arrays.gd").build(data.meshes[mesh_id],native_unindexed_faces_enabled))
	# A worker result is owned by its admitted job. Its packed arrays must not
	# alias the canonical cache even though no production consumer edits them.
	var owned_data:Dictionary=data.duplicate(true)
	if preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and trusted_metadata_reuse_enabled:_seal_owned_containers(owned_data)
	elif not _seal_decoded(owned_data,0,[],[DECODE_MAX_VALUES]):return {}
	var vertices:=0
	for triangles:PackedVector3Array in faces:vertices+=triangles.size()
	return {"sha256":packet.sha256,"data":owned_data,"geometry_keys":keys,"collision_faces":faces,"face_work":{"prepared_slots":faces.size(),"skipped_slots":0,"canonical_slots":canonical_slots,"prepared_vertices":vertices}}

static func publish_prepared(record:Dictionary,prepared:Dictionary,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null,texture_packet:Dictionary={},scope_state:Variant=null)->bool:
	var publication_started:=Time.get_ticks_usec()
	var materials:Array=[]
	if prepared.get("data") is Dictionary and prepared.data.get("materials") is Array:materials=prepared.data.materials
	var scope:=begin_texture_publication(record,material_pool,texture_packet,scope_state,materials)
	if not scope.ok:return false
	var result:=_publish_prepared(record,prepared,paint_validation,material_pool,timings)
	end_texture_publication(scope)
	preload("res://scripts/world3d/load_trace.gd").elapsed("prefab_pixels.publish",publication_started,{"uuid":record.get("uuid",""),"images":texture_packet.get("images",{}).size(),"parts_ms":timings if timings!=null else {}})
	return result

static func begin_texture_publication(record:Dictionary,material_pool:Variant,texture_packet:Dictionary,state:Variant=null,materials:Array=[])->Dictionary:
	# Installation and resource caches are main-thread-only. Scope the supplied
	# CPU images or completed textures to one synchronous publication/material
	# slice. The matching end restores the prior scope; the job retains its lease.
	var previous:Variant=null
	var resident:Dictionary=texture_packet.get("resident_textures",{})
	if not tickets_valid(resident,texture_packet.get("sources",{})):return {"ok":false}
	var previous_uploaded:Dictionary=Cook.Paint.prepared_textures
	Cook.Paint.prepared_textures=texture_packet.get("uploaded_textures",{})
	var resources:Dictionary=texture_packet.get("images",{})
	if not Cook.Paint.prepared_textures.is_empty():
		if resources.is_empty():resources=Cook.Paint.prepared_textures
		else:
			resources=resources.duplicate()
			for key:String in Cook.Paint.prepared_textures:
				if not resources.has(key):resources[key]=Cook.Paint.prepared_textures[key]
	if state!=null and _texture_scope_current(record,texture_packet,state,material_pool,materials,resources):
		# The first slice already invalidated older generations. Missing GPU
		# entries mean this packet has work left, not another source replacement.
		# Keep only the synchronous Image handoff; do not sweep all render caches.
		previous=Cook.Paint.prepared_images
		Cook.Paint.prepared_images=texture_packet.get("images",{}).duplicate()
		state.reuses=int(state.get("reuses",0))+1
		return {"ok":true,"previous":previous,"previous_uploaded":previous_uploaded}
	if not resident.is_empty():
		var source_ids:Dictionary=texture_packet.sources
		var stale:Dictionary=_stale_material_keys(Cook.Paint._materials.values(),source_ids)
		if material_pool!=null:stale.merge(_stale_material_keys(material_pool.values(),source_ids),true)
		var entry:Dictionary=_meshes.get(record.get("house_prefab",{}).get("sha256",""),{})
		for name_:String in ["mesh","source"]:
			if entry.has(name_):stale.merge(_stale_material_keys(entry[name_].materials,source_ids),true)
		if not stale.is_empty():
			invalidate_texture_materials(stale);Cook.Paint._materials.clear()
			if material_pool!=null:material_pool.clear()
	# A ticket is an existing immutable GPU object, never an Image manufactured
	# on the worker. Restore evicted LRU entries without reading/uploading pixels.
	for key:String in resident:
		if not Cook.Paint._textures.has(key):
			Cook.Paint.remember_texture_owner(key,resident[key].texture)
	if not resources.is_empty():
		# Cook's caller-owned pool can outlive a texture's small global LRU too.
		# Its old materials must not bypass the image-generation invalidation.
		if material_pool!=null:
			# Hot-cache eviction is not a source replacement: live materials may
			# still own the exact verified texture. Invalidate actual old versions.
			if not _stale_material_keys(material_pool.values(),texture_packet.get("sources",{}),resources).is_empty():material_pool.clear()
		previous=load("res://scripts/world_editor/terrain_texture_preparation.gd").install({"images":texture_packet.get("images",{}),"uploaded_textures":Cook.Paint.prepared_textures,"failed":[]})
	if state!=null:
		state.sources=texture_packet.get("sources",{}).duplicate()
		state.representations={}
		for key:String in resources:
			var representation:String=resources[key].get_meta("runtime_texture_representation","")
			if not representation.is_empty():state.representations[key]=representation
		state.initialized=true;state.initializations=int(state.get("initializations",0))+1
	return {"ok":true,"previous":previous,"previous_uploaded":previous_uploaded}

static func _texture_scope_current(record:Dictionary,packet:Dictionary,state:Dictionary,material_pool:Variant,materials:Array,resources:Dictionary)->bool:
	if not state.get("initialized",false) or state.get("sources",{})!=packet.get("sources",{}):return false
	# A resident-only packet has no Images to expose a changed weak-cache owner.
	# Reinstall its valid immutable tickets if the catalogue no longer resolves
	# to their generation; the ordinary hot-owner rejection still runs above.
	for key:String in packet.get("resident_textures",{}):
		var texture:Texture2D=Cook.Paint._textures.get(key)
		if texture==null and Cook.Paint._texture_refs.has(key):texture=Cook.Paint._texture_refs[key].get_ref()
		if texture==null or texture.get_meta("runtime_source_sha256","")!=packet.resident_textures[key].source_sha:return false
	# Another publication may have replaced a source between slices. Re-enter
	# the full invalidation protocol only for an actually different live owner.
	for key:String in resources:
		# A new representation can share the source digest even after all hot
		# owners evict. Keep only scalar identity in slice state, never resources.
		if state.get("representations",{}).get(key,"")!=resources[key].get_meta("runtime_texture_representation",""):return false
		var texture:Texture2D=Cook.Paint._textures.get(key)
		if texture==null and Cook.Paint._texture_refs.has(key):texture=Cook.Paint._texture_refs[key].get_ref()
		if texture!=null and not Cook.Paint._same_prepared_texture(texture,resources[key]):return false
	# A cache catalogue may be empty while actual materials still own another
	# generation. Inspect only this target's live owners, never all map caches.
	if material_pool!=null:
		for slot:Dictionary in materials:
			if material_pool.has([slot]) and not _stale_material_keys([material_pool[[slot]]],state.sources,resources).is_empty():return false
	var entry:Dictionary=_meshes.get(record.get("house_prefab",{}).get("sha256",""),{})
	for field:String in ["mesh","source"]:
		if entry.has(field) and not _stale_material_keys(entry[field].materials,state.sources,resources).is_empty():return false
	return true

static func end_texture_publication(scope:Dictionary)->void:
	if scope.get("previous")!=null:load("res://scripts/world_editor/terrain_texture_preparation.gd").restore(scope.previous)
	if scope.has("previous_uploaded"):Cook.Paint.prepared_textures=scope.previous_uploaded

static func _publish_prepared(record:Dictionary,prepared:Dictionary,paint_validation:Variant=null,material_pool:Variant=null,timings:Variant=null)->bool:
	# Main-thread resource/material publication only. Never place this packet in
	# an authored record or serialize it; it belongs to the scheduler lease.
	var profile_mark:int=Time.get_ticks_usec() if timings!=null else 0
	var key:String=record.house_prefab.sha256
	if _meshes.has(key):
		# geometry() or an earlier source-only publication may have installed
		# this owner without all prepared faces. A cache hit must still accept
		# later worker output instead of leaving CPU expansion to its next user.
		if prepared_face_handoff_enabled and prepared.get("sha256")==key:_install_prepared_faces(_meshes[key],prepared)
		if timings!=null:timings.geometry_cache_hit=true
		return true
	if prepared.get("sha256")!=key or not prepared.get("data") is Dictionary:return false
	var data:Dictionary=prepared.data
	if prepared.get("geometry_keys",[]).size()!=data.meshes.size() or prepared.get("collision_faces",[]).size()!=data.meshes.size():return false
	var restored:=Cook.restore(data.duplicate(),paint_validation,material_pool,timings)
	if timings!=null:timings.cook_restore_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	if restored.is_empty():return false
	var entry:Dictionary=restored.values()[0]
	if not prepared_face_handoff_enabled:
		var render_id:int=data.entries[0][1][0];var source_id:int=data.entries[0][1][1]
		entry.mesh._collision_faces=prepared.collision_faces[render_id]
		entry.source._collision_faces=prepared.collision_faces[source_id]
		for row:Array in [[entry.mesh,render_id],[entry.source,source_id]]:
			var product:Variant=prepared.get("collision_products",{}).get(row[1])
			if product is CollisionProducts.Product and not product.kind().is_empty():row[0].set_meta("runtime_collision_product",product)
	_cache_geometry(key,entry,prepared.geometry_keys,data)
	if timings!=null:timings.render_identity_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	# Canonicalization can replace the render owner with a shared alias. Install
	# on the surviving object, never on the temporary mesh it replaced.
	if prepared_face_handoff_enabled:_install_prepared_faces(entry,prepared)
	if timings!=null:timings.collision_handoff_ms=(Time.get_ticks_usec()-profile_mark)/1000.
	return true

static func _install_prepared_faces(entry:Dictionary,prepared:Dictionary)->void:
	var data:Dictionary=prepared.get("data",{})
	var faces:Array=prepared.get("collision_faces",[]);var keys:Array=prepared.get("geometry_keys",[])
	if data.is_empty() or faces.size()!=data.meshes.size() or keys.size()!=data.meshes.size():return
	for row:Array in [[entry.mesh,int(data.entries[0][1][0])],[entry.source,int(data.entries[0][1][1])]]:
		var mesh:Mesh=row[0];var slot:int=row[1]
		# Reuse the already assigned immutable identity; never hash on main.
		if mesh.get_meta("static_batch_geometry_signature","")!=keys[slot]:continue
		if mesh._collision_faces.is_empty() and not faces[slot].is_empty():mesh._collision_faces=faces[slot]
		var product:Variant=prepared.get("collision_products",{}).get(slot)
		if product is CollisionProducts.Product and not product.kind().is_empty():mesh.set_meta("runtime_collision_product",product)

static func _cache_geometry(key:String,entry:Dictionary,geometry_keys:Array,data:Dictionary)->void:
	if geometry_keys.size()==data.meshes.size():
		entry.mesh.set_geometry_key(geometry_keys[data.entries[0][1][0]])
		entry.source.set_geometry_key(geometry_keys[data.entries[0][1][1]])
	var owner_key:Array=[entry.mesh.geometry_key()]
	for material:Material in entry.mesh.materials:owner_key.append(material.get_instance_id() if material!=null else 0)
	var alias:Dictionary=_render_owner_aliases.get(owner_key,{}) if material_owner_reuse_enabled else {}
	var existing:Variant=alias.reference.get_ref() if not alias.is_empty() else null
	# Identical material objects have identical live state, even if a caller has
	# edited them. No cached property values or changed-signal assumptions are
	# involved. The canonical cache must still own this exact mesh generation.
	if existing!=null and _render_meshes.get(alias.render_key)==existing and existing.materials==entry.mesh.materials:
		entry.mesh=existing;material_identity_reuses+=1
	else:
		material_identity_scans+=1
		var identity:Array=[]
		for material:Material in entry.mesh.materials:identity.append(Cook.material_data(material))
		var render_key:String=entry.mesh.geometry_key()+var_to_str(identity).sha256_text()
		if _render_meshes.has(render_key):entry.mesh=_render_meshes[render_key]
		else:
			if _render_meshes.size()>=512:_render_meshes.erase(_render_meshes.keys()[0])
			_render_meshes[render_key]=entry.mesh
		if material_owner_reuse_enabled:
			if _render_owner_aliases.size()>=512:_render_owner_aliases.erase(_render_owner_aliases.keys()[0])
			_render_owner_aliases[owner_key]={"render_key":render_key,"reference":weakref(entry.mesh)}
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
