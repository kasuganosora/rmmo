extends SceneTree
## A tiny native product isolates package trust from source/loader behavior.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var root_path:=preload("res://scripts/world3d/map_paths.gd").cache_directory("white_native_policy_test").path_join(str(OS.get_process_id()))
	var folder:=Native.directory(root_path);DirAccess.make_dir_recursive_absolute(folder)
	# Native.read only needs the package source identity; this test deliberately
	# does not exercise GLTF parsing or claim to deliver an authored model.
	var source:=root_path.path_join("fixture.glb");var file:=FileAccess.open(source,FileAccess.WRITE);file.store_string("policy fixture source");file.close()
	var sha:=FileAccess.get_sha256(source);var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	# Godot accepts an LOD only when it has fewer indices than the base surface.
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,1])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{5.0:PackedInt32Array([0,2,1])});mesh.surface_set_material(0,Controls.white_material())
	var geometry_key:String=Cpu.capture(mesh).geometry_key()
	Native._store_geometry(mesh)
	check(mesh.get_meta(Native.META).get("geometry_key","")==geometry_key,"native writer persists the exact geometry identity before material removal")
	var node:=MeshInstance3D.new();node.mesh=mesh
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"tiny native packet packs")
	# A deliberately stale checksum differentiates trusted package reads from
	# explicit diagnostic authentication without corrupting executable resources.
	var digest:="0".repeat(64);var product:=folder.path_join(digest+".scn")
	check(ResourceSaver.save(packed,product,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"fixture native product saved")
	var info:={"generator":Native.generator(),"source_sha":sha,"payload_sha":digest,"bytes":FileAccess.open(product,FileAccess.READ).get_length()}
	file=FileAccess.open(Native.index_path(source,root_path),FileAccess.WRITE);file.store_string(JSON.stringify(info));file.close()
	var strict:=Native.read(source,sha,root_path,false)
	check(not strict.hit and strict.reason=="white_native_checksum","diagnostic mode still authenticates native product bytes")
	var trusted:=Native.read(source,sha,root_path,true)
	if "--expect-checksum" in OS.get_cmdline_user_args():check(not trusted.hit and trusted.reason=="white_native_checksum","baseline repeats product checksum even for a trusted package")
	else:
		check(trusted.hit,"trusted package reads the native product without a duplicate full-file SHA pass")
		if trusted.hit:
			var instance:MeshInstance3D=trusted.packed.instantiate()
			var cpu:Mesh=instance.mesh.get_meta("ground_cpu_cache")
			check(cpu.collision_faces()==PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector3.ZERO,Vector3.UP,Vector3.RIGHT]),"trusted native handoff retains exact CPU collision input")
			check(cpu.get_meta("static_batch_geometry_signature","")==geometry_key,"native read restores precomputed identity without first-use geometry serialization")
			check(geometry_key==Cpu.geometry_signature(cpu.surfaces,cpu.lods),"stored identity matches independently decoded geometry and LOD")
			check(cpu.lods[0].has(5.0) and geometry_key!=Cpu.geometry_signature(cpu.surfaces,[]),"different LOD tables cannot alias the same base geometry")
			var projected:Mesh=Controls.prepare_cpu_materials(cpu,[Controls.white_material(BaseMaterial3D.CULL_FRONT)])
			check(projected.get_meta("static_batch_geometry_signature","")==geometry_key,"material projection preserves the exact geometry identity")
			instance.free()
	node.free()
	print("WHITE_NATIVE_PRODUCT_POLICY failures=",failures);quit(1 if failures else 0)
