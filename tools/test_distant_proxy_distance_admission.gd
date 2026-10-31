extends SceneTree
## Near sources must not pay material inspection; conservative bounds must
## preserve far eligible subsets and already-published hysteresis behavior.
const Proxy=preload("res://scripts/world3d/distant_building_proxy.gd")
class Batches extends Node:
	var groups:Dictionary={}
var failures:Array=[]
var checks:=0
var result:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func world()->Node3D:
	var scene:=Node3D.new();root.add_child(scene)
	var batches:=Batches.new();batches.name="GroundRenderBatches";scene.add_child(batches)
	var service:=Proxy.new();service.name="Proxy";scene.add_child(service);service.set_process(false)
	scene.set_meta("stream_meshes",{})
	return scene
func source(scene:Node3D,mesh:Mesh,position:Vector3,building:String,batch:bool=false)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position=position
	node.set_meta("ground_batch_record",{"building":{"id":building},"house_prefab":{}})
	scene.add_child(node)
	if batch:scene.get_node("GroundRenderBatches").groups[str(node.get_instance_id())]={"category":"building","visual":node,"members":[node]}
	else:scene.get_meta("stream_meshes")[str(node.name)]=node
	return node
func discard(scene:Node3D)->void:
	var service:Node=scene.get_node("Proxy");service.clear()
	var deadline:=Time.get_ticks_msec()+10000
	while not service._job.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;service._poll()
	check(service._job.is_empty(),"background preparation drains before test world disposal")
	scene.free();await process_frame
func run()->void:
	# Exercise this stage even when the earlier building proof can skip it.
	var proxy_script:Variant=Proxy
	if proxy_script.get("building_admission_enabled")!=null:proxy_script.set("building_admission_enabled",false)
	var scene:=world();var service:Node=scene.get_node("Proxy")
	var material:=StandardMaterial3D.new();var meshes:Array[ArrayMesh]=[]
	var arrays:=BoxMesh.new().get_mesh_arrays()
	for i in 117:
		var mesh:=ArrayMesh.new()
		for slot in 8:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(slot,material)
		meshes.append(mesh)
	for house in 31:
		for part in 7:source(scene,meshes[(house*7+part)%117],Vector3(140+house%8*6,0,house/8*8+part*.1),"house_"+str(house),part<4)
	var times:Array=[]
	for i in 64:
		var began:=Time.get_ticks_usec();service.tick(Vector3.ZERO);times.append(Time.get_ticks_usec()-began)
	result.profile=service.profile.duplicate(true)
	check(service._rows.is_empty() and service._job.is_empty(),"217 near sources never create a proxy or geometry task")
	check(service.profile.near_snapshot_skips==31*64,"all near cohorts are rejected before snapshot")
	if not "--baseline" in OS.get_cmdline_user_args():
		check(service.profile.eligibility_mesh_evaluations==0,"near-only ticks do not inspect shared mesh materials")
		check(int(service.profile.get("early_near_mesh_skips",0))==217*64,"every near source avoids unnecessary material inspection")
	for mesh:ArrayMesh in meshes:check(not mesh.has_meta("ground_cpu_cache"),"near geometry stays uncaptured")
	times.sort();result.tick_median_us=times[32];result.tick_p95_us=times[60];result.tick_total_us=times.reduce(func(a,b):return a+b,0)
	await discard(scene)
	var opaque:=BoxMesh.new();opaque.material=material
	# All parts are near, but changing camera position must immediately use
	# current materials. No cross-frame eligibility or distance cache is valid.
	scene=world();service=scene.get_node("Proxy")
	var a:=source(scene,opaque,Vector3(150,0,0),"live")
	var b:=source(scene,opaque,Vector3(152,0,0),"live")
	service.tick(Vector3.ZERO)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	service.tick(Vector3(-200,0,0))
	check(service._job.is_empty(),"far admission sees material changed after a near-only tick")
	material.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED
	service.tick(Vector3(-200,0,0))
	check(not service._job.is_empty(),"camera departure immediately admits the current opaque sources")
	service.tick(Vector3.ZERO)
	check(service._job.get("cancelled",false),"returning near cancels the same pending preparation")
	await discard(scene)
	# The combined center is near; an unsupported part must not hide the far
	# eligible subset. Checking only the unfiltered center would be incorrect.
	scene=world();service=scene.get_node("Proxy")
	a=source(scene,opaque,Vector3(250,0,0),"mixed")
	b=source(scene,opaque,Vector3(252,0,0),"mixed")
	var unsupported:=BoxMesh.new();unsupported.material=ShaderMaterial.new()
	source(scene,unsupported,Vector3(150,0,0),"mixed")
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty(),"near superset center does not suppress a far eligible subset")
	if not service._job.is_empty():
		check(service._job.row.visuals.size()==2 and is_equal_approx(service._job.row.bounds.get_center().x,251.),"far snapshot includes exactly the eligible subset")
	var deadline:=Time.get_ticks_msec()+10000
	while not service._job.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;service._poll()
	check(service._rows.size()==1,"eligible far geometry publishes its proxy")
	service.tick(Vector3(35,0,0))
	check(service._rows.size()==1,"published proxy stays in the 200-to-240 metre hysteresis band")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	service.tick(Vector3(35,0,0))
	check(service._rows.is_empty() and a.layers==1 and b.layers==1,"active proxy still observes live material changes inside the hysteresis band")
	material.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED
	service.tick(Vector3.ZERO)
	deadline=Time.get_ticks_msec()+10000
	while not service._job.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;service._poll()
	check(service._rows.size()==1,"restoring material permits far publication again")
	a.hide()
	check(service._rows.is_empty() and b.layers==1,"hiding a source withdraws the proxy immediately")
	await discard(scene)
	# Distance uses three-dimensional transformed mesh bounds, not node origin.
	scene=world();service=scene.get_node("Proxy")
	var elevated:=BoxMesh.new();elevated.material=material
	a=source(scene,elevated,Vector3(150,200,0),"height")
	b=source(scene,elevated,Vector3(152,200,0),"height")
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty(),"height contributes to the original three-dimensional admission distance")
	await discard(scene)
	scene=world();service=scene.get_node("Proxy")
	var offset_mesh:=ArrayMesh.new();var offset_arrays:Array=arrays.duplicate(true)
	var vertices:PackedVector3Array=offset_arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():vertices[i]+=Vector3(100,0,0)
	offset_arrays[Mesh.ARRAY_VERTEX]=vertices
	offset_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,offset_arrays);offset_mesh.surface_set_material(0,material)
	source(scene,offset_mesh,Vector3(150,0,0),"offset")
	source(scene,offset_mesh,Vector3(152,0,0),"offset")
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty(),"near node origins do not hide far offset mesh bounds")
	await discard(scene)
	result.checks=checks;result.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PROXY_DISTANCE_ADMISSION ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
