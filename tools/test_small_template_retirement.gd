extends SceneTree
## A small hierarchy can still own many independent, expensive native resources.
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Scope=preload("res://scripts/world3d/runtime_asset_cache_scope.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var failures:=0
var checks:=0
var reports:Array=[]
class WatchedMesh extends ArrayMesh:
	var receipt:Dictionary
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			receipt.deaths+=1;receipt.threads[OS.get_thread_caller_id()]=true
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fixture(count:int)->Dictionary:
	var receipt:={"deaths":0,"threads":{}}
	var scene:=Node3D.new();scene.name="SmallHierarchy"
	var watches:Array=[]
	for i:int in count:
		var mesh:=WatchedMesh.new();mesh.receipt=receipt
		var vertices:=PackedVector3Array();vertices.resize(12288)
		for j:int in vertices.size():vertices[j]=Vector3(j%3,0,(j/3)%2)
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node:=MeshInstance3D.new();node.name="Part%d"%i;node.mesh=mesh
		scene.add_child(node);node.owner=scene;watches.append(weakref(mesh))
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack actual native meshes")
	scene.free()
	return {"packed":packed,"receipt":receipt,"watches":watches}
func drain()->void:
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	if service==null:return
	service.set_process(false)
	var steps:=0
	while not service.pending.is_empty() and steps<20000:
		if service._advance(service.pending[0],1):service._finish_front()
		steps+=1
	check(service.pending.is_empty() and service.known.is_empty(),"all scene disposal tickets drain")
func trial(count:int,mode:String)->void:
	var f:=fixture(count);var receipt:Dictionary=f.receipt;var watches:Array=f.watches
	var template:WeakRef=weakref(f.packed);var path:="D:/code/rmmo_runtime/cache/world3d/small_template_%d_%s.glb"%[count,mode]
	var map:=Node3D.new();root.add_child(map)
	check(Assets.cache_packed(path,f.packed),"cache template")
	Scope.claim(map,path)
	var other:=Node3D.new()
	if mode=="shared":Scope.claim(other,path)
	var borrowed:Node=f.packed.instantiate() if mode=="borrowed" else null
	f.erase("packed")
	if mode=="shared":
		check(not map.get_meta(Scope.META).release(path) and Assets.has_cached_scene(path),"shared map blocks eviction")
		map.free();map=other;other=null
	if mode=="replacement":
		var replacement:=PackedScene.new();var node:=Node3D.new();replacement.pack(node);node.free()
		check(Assets.cache_packed(path,replacement),"replacement accepts new template")
		check(not map.get_meta(Scope.META).release(path) and Assets._scenes[path]==replacement,"old claim cannot erase replacement")
		Assets.evict_cached_scene(path);replacement=null
	elif mode=="direct":check(Assets.evict_cached_scene(path),"direct cache eviction succeeds")
	else:check(map.get_meta(Scope.META).release(path),"last map evicts exact template")
	check(not Assets.has_cached_scene(path),"logical eviction is immediate")
	check(receipt.deaths==0 and template.get_ref()!=null,"WORK small template retains dependencies after synchronous eviction")
	reports.append({"meshes":count,"mode":mode,"synchronous_deaths":receipt.deaths})
	drain()
	check(template.get_ref()==null,"template releases after disposal")
	if borrowed!=null:
		check(receipt.deaths==0 and watches.all(func(w):return w.get_ref()!=null),"live instance keeps original mesh owners")
		check((borrowed.get_child(0) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==12288,"borrowed geometry remains intact")
		borrowed.free();borrowed=null
	check(receipt.deaths==count and watches.all(func(w):return w.get_ref()==null),"all unborrowed native meshes release")
	check(receipt.threads.keys()==[OS.get_main_thread_id()],"native meshes release only on main thread")
	if is_instance_valid(map):map.free()
	if is_instance_valid(other):other.free()
	drain()
func run()->void:
	for count:int in [1,16,63,64]:trial(count,"scope")
	for mode:String in ["shared","borrowed","replacement","direct"]:trial(16,mode)
	check(Scope._scopes.is_empty(),"no leaked map claims")
	print("SMALL_TEMPLATE_RETIREMENT ",JSON.stringify({"checks":checks,"failures":failures,"reports":reports}))
	quit(1 if failures else 0)
