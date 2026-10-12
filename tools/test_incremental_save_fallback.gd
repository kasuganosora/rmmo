extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Materials=preload("res://scripts/world3d/surface_materials.gd")
var failed:=0
var directory:String
func _init()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func make_source(path:String,color:Color)->void:
	var model:=Node3D.new();model.name="Source"
	var pixels:=Image.create(8,8,false,Image.FORMAT_RGBA8);pixels.fill(color)
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(pixels)
	var mesh:=BoxMesh.new();mesh.material=material
	var child:=MeshInstance3D.new();child.name="ColoredBox";child.mesh=mesh;model.add_child(child)
	check(Io.save_scene(model,path)==OK,"write source "+path.get_file()+" "+str(color))
	model.free()
func has_color(node:Node,color:Color)->bool:
	if node==null:return false
	var meshes:Array=Materials.meshes(node)
	if meshes.size()!=1:return false
	var material:BaseMaterial3D=meshes[0].get_active_material(0)
	if material==null or material.albedo_texture==null:return false
	var pixels:=material.albedo_texture.get_image()
	return pixels!=null and pixels.get_pixel(0,0).is_equal_approx(color)
func run()->void:
	directory=Paths.cache_directory("incremental_fallback_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var source_a:=directory.path_join("source_a.glb")
	make_source(source_a,Color.RED)
	for reason:String in ["incremental_neighbor_geometry","baseline_content_changed","published_dependency_changed"]:
		var folder:=directory.path_join(reason);var path:=folder.path_join("map.gltf")
		var doc:=Doc.new();var original:String=doc.add_asset({"asset_path":source_a},Vector3(0,2,0))
		check(doc.save(path)==OK and doc.last_save_metrics.get("export",{}).get("mode")=="full_export",reason+" creates independent trusted baseline A")
		var before:=Pose._json(path)
		check(before.get("extras",{}).has(Pose.MANIFEST),reason+" baseline has manifest")
		if reason=="baseline_content_changed":
			var bytes:=FileAccess.get_file_as_bytes(path);bytes.append(10)
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
			doc=Doc.open_file(path)
			check(doc!=null and doc.save_signature(path)==FileAccess.get_sha256(path),"external newline reopened with fresh conflict signature")
		elif reason=="published_dependency_changed":
			var uri:String=before.buffers[0].uri
			var dependency:=folder.path_join(Io.decode_dependency_uri(uri))
			var bytes:=FileAccess.get_file_as_bytes(dependency);bytes.append(9)
			var file:=FileAccess.open(dependency,FileAccess.WRITE);file.store_buffer(bytes);file.close()
			check(FileAccess.get_sha256(dependency)!=before.extras[Pose.MANIFEST].dependencies[uri],"published buffer checksum actually changed")
		var introduced:=folder.path_join("introduced.glb")
		make_source(introduced,Color.GREEN)
		var preview:=Library.instantiate(introduced)
		check(Library._scenes.has(introduced) and has_color(preview,Color.GREEN),reason+" preview really caches green source")
		if preview!=null:preview.free()
		make_source(introduced,Color.BLUE)
		var fresh:=Io.load_scene(introduced)
		check(has_color(fresh,Color.BLUE),reason+" disk source now contains blue pixels")
		if fresh!=null:fresh.free()
		preview=Library.instantiate(introduced)
		check(has_color(preview,Color.GREEN),reason+" preview remains stale green before save")
		if preview!=null:preview.free()
		var added:String=doc.add_asset({"asset_path":introduced},Vector3(4,2,0))
		if reason=="incremental_neighbor_geometry":
			var terrain:String=doc.add_box("ground",Vector3(20,0,0),Vector3(8,1,8))
			var record:Dictionary=doc._find(terrain)
			record.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-1.,"heights":[0,0,0,0,0,0,0,0,0],"holes":[false,false,false,false]}
		# These are full-fallback correctness tests. They do not assert terrain
		# additions have gained incremental support or that rebuilding is fast.
		check(doc.save(path)==OK,reason+" fallback save succeeds")
		check(doc.last_save_metrics.get("reuse_fallback")==reason,reason+" reaches intended rejection before full fallback")
		check(doc.last_save_metrics.get("export",{}).get("mode")=="full_export",reason+" performs actual full fallback")
		var native:=Io.load_scene(path)
		check(native!=null,reason+" native saved map loads")
		if native!=null:
			check(has_color(Io.find_named(native,added),Color.BLUE),reason+" newly introduced source exports fresh blue instead of stale preview green")
			check(has_color(Io.find_named(native,original),Color.RED),reason+" unchanged original source remains red")
			native.free()
		var saved:=Pose._json(path)
		check(saved.get("extras",{}).get(Pose.MANIFEST,{}).get("sources",{}).get(introduced)==FileAccess.get_sha256(introduced),reason+" new baseline binds actual blue source hash")
		check(Pose.dependencies(saved,path,Paths.external_root(),Io).ok,reason+" published dependencies remain readable")
		print("INCREMENTAL_FALLBACK_METRICS ",reason," ",JSON.stringify(doc.last_save_metrics))
	if failed==0:Io._remove_tree(directory)
	else:print("INCREMENTAL_FALLBACK_FAILED_FIXTURE ",directory)
	print("INCREMENTAL_FALLBACK_FAILED=",failed)
	quit(0 if failed==0 else 1)
