extends SceneTree
## Real Godot 4.8 GLTF export/parse and image-free native serialization.
## Public Compiled.build requires graphics; this CPU test does not bypass that
## gate or claim the full UI import transaction. Native reopen is a second run.
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var checks:=0
var failures:=0
var output:=""
var golden:Array=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func box_array(box:AABB)->Array:
	return [box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z]

func array_box(value:Array)->AABB:
	return AABB(Vector3(value[0],value[1],value[2]),Vector3(value[3],value[4],value[5]))

func read_glb(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ);file.seek(12)
	var length:=file.get_32();file.get_32()
	var data:Dictionary=JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	var bin_length:=file.get_32();file.get_32()
	return {"json":data,"bin":file.get_buffer(bin_length)}

func write_glb(path:String,data:Dictionary,bin:PackedByteArray)->void:
	var json:=JSON.stringify(data).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+json.size()+bin.size())
	file.store_32(json.size());file.store_32(0x4e4f534a);file.store_buffer(json)
	file.store_32(bin.size());file.store_32(0x004e4942);file.store_buffer(bin);file.close()

func own(node:Node,owner_:Node)->void:
	for child:Node in node.get_children():child.owner=owner_;own(child,owner_)

func fixture(kind:String)->Dictionary:
	var scene:Node=Node.new() if kind=="plain_node" else Node3D.new();scene.name="ModelRoot"
	if kind=="trs":scene.transform=Transform3D(Basis.from_euler(Vector3(.2,.4,-.1)).scaled_local(Vector3(2,1.5,.75)),Vector3(11,-3,7))
	if kind=="matrix":scene.transform=Transform3D(Basis(Vector3(1,.25,0),Vector3(.1,1,0),Vector3(0,.2,1.5)),Vector3(-8,2,4))
	var mesh:=MeshInstance3D.new();mesh.name="Box";mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(2,4,6)
	mesh.transform=Transform3D(Basis.from_euler(Vector3(0,.3,0)),Vector3(2,1,-1))
	if kind=="mesh_root":scene.free();scene=mesh;scene.name="MeshRoot"
	else:scene.add_child(mesh);mesh.owner=scene
	var expected:AABB=Library.bounds_of(scene if scene is Node3D else mesh)
	var path:=output.path_join(kind+".glb")
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	check(document.append_from_scene(scene,state)==OK,kind+": real 4.8 append_from_scene")
	check(document.write_to_filesystem(state,path)==OK,kind+": real 4.8 GLB export")
	Drainer.dispose_scene(scene);state=null;document=null
	var source:=read_glb(path)
	check(source.json.get("extensionsUsed",[]).has("GODOT_single_root"),kind+": exporter emits unchanged single-root declaration")
	if kind in ["trs","matrix"]:
		check(source.json.nodes[0].has("matrix") or source.json.nodes[0].has("translation"),kind+": exported root transform remains nonidentity")
	var bounds:=Manifest.read(path)
	check(bounds.get("known",false),kind+": bounds manifest admits real static Godot export")
	if bounds.get("known",false):check(bounds.local_bounds.is_equal_approx(expected),kind+": accessor bounds include root and child transforms once")
	var metadata:=Footprint._source_metadata(path)
	check(not metadata.is_empty(),kind+": compiled footprint source metadata accepts the same export")
	if not metadata.is_empty():check(array_box(metadata.local_bounds).is_equal_approx(expected),kind+": persisted native metadata bounds match actual source scene")
	var prepared:=Compiled.prepare_source(path)
	check(prepared.error==OK and prepared.current(),kind+": real prepared source parsed once with stable SHA")
	var generated:Node=prepared.get_scene()
	check(generated is Node3D and Library.bounds_of(generated).is_equal_approx(expected),kind+": default 4.8 generate_scene preserves source bounds")
	if generated!=null:
		own(generated,generated)
		var packed:=PackedScene.new();check(packed.pack(generated)==OK,kind+": pack actual prepared scene")
		check(Compiled.strict_image_free(packed),kind+": native scene satisfies static image-free geometry contract")
		var native_path:=output.path_join(kind+".scn")
		check(ResourceSaver.save(packed,native_path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,kind+": save native PackedScene")
		check(ResourceLoader.get_dependencies(native_path).is_empty(),kind+": native scene has no external GLB dependencies")
		golden.append({"name":kind,"native":native_path,"sha":FileAccess.get_sha256(native_path),"source":path,"bounds":box_array(expected)})
		packed=null
	prepared.dispose();prepared=null;generated=null;Drainer.synchronize_transfer()
	return source

func malformed(source:Dictionary)->void:
	for kind:String in ["duplicate_root","scene_parent","scene_index","cycle","missing_scenes","used_payload","node_payload","nested_declaration","required_extension","unknown_extension","skin","animation","morph","native_map"]:
		var data:Dictionary=source.json.duplicate(true)
		var orphan:int=data.nodes.size();data.nodes.append({"name":"Other","mesh":0,"translation":[100,0,0]})
		match kind:
			"duplicate_root":data.scenes[0].nodes=[0,0]
			"scene_parent":data.scenes[0].nodes=[1]
			"scene_index":data.scene=4
			"cycle":data.nodes[1].children=[0]
			"missing_scenes":data.erase("scenes")
			"used_payload":data.extensions={"GODOT_single_root":{}}
			"node_payload":data.nodes[0].extensions={"GODOT_single_root":{}}
			"nested_declaration":data.nodes[0].extras={"extensionsUsed":["GODOT_single_root"]}
			"required_extension":data.extensionsRequired=["GODOT_single_root"]
			"unknown_extension":data.extensionsUsed.append("UNKNOWN_geometry")
			"skin":data.nodes[1].skin=0
			"animation":data.animations=[{}]
			"morph":data.meshes[0].primitives[0].targets=[{}]
			"native_map":data.nodes[0].extras={"rmmo_format":"rmmo_gltf_map"}
		check(not Manifest.from_json(data,source.bin.size()).get("known",false),"unchanged rejection boundary: "+kind)
	var with_orphan:Dictionary=source.json.duplicate(true)
	with_orphan.nodes.append({"name":"Unused","mesh":0,"translation":[100,0,0]})
	var bounds:=Manifest.from_json(with_orphan,source.bin.size())
	check(bounds.get("known",false) and bounds.get("mesh_nodes",[]).size()==1,"valid unselected orphan does not enter node-zero bounds")
	with_orphan.erase("scene")
	check(Manifest.from_json(with_orphan,source.bin.size()).get("known",false),"omitted default scene still resolves to unique scene zero")
	# Removing the declaration restores ordinary selected-scene semantics.
	var ordinary:Dictionary=source.json.duplicate(true);ordinary.extensionsUsed.erase("GODOT_single_root")
	var index:int=ordinary.nodes.size();ordinary.nodes.append({"mesh":0,"translation":[100,0,0]})
	ordinary.scenes.append({"nodes":[index]});ordinary.scene=1
	var ordinary_path:=output.path_join("ordinary_selected.glb");write_glb(ordinary_path,ordinary,source.bin)
	var prepared:=Compiled.prepare_source(ordinary_path);var generated:Node=prepared.get_scene()
	var selected:=Manifest.read(ordinary_path)
	check(selected.get("known",false) and generated is Node3D and selected.local_bounds.is_equal_approx(Library.bounds_of(generated)),"ordinary multi-scene selected-root behavior is unchanged")
	prepared.dispose();Drainer.synchronize_transfer()

func root_selection(source:Dictionary)->void:
	for kind:String in ["multiple_roots","other_root","multiple_scenes","selected_other_scene","root_has_parent","empty_roots"]:
		var data:Dictionary=source.json.duplicate(true)
		var orphan:int=data.nodes.size();data.nodes.append({"name":"Other","mesh":0,"translation":[100,0,0]})
		match kind:
			"multiple_roots":data.scenes[0].nodes=[0,orphan]
			"other_root":data.scenes[0].nodes=[orphan]
			"multiple_scenes":data.scenes.append({"nodes":[orphan]})
			"selected_other_scene":data.scenes.append({"nodes":[orphan]});data.scene=1
			"root_has_parent":data.nodes[orphan].children=[0];data.scenes[0].nodes=[orphan]
			"empty_roots":data.scenes[0].nodes=[]
		var path:=output.path_join(kind+".glb");write_glb(path,data,source.bin)
		var prepared:=Compiled.prepare_source(path);var generated:Node=prepared.get_scene()
		check(prepared.error==OK and generated is Node3D,kind+": actual 4.8 accepts graph and generates node zero")
		var result:=Manifest.read(path)
		check(result.get("known",false),kind+": single-root declaration follows engine node-zero semantics")
		if result.get("known",false) and generated is Node3D:
			check(result.local_bounds.is_equal_approx(Library.bounds_of(generated)) and result.mesh_nodes.size()==1,kind+": metadata matches generated tree without another scene or ancestor transform")
		prepared.dispose();Drainer.synchronize_transfer()

func reopen()->void:
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("native_reopen.json")))
	for row:Dictionary in saved.models:
		check(not FileAccess.file_exists(row.source),str(row.name)+": source absent in cold reopen process")
		check(FileAccess.get_sha256(row.native)==row.sha,str(row.name)+": exact native product SHA retained")
		var packed:=ResourceLoader.load(row.native,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(packed!=null,str(row.name)+": cold native-only ResourceLoader reopen")
		if packed==null:continue
		var scene:=Library._instantiate(packed)
		check(scene!=null and Library.bounds_of(scene).is_equal_approx(array_box(row.bounds)),str(row.name)+": cold runtime instance bounds preserve root transforms")
		Drainer.dispose_scene(scene);scene=null;packed=null;Drainer.synchronize_transfer()
	check(Library._scenes.is_empty(),"CPU native reopen does not populate the global library cache")

func run()->void:
	create_timer(60).timeout.connect(func():printerr("SINGLE_ROOT_BOUNDS watchdog");quit(2))
	var original:="";var cold:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
		elif arg.begins_with("--original-fixture="):original=arg.trim_prefix("--original-fixture=")
		elif arg=="--reopen":cold=true
	if not output.contains("/review_artifacts/") or output.begins_with("res://"):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	if cold:reopen()
	else:
		var baseline:Dictionary={}
		for kind:String in ["plain_node","identity","trs","matrix","mesh_root"]:
			var source:=fixture(kind)
			if kind=="plain_node":baseline=source
		malformed(baseline);root_selection(baseline)
		if not original.is_empty():
			var observation:=Manifest.read(original)
			check(observation.get("known",false),"preserved real world3d_assets failure fixture now has known bounds")
		FileAccess.open(output.path_join("native_reopen.json"),FileAccess.WRITE).store_string(JSON.stringify({"models":golden}))
		for row:Dictionary in golden:
			check(DirAccess.remove_absolute(row.source)==OK,str(row.name)+": remove generated source before independent native reopen")
	print("SINGLE_ROOT_BOUNDS checks=",checks," failures=",failures," cold=",cold)
	quit(0 if failures==0 else 1)
