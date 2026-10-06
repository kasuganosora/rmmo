extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	var doc:=Doc.new()
	for i in 24:
		for part in 5:
			var id:=doc.add_box_silent("block",Vector3(i*120-1400+part*4,2,0),Vector3(3,4,3))
			var r:Dictionary=doc._find(id);r.building={"id":"house_%d"%i,"part":id,"role":"wall","floor":part%2,"floor_y":0}
			if part==4:r.collision="none"
	for i in 30:doc.add_box_silent("block",Vector3(i*12-180,1,20),Vector3(5,2,5))
	var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene)
	Stream.sync(scene,host,Vector3.ZERO)
	# Interrupt planning/apply with another target, including a kilometre jump.
	for x in [33.,66.,-65.,1050.,1083.,1018.,-1150.,-1080.,0.]:Stream.sync(scene,host,Vector3(x,0,0),1)
	for i in 1000:
		Stream.sync(scene,host,Vector3.ZERO,1)
		if scene.has_meta("stream_chunk"):break
	check(scene.has_meta("stream_chunk"),"interrupted stream settles")
	Stream.sync(scene,host,Vector3(33,0,0),1)
	Stream.sync(scene,host,Vector3.ZERO)
	check(scene.has_meta("stream_chunk") and scene.get_meta("stream_chunk")==Vector2i.ZERO and not scene.has_meta("stream_candidate_work"),"synchronous flush completes an interrupted candidate selection")
	var expected_host:=Node3D.new();root.add_child(expected_host);var expected:=doc.build();expected_host.add_child(expected)
	Stream.sync(expected,expected_host,Vector3.ZERO)
	for bag in ["stream_meshes","stream_bodies"]:
		var actual:Array=scene.get_meta(bag).keys();var wanted:Array=expected.get_meta(bag).keys();actual.sort();wanted.sort()
		check(actual==wanted,"delta residency equals fresh load after interrupted swaps: "+bag)
	host.free();expected_host.free();print("STREAM_DELTA_FINISHED failures=",failed);quit(1 if failed else 0)
