extends SceneTree
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Preparation=preload("res://scripts/world3d/channel_mesh_preparation.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Probe=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(id:String)->Dictionary:
	return {"uuid":id,"kind":"box","surface_id":"water","collision":"none","position":[2,0,3],"rotation":[0,17,0],"size":[23.9999997,.19999999,17.0000001],"color":[.2,.4,.3],"channel_mesh":{"uv_origin":[12.0000003,0,-17.0000003],"polygons":[[[-.499999994,-.499999994],[.499999994,-.499999994],[.499999994,.499999994],[-.499999994,.499999994]]]},"water_depth_effect":{"absorption":.45,"shallow_color":[.24,.42,.34],"deep_color":[.055,.16,.14]}}
func material_values(material:Material)->Array:
	if material is StandardMaterial3D:return [material.albedo_color,material.roughness,material.metallic,material.cull_mode,material.transparency,material.shading_mode]
	return [material]
func run()->void:
	create_timer(100).timeout.connect(func():quit(2))
	var legacy_path:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/channel_surface_before_worker_arrays.gd"
	var doc_path:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/world_document_before_channel_arrays.gd"
	var legacy:Script=load(legacy_path) if FileAccess.file_exists(legacy_path) else Channel
	var old_doc:Script=load(doc_path) if FileAccess.file_exists(doc_path) else Doc
	var a:=fixture("a");var b:=fixture("b");b.size[0]=32.
	b.terrain_material={"name":"unused channel terrain slot","color":[.9,.1,.2,1],"roughness":.8,"tile_size":[2,2]}
	var records:Array=[a,b];var before:=var_to_bytes(records);var context:=Neighbors.new()
	var worker:=Thread.new();check(worker.start(Preparation.prepare.bind(records,context,{}))==OK,"channel CPU arrays run on an actual worker")
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish()
	check(prepared.size()==2 and var_to_bytes(records)==before,"worker prepares every uncached channel without mutating source records")
	var source:Mesh=legacy.mesh(a,StandardMaterial3D.new())
	check(prepared.a==source.get_meta("ground_cpu_cache").surfaces,"canonical decimal positions, normal/tangent/UV/index channels equal the previous actual slab builder")
	source=null
	var key:Array=["channel_mesh",a,{}];var keys:=Preparation.cached_keys({"entries":[[key,[0,0]]]})
	check(Preparation.prepare(records,context,keys).keys()==["b"],"a cached terrain context still prepares the missing channel geometry")
	var changed:=a.duplicate(true);changed.size[0]+=1
	check(Preparation.prepare([changed],context,keys).has("a"),"same UUID with changed map geometry cannot reuse the old channel key")
	context.data.a={"normals":{"changed":true}}
	check(Preparation.prepare([a],context,keys).has("a"),"changed preparation context cannot reuse stale geometry")
	for field:String in ["fortification_art","water_gate","building_shape"]:
		var special:=a.duplicate(true);special[field]="wall_grid" if field=="building_shape" else {}
		check(not Preparation.supports(special) and Preparation.prepare([special],context,{}).is_empty(),"channel polygons used by "+field+" never replace their actual builder")
	var baseline:RefCounted=old_doc.new();baseline.load_immutable_records=true
	var document:=Doc.new();document.load_immutable_records=true;document.load_surface_arrays=prepared
	for record:Dictionary in records:
		var control:MeshInstance3D=baseline._mesh(record)
		var actual:MeshInstance3D=document._mesh(record)
		var control_cpu:Mesh=Cpu.capture(control.mesh)
		check(actual.mesh is Cpu and actual.mesh.surfaces==control_cpu.surfaces,"immutable water indexing uses the exact prepared CPU mesh instead of a disposable GPU upload")
		check(actual.transform==control.transform and actual.get_meta("extras")==control.get_meta("extras") and actual.cast_shadow==control.cast_shadow,"prepared water preserves world pose, collision/landscape role and shadow behavior")
		check(actual.mesh.get_aabb().is_equal_approx(control.mesh.get_aabb()) and actual.mesh.collision_faces()==control_cpu.collision_faces(),"prepared bounds and every original collision triangle equal the native rendered slab")
		var equal:=true
		for slot:int in actual.mesh.get_surface_count():equal=equal and material_values(actual.mesh.surface_get_material(slot))==material_values(control.mesh.surface_get_material(slot))
		check(equal and actual.material_override==control.material_override,"prepared water preserves base roughness/metallic/culling and its material override")
		control.free();actual.free()
	check(var_to_bytes(records)==before,"document preparation keeps all source bytes and original polygons unchanged")
	print("CHANNEL_MESH_PREPARATION checks=",checks," failures=",failures);quit(1 if failures else 0)
