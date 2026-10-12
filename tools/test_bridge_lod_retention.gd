extends SceneTree
## Headless validates stored CPU geometry and offline derivation. --gpu also
## reads back actual restored renderer LOD buffers; run on the private desktop.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const Lod=preload("res://scripts/world3d/bridge_lod_preparation.gd")
const Gpu=preload("res://tools/bridge_lod_assertions.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
var passed:=0
var failed:=0
class Cancelled extends RefCounted:
	func is_cancelled()->bool:return true
class Errors extends Logger:
	var errors:Array[String]=[]
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:errors.append(function+": "+code+" "+rationale)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func fixture()->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array();var colors:=PackedColorArray();var indices:=PackedInt32Array()
	for z in 17:
		for x in 17:
			vertices.append(Vector3(x,0,z));normals.append(Vector3.UP);uv.append(Vector2(x,z)/16.);colors.append(Color(.6,.7,.8,1))
	for z in 16:
		for x in 16:
			var i:=z*17+x;indices.append_array(PackedInt32Array([i,i+17,i+1,i+1,i+17,i+18]))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	return {"materials":[{"null":true}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":AABB(Vector3.ZERO,Vector3(16,0,16)),"box_size":Vector3.ZERO}],"entries":[[[0],[0,0]]]}
func encoded(data:Dictionary)->Dictionary:
	var bytes:=var_to_bytes(data)
	return {"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
func frozen(data:Dictionary)->Dictionary:return {"uuid":"lod_fixture","house_prefab":encoded(data)}
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var original:=fixture();var original_bytes:=var_to_bytes(original)
	check(Cook.valid_data(original),"legacy frozen geometry without lods remains valid")
	var cpu:=Cpu.new();cpu.surfaces=original.meshes[0].surfaces;cpu.materials.append(null);cpu.bounds=original.meshes[0].bounds
	var old_key:=Cook.Envelope.checksum(var_to_bytes(cpu.surfaces)).hex_encode()
	check(cpu.geometry_key()==old_key and Cpu.geometry_signature(cpu.surfaces,[{}])==old_key,"no-LOD and explicit empty LODs retain the old exact geometry signature")
	var faces:=cpu.collision_faces().duplicate()
	var worker:=Thread.new();check(worker.start(Lod.derive_data.bind(original))==OK,"offline simplification starts as a CPU worker")
	while worker.is_alive():await process_frame
	var derived:Dictionary=worker.wait_to_finish()
	check(derived.get("ok",false) and derived.get("changed",false),"offline derivation adds real LOD buffers without changing the base arrays")
	if derived.get("ok",false) and derived.get("changed",false):
		var data:Dictionary=derived.data;var render:int=data.entries[0][1][0];var source:int=data.entries[0][1][1]
		check(render!=source and var_to_bytes(data.meshes[source])==var_to_bytes(original.meshes[0]),"shared old render/collision entry splits while the collision row remains byte-exact")
		check(var_to_bytes(data.meshes[render].surfaces)==var_to_bytes(original.meshes[0].surfaces) and data.materials==original.materials,"all base positions normals UV colors indices and material slots remain unchanged")
		check(Cook.valid_data(data) and data.meshes[render].lods[0].size()>0,"derived LOD schema validates and contains distance-index tables")
		var restored:Dictionary=Cook.restore(data.duplicate(true))[[0]]
		check(restored.mesh.lods==data.meshes[render].lods and restored.source.lods.is_empty(),"cooked restore retains visual LODs and legacy collision-only mesh")
		check(restored.mesh.collision_faces()==faces and restored.source.collision_faces()==faces,"render and source collision extraction always use exact base faces")
		var cache:Dictionary={};cache[[0]]=restored
		var repacked:=Cook.pack(cache,"","test")
		check(repacked.meshes[repacked.entries[0][1][0]].lods==data.meshes[render].lods,"cooked reserialization preserves every LOD distance and index buffer")
		var compact:=data.duplicate(true);var before:=var_to_bytes(compact.meshes[render]);House.compact_data(compact)
		check(var_to_bytes(compact.meshes[render])==before,"compaction cannot reindex a LOD surface without remapping its indices")
		var prepared:=House.prepare_cpu(frozen(data))
		check(prepared.geometry_keys[render]==restored.mesh.geometry_key() and prepared.geometry_keys[render]!=old_key and prepared.geometry_keys[source]==old_key,"immutable House identities include visual LOD data but preserve source/no-LOD identities")
		var changed:=data.duplicate(true);var distances:Array=changed.meshes[render].lods[0].keys();var key:float=distances[0]
		var held:PackedInt32Array=prepared.data.meshes[render].lods[0][key];held[0]=(held[0]+1)%289
		check(House.prepare_cpu(frozen(data)).data.meshes[render].lods[0][key]!=held,"worker-owned LOD packed buffers cannot mutate canonical decoded geometry")
		changed.meshes[render].lods[0][key*2.123]=changed.meshes[render].lods[0][key];changed.meshes[render].lods[0].erase(key)
		check(House.prepare_cpu(frozen(changed)).geometry_keys[render]!=prepared.geometry_keys[render],"equal base arrays with different LOD thresholds cannot share render identity")
		var different_indices:=data.duplicate(true);var alternate:PackedInt32Array=different_indices.meshes[render].lods[0][key].duplicate()
		alternate[0]=(alternate[0]+1)%289;different_indices.meshes[render].lods[0][key]=alternate
		check(Cook.valid_data(different_indices) and House.prepare_cpu(frozen(different_indices)).geometry_keys[render]!=prepared.geometry_keys[render],"equal base arrays and thresholds with different LOD indices cannot share render identity")
		check(not Lod.derive_data(data).changed and var_to_bytes(original)==original_bytes,"derivation is idempotent and never mutates the legacy input")
		for bad:Variant in ["bad",[{} ,{}],[{0.0:PackedInt32Array([0,1,2])}],[{INF:PackedInt32Array([0,1,2])}],[{1.0:PackedInt32Array([-1,1,2])}],[{1.0:PackedInt32Array([0,1,289])}],[{1.0:PackedInt32Array([0,1])}],[{1.0:PackedInt64Array([0,1,2])}]]:
			var invalid:=original.duplicate(true);invalid.meshes[0].lods=bad
			check(not Cook.valid_data(invalid),"malformed LOD schema rejected: "+str(bad).left(45))
		var excessive:Dictionary={}
		for i in 33:excessive[float(i+1)]=PackedInt32Array([0,1,2])
		var invalid:=original.duplicate(true);invalid.meshes[0].lods=[excessive]
		check(not Cook.valid_data(invalid),"LOD level count has a bounded validation/allocation contract")
		var cumulative:Dictionary={}
		for i in 16:cumulative[float(i+1)]=original.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]
		invalid=original.duplicate(true);invalid.meshes[0].lods=[cumulative]
		check(Cook.valid_data(invalid),"cumulative LOD indices allow the exact sixteen-base limit")
		cumulative[17.0]=original.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]
		check(not Cook.valid_data(invalid),"seventeen full-base LOD levels exceed the cumulative index limit even below the level-count cap")
		for distance:float in [1.0e-300,1.0e300]:
			invalid=original.duplicate(true);invalid.meshes[0].lods=[{distance:PackedInt32Array([0,1,2])}]
			check(not Cook.valid_data(invalid),"finite float64 threshold that becomes zero or infinity in float32 is rejected: "+str(distance))
		var collapsed:Dictionary={1.0:PackedInt32Array([0,1,2]),1.000000001:PackedInt32Array([2,1,0])}
		invalid=original.duplicate(true);invalid.meshes[0].lods=[collapsed]
		check(collapsed.size()==2 and not Cook.valid_data(invalid),"distinct float64 thresholds that collapse to one renderer threshold are rejected")
		var lod_bytes:=var_to_bytes(data.meshes[render].lods)
		check(Cook.valid_data(data) and var_to_bytes(data.meshes[render].lods)==lod_bytes,"normal ImporterMesh float32 thresholds and index buffers are validated without normalization")
		if "--gpu" in OS.get_cmdline_user_args():gpu_cases(data,changed)
	check(Lod.derive_data(original,Cancelled.new()).get("cancelled",false),"cancelled offline derivation cannot publish new geometry")
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	print("BRIDGE_LOD_RETENTION passed=",passed," failures=",failed);quit(1 if failed else 0)
func gpu_cases(data:Dictionary,changed:Dictionary)->void:
	check(DisplayServer.get_name()!="headless","GPU LOD verification requires a private renderer")
	if DisplayServer.get_name()=="headless":return
	var render:int=data.entries[0][1][0]
	var a:=House.geometry(frozen(data));var b:=House.geometry(frozen(changed))
	check(a.mesh!=b.mesh,"two real restored frozen payloads with different LODs never deduplicate")
	var gpu:Mesh=a.mesh.restore()
	check(Gpu.matches(gpu,data.meshes[render].lods),"actual GPU index buffers and thresholds match reopened frozen data")
	check(Cpu.capture(gpu).lods==data.meshes[render].lods,"restored GPU mesh retains the original CPU LOD owner without readback")
	var node:=MeshInstance3D.new();node.mesh=gpu;node.set_surface_override_material(0,StandardMaterial3D.new())
	Batch.freeze(node)
	check(node.mesh.lods==data.meshes[render].lods and Gpu.matches(node.mesh.restore(),data.meshes[render].lods),"per-instance material fork preserves LODs through editor freeze/restore")
	node.free();RenderingServer.force_sync()
