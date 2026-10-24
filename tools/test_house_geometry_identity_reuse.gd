extends SceneTree
## Immutable decode identities and CPU handoff; optional --map reads real frozen
## bridge/house resources without preparing textures or changing authored files.
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Prepare=preload("res://scripts/world3d/chunk_reference_preparation.gd")
class Cancelled extends RefCounted:
	func is_cancelled()->bool:return true
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func hash_bytes(bytes:PackedByteArray)->String:return Cook.Envelope.checksum(bytes).hex_encode()
func encode(data:Dictionary)->Dictionary:
	var bytes:=var_to_bytes(data)
	return {"version":1,"sha256":hash_bytes(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
func fixture()->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	return {"materials":[{"values":{"albedo_color":Color(.7,.2,.1),"roughness":.8}}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":AABB(Vector3(0,0,-1),Vector3(1,0,1)),"box_size":Vector3.ZERO}],"entries":[[["fixture"],[0,0]]]}
func record(value:Dictionary,id:String="fixture")->Dictionary:
	return {"uuid":id,"kind":"box","surface_id":"block","collision":"block","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"house_prefab":value}
func all_sealed(value:Variant)->bool:
	if value is Dictionary:
		if not value.is_read_only():return false
		for key in value:
			if not all_sealed(key) or not all_sealed(value[key]):return false
	elif value is Array:
		if not value.is_read_only():return false
		for child in value:
			if not all_sealed(child):return false
	return true
func evict(digest:String)->void:
	House._decode_mutex.lock()
	if House._decoded.has(digest):House._decoded_bytes-=House.retained_decode_bytes(House._decoded[digest]);House._decoded.erase(digest)
	House._decode_mutex.unlock()
func prepared_keys_valid(prepared:Dictionary)->bool:
	if prepared.is_empty():return false
	for i in prepared.data.meshes.size():
		if prepared.geometry_keys[i]!=hash_bytes(var_to_bytes(prepared.data.meshes[i].surfaces)):return false
	return true

func run()->void:
	# This fixture deliberately corrupts encoded bytes/digests. Ordinary package
	# loads trust authored identities; authenticate only this diagnostic test.
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
	create_timer(90).timeout.connect(func():quit(2))
	var data:=fixture();var value:=encode(data);var r:=record(value)
	var packet:=House._decode_packet(value)
	check(not packet.is_empty() and all_sealed(packet),"decode packet and every nested data/key container are read-only")
	check(House.warm(value) and House.source_slot(value)==0 and is_same(House._decode_packet(value),packet),"metadata and warm queries reuse validated packet without returning geometry")
	var local:=House.local_bounds(value)
	check(local.size()==2 and local.known and local.bounds==AABB(Vector3(0,0,-1),Vector3(1,0,1)),"local bounds query returns only actual geometry math values")
	local.bounds=AABB(Vector3(999,999,999),Vector3.ONE)
	check(House.local_bounds(value).bounds==AABB(Vector3(0,0,-1),Vector3(1,0,1)),"caller editing a metadata result cannot change cached geometry or next bounds")
	var misleading:=data.duplicate(true);misleading.meshes[0].bounds=AABB(Vector3(999,999,999),Vector3.ONE)
	check(House.local_bounds(encode(misleading)).bounds==AABB(Vector3(0,0,-1),Vector3(1,0,1)),"bounds query does not trust forged stored mesh bounds")
	var primitive:=data.duplicate(true);primitive.meshes[0].box_size=Vector3(4,6,8)
	check(House.local_bounds(encode(primitive)).bounds==AABB(Vector3(-2,-3,-4),Vector3(4,6,8)),"bounds query includes independent box collision extent")
	var invalid_points:=data.duplicate(true);invalid_points.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]=Vector3(INF,0,0)
	check(not House.local_bounds(encode(invalid_points)).known,"bounds query rejects non-finite actual vertices")
	var public_data:=House.decode(value)
	check(not is_same(public_data,packet.data) and not public_data.is_read_only() and var_to_bytes(public_data)==var_to_bytes(data),"legacy decode API returns a writable owned copy without serialized derived keys")
	var prepared:=House.prepare_cpu(r)
	check(prepared_keys_valid(prepared) and not is_same(prepared.data,packet.data) and is_same(prepared.geometry_keys,packet.geometry_keys),"prepare reuses exact immutable keys with separately owned geometry data")
	var packed:PackedVector3Array=public_data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX]
	packed[0]=Vector3(9,9,9)
	check(packet.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ZERO and prepared.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ZERO,"public packed channel writes cannot mutate canonical or another job's geometry")
	var isolated:=House.prepare_cpu(r)
	var exposed:PackedVector3Array=isolated.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX]
	exposed[0]=Vector3(2,2,2)
	check(packet.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ZERO and prepared_keys_valid(House.prepare_cpu(r)),"prepared job packed arrays never expose canonical cache buffers")
	var edited:Dictionary=packet.data.duplicate(true)
	edited.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX]=packed
	edited.materials[0]["values"].roughness=.3
	check(not edited.is_read_only() and not edited.meshes.is_read_only() and not edited.meshes[0].surfaces[0].is_read_only(),"editable deep duplicates remain writable at all levels")
	var changed_value:=encode(edited);var changed:=House.prepare_cpu(record(changed_value,"changed"))
	check(prepared_keys_valid(changed) and changed.geometry_keys!=prepared.geometry_keys and prepared.data.materials[0]["values"].roughness==.8,"edited geometry receives a new identity without changing old material or arrays")
	var bad:=value.duplicate();bad.data=changed_value.data;bad.length=changed_value.length
	check(House.decode(bad).is_empty(),"same claimed SHA with changed encoding cannot inherit cached proof")
	bad=value.duplicate();bad.length+=1
	check(House.decode(bad).is_empty(),"changed raw length still undergoes full identity validation")
	bad=value.duplicate();bad.sha256="0".repeat(64)
	check(House.decode(bad).is_empty(),"wrong digest never produces a geometry packet")
	check(not House.warm(bad) and House.source_slot(bad)==-1 and not House.local_bounds(bad).known,"all metadata APIs still reject an invalid source identity")
	check(is_same(House._decode_packet(value),packet),"failed variants leave valid cached packet intact")
	# Simulate a legacy/hot-reload entry whose dictionary has been edited after
	# decoding. Matching encoded bytes and SHA do not make it safe to reuse.
	evict(value.sha256)
	House._decode_mutex.lock()
	House._decoded[value.sha256]={"encoded":value.data,"length":value.length,"data":edited,"geometry_keys":["stale"]};House._decoded_bytes+=value.length
	House._decode_mutex.unlock()
	var repaired:=House._decode_packet(value)
	check(all_sealed(repaired) and var_to_bytes(repaired.data)==var_to_bytes(data) and repaired.geometry_keys==packet.geometry_keys,"unsealed legacy cache entry is redecoded and validated instead of trusted")
	evict(value.sha256)
	check(prepared_keys_valid(prepared) and all_sealed(prepared.data),"in-flight prepared packet retains its verified identities after cache eviction")
	check(House._publish_prepared(r,prepared,{},{}),"main-thread CPU/material publication works after decoded cache eviction")
	var next_packet:=House._decode_packet(value)
	check(not is_same(next_packet,packet) and next_packet.geometry_keys==packet.geometry_keys,"later decode may own another packet without changing retained data")
	var colors:=data.duplicate(true);colors.materials[0]["values"].albedo_color=Color(.1,.2,.7)
	var color_value:=encode(colors);var color_record:=record(color_value,"blue")
	var red_geometry:=House.geometry(r);var blue_geometry:=House.geometry(color_record)
	check(red_geometry.mesh.geometry_key()==blue_geometry.mesh.geometry_key() and red_geometry.mesh!=blue_geometry.mesh,"shared geometry identity does not merge different materials")
	check(red_geometry.mesh.materials[0].albedo_color==Color(.7,.2,.1) and blue_geometry.mesh.materials[0].albedo_color==Color(.1,.2,.7),"separate prefab material colors survive immutable restore")
	var resource_positions:PackedVector3Array=blue_geometry.mesh.surfaces[0][Mesh.ARRAY_VERTEX]
	resource_positions[0]=Vector3(3,3,3)
	check(House.decode(color_value).meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ZERO,"restored CpuMesh cannot mutate signature-bearing canonical arrays")
	var plain:=Cpu.new();plain.surfaces=data.meshes[0].surfaces.duplicate(true)
	check(not plain.has_meta("static_batch_geometry_signature") and plain.geometry_key()==hash_bytes(var_to_bytes(plain.surfaces)),"ordinary non-frozen CpuMesh still hashes its own current surfaces")
	var doc:=Doc.new();doc.load_immutable_records=true;doc.load_texture_checks={}
	var timing:Dictionary={};var visual:MeshInstance3D=doc._mesh(r,true,timing)
	check(visual.mesh is Cpu and timing.get("geometry_cache_hit",false) and timing.has("gpu_restore_ms") and timing.has("node_metadata_ms") and timing.has("prefab_visual_ms") and timing.has("texture_validation_ms"),"WorldDocument forwards prefab stages and records post-prefab texture validation separately")
	visual.free()
	# Same-payload racing misses must publish one immutable owner, while another
	# material payload retains its own data and keys. No renderer calls in workers.
	evict(value.sha256);evict(color_value.sha256)
	var workers:Array=[]
	for i in 6:
		var worker:=Thread.new();check(worker.start(House.prepare_cpu.bind(r if i%2==0 else color_record))==OK,"CPU worker starts "+str(i));workers.append(worker)
	var packets:Array=[]
	for worker:Thread in workers:packets.append(worker.wait_to_finish())
	check(packets.all(func(p):return prepared_keys_valid(p) and all_sealed(p.data)),"concurrent CPU preparation returns sealed matching geometry")
	check(is_same(packets[0].geometry_keys,packets[2].geometry_keys) and is_same(packets[2].geometry_keys,packets[4].geometry_keys) and is_same(packets[1].geometry_keys,packets[3].geometry_keys) and not is_same(packets[0].geometry_keys,packets[1].geometry_keys) and not is_same(packets[0].data,packets[2].data),"concurrent jobs share one identity generation while owning separate packed geometry")
	var cache_before:=House._decoded_bytes
	var cancelled:=Prepare.prepare({},[],"","",Cancelled.new())
	check(cancelled.cancelled and cancelled.records.is_empty() and House._decoded_bytes==cache_before,"cancelled reference transaction still exits before preparing or publishing records")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):check_real(arg.trim_prefix("--map="))
	print("HOUSE_GEOMETRY_IDENTITY_REUSE checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func check_real(path:String)->void:
	var before:=FileAccess.get_sha256(path)
	var map_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var records:Array=map_data.nodes[0].extras.rmmo_records
	for uuid:String in ["stone_e_0be972769041dbc9","obj_3828"]:
		var selected:Array=records.filter(func(r):return r.get("uuid","")==uuid)
		check(selected.size()==1,"real frozen record exists "+uuid)
		if selected.size()!=1:continue
		var row:Dictionary=selected[0];var reference:Dictionary=row.rmmo_ref
		var source_path:=path.get_base_dir().path_join(reference.uri)
		var bytes:=FileAccess.get_file_as_bytes(source_path)
		check(bytes.size()==int(reference.length) and hash_bytes(bytes)==reference.sha256,"real rmres identity "+uuid)
		if bytes.size()!=int(reference.length) or hash_bytes(bytes)!=reference.sha256:continue
		var raw:=bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD)
		var definition:Dictionary=bytes_to_var(raw)
		var record_:Dictionary=definition.duplicate(true)
		for key:String in ["uuid","position","rotation","size"]:record_[key]=row[key]
		record_.merge(row.get("rmmo_state",{}),true)
		var actual:=House.prepare_cpu(record_)
		check(prepared_keys_valid(actual) and all_sealed(actual.data),"real frozen render/source keys exactly match original arrays "+uuid)
		var uncompressed:=Marshalls.base64_to_raw(definition.house_prefab.data).decompress(int(definition.house_prefab.length),FileAccess.COMPRESSION_ZSTD)
		check(var_to_bytes(actual.data)==uncompressed,"real serialized frozen payload remains byte-exact "+uuid)
		var candidates:Dictionary={}
		for i in actual.collision_faces.size():candidates[i]={"faces":actual.collision_faces[i]}
		var repeated_hash_us:Array=[];var warm_prepare_us:Array=[]
		for _round in 4:
			var began:=Time.get_ticks_usec();var keys:Array=[]
			for mesh:Dictionary in actual.data.meshes:keys.append(hash_bytes(var_to_bytes(mesh.surfaces)))
			repeated_hash_us.append(Time.get_ticks_usec()-began)
			began=Time.get_ticks_usec();var warm:=House.prepare_cpu(record_,candidates);warm_prepare_us.append(Time.get_ticks_usec()-began)
			check(warm.geometry_keys==keys and is_same(warm.geometry_keys,actual.geometry_keys),"real warm preparation borrows same keys "+uuid)
		print("REAL_IDENTITY_MICRO ",JSON.stringify({"uuid":uuid,"repeat_hash_us":repeated_hash_us,"warm_prepare_with_existing_faces_us":warm_prepare_us}))
		check(FileAccess.get_sha256(source_path)==reference.sha256,"real resource unchanged "+uuid)
	check(FileAccess.get_sha256(path)==before,"formal map unchanged by CPU identity probe")
