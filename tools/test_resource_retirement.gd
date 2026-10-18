extends SceneTree
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Scope=preload("res://scripts/world3d/runtime_asset_cache_scope.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Dictionary:
	var scene:=Node3D.new();scene.name="ManyMeshes"
	var image:=Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color(.4,.7,.3))
	var texture:=ImageTexture.create_from_image(image)
	var material:=StandardMaterial3D.new();material.albedo_texture=texture
	var watches:Array=[weakref(material),weakref(texture)]
	for i:int in 256:
		var node:=MeshInstance3D.new();node.name="Part%d"%i;node.mesh=BoxMesh.new();node.mesh.material=material
		scene.add_child(node);node.owner=scene;node.mesh.get_rid();watches.append(weakref(node.mesh))
	var packed:=PackedScene.new();packed.pack(scene)
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	return {"packed":packed,"watches":watches}
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	check(DisplayServer.get_name()!="headless","resource disposal fixture uses real GPU meshes and embedded pixels")
	var packet:=fixture();var watches:Array=packet.watches
	var path:="D:/code/rmmo_runtime/cache/world3d/retirement_fixture.glb"
	var map:=Node3D.new();root.add_child(map)
	Assets.cache_packed(path,packet.packed);Scope.claim(map,path)
	var template:WeakRef=weakref(packet.packed);packet.clear()
	check(map.get_meta(Scope.META).release(path) and not Assets.has_cached_scene(path),"logical last-owner cache eviction is immediate")
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	check(service!=null and service.pending.size()==1 and template.get_ref()!=null,"large template has an explicit tree-owned disposal owner after eviction")
	service.set_process(false)
	for i:int in 10:service._advance(service.pending[0],1)
	check(not service.pending.is_empty() and watches.all(func(reference):return reference.get_ref()!=null),"bounded description scan keeps every dependency alive before template release")
	service.set_process(true)
	var deadline:=Time.get_ticks_msec()+15000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	RenderingServer.force_sync();await process_frame
	check(service.pending.is_empty() and service.known.is_empty() and template.get_ref()==null,"disposal finishes without a queued template or identity leak")
	check(watches.all(func(reference):return reference.get_ref()==null),"all actual mesh/material/texture weak probes release after the final disposal slice")
	check(service.profile.slices>10 and service.profile.resources>=256,"real final resource destructors progress through multiple budget slices")
	map.free();print("RESOURCE_RETIREMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
