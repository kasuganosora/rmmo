extends "res://tools/test_house_geometry_identity_reuse.gd"
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
func run()->void:
	Policy.verify_packages=false
	var data:=fixture();var mesh:Dictionary=data.meshes[0];data.meshes=[]
	for i:int in 220:
		var local:Dictionary=mesh.duplicate(true);var points:=PackedVector3Array()
		for n:int in 600:points.append(Vector3(i+n%3,0,-float(n%17)))
		local.surfaces[0][Mesh.ARRAY_VERTEX]=points;local.surfaces[0][Mesh.ARRAY_INDEX]=null
		local.bounds=AABB(Vector3(i,0,-16),Vector3(2,0,16));data.meshes.append(local)
	data.meshes[3].box_size=Vector3(5,8,9)
	var value:=encode(data);var r:=record(value);var reports:Array=[];var expected:Dictionary={}
	for reuse:bool in [false,true,true,false]:
		House.trusted_metadata_reuse_enabled=reuse;House.native_unindexed_faces_enabled=reuse;evict(value.sha256)
		var started:=Time.get_ticks_usec();var packet:=House._decode_packet(value);var decode_us:=Time.get_ticks_usec()-started
		if expected.is_empty():expected=packet
		check(var_to_bytes(packet.data)==var_to_bytes(expected.data) and packet.geometry_keys==expected.geometry_keys and packet.local_bounds.bounds.encloses(expected.local_bounds.bounds),"trusted metadata preserves exact geometry/identity and contains actual bounds")
		check(all_sealed(packet),"all nested canonical containers remain sealed")
		started=Time.get_ticks_usec();var prepared:=House.prepare_cpu(r);var prepare_us:=Time.get_ticks_usec()-started
		check(all_sealed(prepared.data) and not is_same(prepared.data,packet.data),"CPU job receives its own sealed data")
		var exact:=true
		for i:int in data.meshes.size():exact=exact and prepared.collision_faces[i]==data.meshes[i].surfaces[0][Mesh.ARRAY_VERTEX]
		check(exact,"native unindexed face copies preserve exact triangle order")
		var public_copy:=House.decode(value)
		var positions:PackedVector3Array=public_copy.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX];positions[0]=Vector3(1000,0,1000)
		var job_positions:PackedVector3Array=prepared.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX];job_positions[0]=Vector3(2000,0,2000)
		check(packet.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ZERO,"public/job packed-array edits cannot mutate canonical ownership")
		reports.append({"reuse":reuse,"decode_us":decode_us,"prepare_us":prepare_us,"vertex_bounds_tests":0 if reuse else 132000})
	# The fast freezer also handles repeated private containers and container
	# keys without revisiting each shared child or changing serialized values.
	var shared:Array=[{"deep":[1,2,3]}];var complex:Dictionary={"one":shared,"two":shared,["key"]:{"child":[4]}}
	var before:=var_to_bytes(complex);House._seal_owned_containers(complex)
	check(all_sealed(complex) and var_to_bytes(complex)==before,"shared nested containers and container keys stay intact and frozen")
	House.trusted_metadata_reuse_enabled=true;House.native_unindexed_faces_enabled=true
	var mixed:=fixture();mixed.meshes[0].surfaces.append(mixed.meshes[0].surfaces[0].duplicate(true));mixed.meshes[0].surfaces[1][Mesh.ARRAY_INDEX]=PackedInt32Array()
	var mixed_record:=record(encode(mixed));House.native_unindexed_faces_enabled=false;var old_faces:Array=House.prepare_cpu(mixed_record).collision_faces
	House.native_unindexed_faces_enabled=true
	check(House.prepare_cpu(mixed_record).collision_faces==old_faces,"mixed indexed/unindexed surfaces retain the same face order")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):real_bounds(arg.trim_prefix("--map="))
	print("TRUSTED_PREFAB_METADATA ",JSON.stringify({"trials":reports,"failures":failures}));quit(1 if failures else 0)
func real_bounds(path:String)->void:
	var before:=FileAccess.get_sha256(path);var map_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));var seen:Dictionary={};var sources:Dictionary={};var tested:=0;var max_delta:=0.;var unindexed_vertices:=0;var indexed_vertices:=0
	for row:Dictionary in map_data.nodes[0].extras.rmmo_records:
		var definition:Dictionary=row
		if row.has("rmmo_ref"):
			var source_path:=path.get_base_dir().path_join(row.rmmo_ref.uri)
			if sources.has(source_path):continue
			var bytes:=FileAccess.get_file_as_bytes(source_path);sources[source_path]=hash_bytes(bytes)
			definition=bytes_to_var(bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD))
		if not definition.has("house_prefab") or seen.has(definition.house_prefab.sha256):continue
		seen[definition.house_prefab.sha256]=true
		var packet:=House._decode_packet(definition.house_prefab)
		var actual:=House._local_bounds(packet.data)
		# Source AABBs are conservative after transformed meshes are merged.
		# Verify containment, including the producer's vertex quantization, rather
		# than claiming that conservative and tight bounds are identical.
		var delta:Vector3=(actual.bounds.position-packet.local_bounds.bounds.position).abs().max((actual.bounds.end-packet.local_bounds.bounds.end).abs())
		max_delta=maxf(max_delta,maxf(delta.x,maxf(delta.y,delta.z)))
		check(actual.known==packet.local_bounds.known and packet.local_bounds.bounds.encloses(actual.bounds),"real stored bounds contain all actual geometry "+row.uuid);tested+=1
		for mesh:Dictionary in packet.data.meshes:
			for arrays:Array in mesh.surfaces:
				if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty():indexed_vertices+=arrays[Mesh.ARRAY_VERTEX].size()
				else:unindexed_vertices+=arrays[Mesh.ARRAY_VERTEX].size()
	check(tested>0 and FileAccess.get_sha256(path)==before,"real map covered without changing authored bytes")
	var unchanged:=true
	for source_path:String in sources:unchanged=unchanged and FileAccess.get_sha256(source_path)==sources[source_path]
	check(unchanged,"all referenced sources unchanged")
	print("REAL_PREFAB_METADATA ",JSON.stringify({"unique_payloads":tested,"max_bounds_delta_m":max_delta,"unindexed_vertices":unindexed_vertices,"indexed_vertices":indexed_vertices}))
