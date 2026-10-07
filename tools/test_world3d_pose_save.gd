extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0
func _init()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print(("PASS: " if value else "FAIL: ")+label)
	if not value:failed+=1
func exported(doc:RefCounted)->Dictionary:return doc.last_save_metrics.get("export",{})
func run()->void:
	var directory:=Paths.cache_directory("pose_save_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var texture:=directory.path_join("texture.png")
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.RED);image.save_png(texture)
	var doc:=Doc.new()
	var terrain:String=doc.add_box("ground",Vector3.ZERO,Vector3(8,1,8))
	var ground:Dictionary=doc._find(terrain)
	ground.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-1.,"heights":[0,0,0,0,0,0,0,0,0],"holes":[false,false,false,false]}
	ground.terrain_material={"name":"paint","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":texture}
	var id:String=doc.add_box("block",Vector3(1,2,3),Vector3(2,3,4))
	check(doc.save(path)==OK,"first complete export creates baseline")
	var first:=exported(doc).duplicate(true)
	check(first.get("texture_export_passes")==1 and first.get("images_written",0)>0,"first save really exports texture images")
	var baseline:=Pose._json(path)
	check(baseline.get("extras",{}).has(Pose.MANIFEST),"resource manifest is outside authoring extras")
	var dependencies:=Pose.dependencies(baseline,path,Paths.external_root(),Io)
	check(doc.save(path)==OK and exported(doc).get("mode")=="pose_reuse" and exported(doc).images_written==0,"unchanged save skips material and texture export")
	for step in 3:
		doc._find(id).position[0]+=2.25;doc._find(id).rotation[1]+=35.
		check(doc.save(path)==OK and exported(doc).get("mode")=="pose_reuse","move and rotation reuse saved resources %d"%step)
		var loaded=Doc.open_file(path)
		check(loaded!=null and Pose.same(loaded.records,doc.records),"authoring reopen retains poses %d"%step)
		var scene:=Io.load_scene(path)
		var visual:Node3D=Io.find_named(scene,id)
		check(visual!=null and visual.transform.is_equal_approx(Pose.pose(doc._find(id))),"native glTF node pose matches records %d"%step)
		scene.free();doc=loaded
	check(Pose.same(dependencies,Pose.dependencies(Pose._json(path),path,Paths.external_root(),Io)),"all image/buffer URIs and bytes remain identical")
	var original:=FileAccess.get_sha256(path)
	for stage in ["resources_ready","before_publish"]:
		Io.save_fault=func(at):return at==stage
		doc._find(id).position[2]+=1
		check(doc.save(path)!=OK and FileAccess.get_sha256(path)==original,"fast save interruption preserves original at "+stage)
	Io.save_fault=Callable()
	check(doc.save(path)==OK,"retry after failed fast publication")
	Io.save_fault=func(stage):
		if stage=="before_publish":
			var text:=FileAccess.get_file_as_string(path)
			var external:=FileAccess.open(path,FileAccess.WRITE);external.store_string(text+"\n");external.close()
		return false
	var old_signature:=FileAccess.get_sha256(path)
	check(doc.save(path)==ERR_BUSY and FileAccess.get_sha256(path)!=old_signature,"late external map writer is preserved by final conflict check")
	Io.save_fault=Callable();doc=Doc.open_file(path)
	check(doc.save(path)==OK and exported(doc).get("mode")=="full_export","externally changed baseline content triggers complete rebuild")
	Io.save_fault=func(stage):
		if stage=="before_publish":image.fill(Color.GREEN);image.save_png(texture)
		return false
	old_signature=FileAccess.get_sha256(path)
	check(doc.save(path)==ERR_BUSY and FileAccess.get_sha256(path)==old_signature,"late source texture change does not publish stale reuse")
	Io.save_fault=Callable()
	check(doc.save(path)==OK and exported(doc).get("mode")=="full_export","retry exports changed source after race")
	var stale=Doc.open_file(path)
	doc._find(id).position[0]+=1;check(doc.save(path)==OK,"new writer publishes")
	check(stale.save(path)==ERR_BUSY,"stale writer does not overwrite new map")
	# Changed source pixels must invalidate both reuse and stale in-memory material caches.
	image.fill(Color.BLUE);image.save_png(texture)
	check(doc.save(path)==OK and exported(doc).get("mode")=="full_export","external texture edit falls back to full export")
	var scene:=Io.load_scene(path)
	var visual:MeshInstance3D=Io.find_named(scene,terrain)
	var material:BaseMaterial3D=visual.get_active_material(0)
	check(material.albedo_texture.get_image().get_pixel(0,0).b>.9,"fallback exports the changed pixels rather than cached red")
	scene.free()
	doc._find(id).size[0]+=1
	check(doc.save(path)==OK and exported(doc).get("mode")=="full_export","geometry size edit uses full export")
	var dep:String=Io._buffer_uris(path)[0]
	var file:=FileAccess.open(directory.path_join(dep),FileAccess.WRITE);file.store_string("broken");file.close()
	check(doc.save(path)==OK and exported(doc).get("mode")=="full_export","corrupt published dependency is rebuilt, never blindly reused")
	var other:=directory.path_join("other/map.gltf")
	check(doc.save(other)==OK and exported(doc).get("mode")=="full_export","Save As exports independent resources")
	var relocated:=Pose._json(other)
	check(Pose.dependencies(relocated,other,Paths.external_root(),Io).ok,"Save As dependencies stay inside its own directory")
	for uri in Io._buffer_uris(other):check(not uri.contains(".."),"Save As has no old-directory dependency")
	var test_record:Dictionary=doc._find(id).duplicate(true)
	test_record.fixture={"id":"door","kind":"door","pivot":[-1.,0.,0.],"angle":90.,"open":.6}
	var node:Dictionary={};Pose._set_pose(node,Pose.pose(test_record))
	check(Pose._node_pose(node).is_equal_approx(preload("res://scripts/world3d/building_fixtures.gd").transform(test_record)),"fixture matrix preserves open hinge pose")
	# The holder, not its nested meshes, owns an imported object's world pose.
	var model:=Node3D.new();model.name="Model"
	var shared:=BoxMesh.new()
	for i in 2:
		var part:=MeshInstance3D.new();part.name="Part%d"%i;part.mesh=shared;part.position=Vector3(i*3,0,0);model.add_child(part)
	var model_path:=directory.path_join("model.gltf")
	check(Io.save_scene(model,model_path)==OK,"nested imported source fixture")
	model.free()
	var imported:String=doc.add_asset({"asset_path":model_path},Vector3(10,2,3))
	check(doc.save(other)==OK,"imported multi-mesh baseline")
	var asset_before:=Pose._json(other)
	doc.move(imported,Vector3(14,2,3));doc._find(imported).rotation=[0,47,0]
	check(doc.save(other)==OK and exported(doc).get("mode")=="pose_reuse","imported holder movement reuses all child meshes")
	var asset_after:=Pose._json(other);var same_children:=true
	for i in asset_before.nodes.size():
		if asset_before.nodes[i].get("name") in ["rmmo_world",imported]:continue
		same_children=same_children and Pose.same(asset_before.nodes[i],asset_after.nodes[i])
	check(same_children and Pose.same(asset_before.meshes,asset_after.meshes),"unchanged child transforms and shared mesh indexes")
	var saved_signature:=FileAccess.get_sha256(other)
	file=FileAccess.open(model_path,FileAccess.WRITE);file.store_string('{"asset":{"version":"2.0"},"images":[7]}');file.close()
	check(doc.save(other)!=OK and FileAccess.get_sha256(other)==saved_signature,"malformed external glTF dependency array fails without mutation")
	file=FileAccess.open(model_path,FileAccess.WRITE);file.store_string('{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":99}]}');file.close()
	check(doc.save(other)!=OK and FileAccess.get_sha256(other)==saved_signature,"unloadable model cannot replace original with a missing-asset box")
	print("POSE_SAVE_FINISHED ",JSON.stringify({"failures":failed,"first":first,"last":doc.last_save_metrics}))
	Io._remove_tree(directory)
	quit(0 if failed==0 else 1)
