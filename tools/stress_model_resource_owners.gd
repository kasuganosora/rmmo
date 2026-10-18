extends SceneTree
## Reproduces the previous short Array -> large Array[Resource] shape in the
## benchmark only. Production exclusively creates ModelOwners.
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Owners=preload("res://scripts/world3d/model_resource_owners.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
var checks:=0
var failures:=0
var output:=""
var trials:Array=[]
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(count:int,with_scene:bool)->Dictionary:
	var owners:=Owners.new();owners.document=GLTFDocument.new();owners.state=GLTFState.new()
	var watches:Array=[weakref(owners.state),weakref(owners.document)]
	var nodes:Array[GLTFNode]=[];var meshes:Array[GLTFMesh]=[];var json:Array=[]
	var scene:=Node3D.new()
	for i:int in count:
		var node:=GLTFNode.new();node.mesh=i;nodes.append(node)
		json.append({"mesh":i,"extras":{"tags":[i,"same-shape",{"values":[i,i+1]}]}})
		var resource:Resource
		if with_scene:
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
			var importer:=ImporterMesh.new();importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var gltf:=GLTFMesh.new();gltf.mesh=importer;meshes.append(gltf)
			resource=importer.get_mesh()
			var instance:=MeshInstance3D.new();instance.mesh=resource;scene.add_child(instance);instance.owner=scene
			watches.append(weakref(importer));watches.append(weakref(gltf))
		else:resource=Resource.new()
		owners.visuals.append(resource);watches.append(weakref(resource))
		if i%3==0:owners.visuals.append(resource)
	owners.state.nodes=nodes;owners.state.meshes=meshes;owners.state.json={"nodes":json}
	owners.state.set_meta("aliases",owners.visuals.slice(0,20))
	if with_scene:
		owners.packed=PackedScene.new();check(owners.packed.pack(scene)==OK,"GPU fixture packs actual meshes")
		watches.append(weakref(owners.packed))
	scene.free()
	return {"owners":owners,"watches":watches}
func measure(count:int,typed:bool,with_scene:bool,keep_published:bool)->void:
	var data:=fixture(count,with_scene);var owners:RefCounted=data.owners;var watches:Array=data.watches;data.clear()
	var survivors:Array=owners.visuals.duplicate() if keep_published else []
	var cached:PackedScene=owners.packed if keep_published else null
	var borrowed:Dictionary={"records":[{"uuid":"author","nested":[1,2,3]}]}
	var packet:Dictionary={"records":borrowed.records}
	if typed:
		if keep_published:owners.transfer_template(cached)
		packet.resource_owners=owners
	else:
		packet.retained_resources=[{"retained_resources":[owners.document,owners.state]},owners.packed,owners.visuals]
		var empty:Array[Resource]=[]
		owners.document=null;owners.state=null;owners.packed=null;owners.visuals=empty
	owners=null
	var ledger:=Admission.new();ledger.reserve("test",{"estimated_bytes":count*1024,"exclusive":false});ledger.park("test")
	Drainer.synchronize_transfer()
	var service:Node=Retirement._service();service.set_process(false)
	var before:Dictionary=service.profile.duplicate()
	var began:=Time.get_ticks_usec()
	var deferred:bool=Retirement.defer_model_packet(packet,Callable(ledger,"release").bind("test"),ledger) if typed else Retirement.defer_import_packet(packet,Callable(ledger,"release").bind("test"),ledger)
	Drainer.dispose_result(packet)
	var handoff:=Time.get_ticks_usec()-began
	check(deferred and packet.is_empty() and ledger.reserved_bytes==count*1024,"handoff keeps reservation until final owner")
	var total:int=handoff;var maximum:=0;var slices:=0
	while not service.pending.is_empty() and slices<100000:
		began=Time.get_ticks_usec()
		if service._advance(service.pending[0],1000):service._finish_front()
		var elapsed:=Time.get_ticks_usec()-began;total+=elapsed;maximum=maxi(maximum,elapsed);slices+=1
	check(service.pending.is_empty() and ledger.reserved_bytes==0,"bounded slices finish and return byte reservation")
	check(borrowed=={"records":[{"uuid":"author","nested":[1,2,3]}]},"borrowed graph survives")
	survivors.clear();cached=null;RenderingServer.force_sync()
	check(watches.all(func(w):return w.get_ref()==null),"weak probes confirm all fixture resources released")
	var work:Dictionary={}
	for key:String in ["model_values","model_slices","import_values","import_slices","resources"]:work[key]=int(service.profile[key])-int(before[key])
	var result:Dictionary={"count":count,"typed":typed,"gpu_scene":with_scene,"published":keep_published,"handoff_us":handoff,"max_slice_us":maximum,"cpu_total_us":total,"slices":slices,"work":work}
	trials.append(result);print("OWNER_STRESS ",JSON.stringify(result))
	await process_frame
func run()->void:
	check(DisplayServer.get_name()!="headless","GPU case uses actual RenderingServer")
	for count:int in [2151,21510]:
		for turn:int in 4:await measure(count,turn in [1,2],false,false)
	for published:bool in [false,true]:
		for turn:int in 4:await measure(2151,turn in [1,2],true,published)
	check(trials.size()==16,"every baseline and candidate trial actually completed")
	var report:Dictionary={"checks":checks,"failures":failures,"trials":trials,"engine":Engine.get_version_info(),"note":"ABBA original nested handoff vs typed owner; identical synthetic data. 1 ms soft slice budget includes destructors; no FPS inference. Construction excluded, all retirement CPU included."}
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MODEL_OWNER_STRESS checks=",checks," failures=",failures);quit(1 if failures else 0)
