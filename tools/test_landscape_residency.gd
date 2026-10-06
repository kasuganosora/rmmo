extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	var doc:=Doc.new();var grounds:Array=[];var houses:Array=[]
	for x in [960.,1088.]:grounds.append(doc.add_box("ground",Vector3(x,-.1,0),Vector3(128,.2,128)))
	for x in [1018.,1038.]:
		var id:=doc.add_box("block",Vector3(x,2,0),Vector3(4,4,4));houses.append(id)
		doc._find(id).building={"id":"seam_house","role":"wall","part":id,"floor":0,"floor_y":0}
	var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene)
	Stream.sync(scene,host,Vector3(-400,0,0))
	var floating:=false
	# One operation per frame, including interrupted enter/leave changes.
	for x in [0.,-400.,32.,-400.,0.,150.,-400.]:
		for i in 200:
			Stream.sync(scene,host,Vector3(x,0,0),1)
			var meshes:Dictionary=scene.get_meta("stream_meshes")
			if houses.any(func(id):return meshes.has(id)) and not grounds.all(func(id):return meshes.has(id)):floating=true
			if scene.has_meta("stream_chunk"):break
	check(not floating,"budgeted swaps never expose a house without both supporting terrain tiles")
	Stream.sync(scene,host,Vector3.ZERO)
	var meshes:Dictionary=scene.get_meta("stream_meshes");var bodies:Dictionary=scene.get_meta("stream_bodies")
	check(houses.all(func(id):return meshes.has(id)) and grounds.all(func(id):return meshes.has(id)),"1km house and both support tiles visible together")
	check(bodies.is_empty(),"distant landscape does not load any collision")
	Stream.sync(scene,host,Vector3(1024,0,0))
	check(grounds.all(func(id):return bodies.has(id)),"nearby support becomes physical before arrival")
	host.free();print("LANDSCAPE_RESIDENCY_FINISHED failures=",failed);quit(1 if failed else 0)
