extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	var doc:=Doc.new()
	var ids:Array=[]
	for x in [995.0,1055.0]:
		var id:=doc.add_box("block",Vector3(x,2,0),Vector3(2,4,2));ids.append(id)
		var r:Dictionary=doc._find(id);r.building={"id":"long_house","part":id,"role":"wall","floor":0,"floor_y":0}
	var prop:=doc.add_box("block",Vector3(400,1,0),Vector3(1,2,1))
	var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene)
	Stream.sync(scene,host,Vector3.ZERO)
	var meshes:Dictionary=scene.get_meta("stream_meshes");var bodies:Dictionary=scene.get_meta("stream_bodies")
	check(ids.all(func(id):return meshes.has(id)),"whole building visible at one kilometre, including its far side")
	check(not meshes.has(prop),"ordinary distant prop retains its own residency range")
	check(ids.all(func(id):return not bodies.has(id)),"one-kilometre rendering does not load distant collision")
	var batcher=scene.get_node("GroundRenderBatches");var original_syncs:int=batcher.sync_count
	for x in [31.,33.,65.,350.,650.,950.,1020.]:
		Stream.sync(scene,host,Vector3(x,0,0))
		check(ids.all(func(id):return meshes.has(id)),"house survives chunk crossing "+str(x))
		if x<=65:check(batcher.sync_count==original_syncs,"unchanged distant house visuals do not rebuild batches")
	check(ids.all(func(id):return bodies.has(id)),"nearby house collision becomes resident")
	Stream.sync(scene,host,Vector3(-200,0,0))
	check(ids.all(func(id):return not meshes.has(id) and not bodies.has(id)),"complete distant house and collision unload outside range")
	Stream.sync(scene,host,Vector3.ZERO)
	check(ids.all(func(id):return meshes.has(id)),"return trip restores complete house")
	var camera=preload("res://scripts/world3d/third_person_camera.gd").new()
	camera.bind_map(scene,{})
	check(not camera.cutaway.enabled,"third-person upper-storey hiding is off by default")
	camera.free();host.free()
	print("HOUSE_RESIDENCY_FINISHED failures=",failed);quit(1 if failed else 0)
