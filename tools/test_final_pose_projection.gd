extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func legacy(node:MeshInstance3D,pose:Transform3D)->Dictionary:
	var spec:Dictionary=Stream._spec(node)
	spec.transform=pose;spec.position=pose.origin
	var bounds:AABB=pose*node.get_aabb()
	spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(bounds.position);spec.chunk_max=Stream.chunk_key(bounds.end)
	Fixtures.prepare_spec(spec)
	return spec
func run()->void:
	var nodes:Array[MeshInstance3D]=[];var poses:Array[Transform3D]=[]
	var box:=BoxMesh.new();box.size=Vector3(2,3,.2);var cpu:=Cpu.capture(box)
	var triangles:=Cpu.new();triangles.surfaces=cpu.surfaces;triangles.materials=cpu.materials;triangles.bounds=cpu.bounds
	for i:int in 4096:
		var node:=MeshInstance3D.new();node.name="part%d"%i;node.mesh=cpu if i%2==0 else triangles
		node.transform=Transform3D(Basis.from_euler(Vector3(.1,.2,.3)),Vector3(i%100-50,2,i/100))
		var extra:Dictionary={"uuid":"instance__%d"%i,"kind":"box","rmmo_collision":"walk","building":{"id":"house%d"%(i/16),"floor":i%3,"role":"body","part":"wall"}}
		if i%3==0:extra.fixture={"id":"door%d"%i,"kind":"door","pivot":[-1,-1.5,0],"angle":90.,"open":.37}
		node.set_meta("extras",extra);node.set_meta("ground_batch_record",extra)
		poses.append(Transform3D(Basis.from_euler(Vector3(.07,.7,.05)).scaled(Vector3(1.3,1.1,.8)),Vector3(256,4,-512))*node.transform)
		nodes.append(node)
	var expected:Array=[];var began:=Time.get_ticks_usec()
	for i:int in nodes.size():expected.append(legacy(nodes[i],poses[i]))
	var old_us:=Time.get_ticks_usec()-began
	var actual:Array=[];began=Time.get_ticks_usec()
	for i:int in nodes.size():actual.append(Stream._spec(nodes[i],poses[i]))
	var new_us:=Time.get_ticks_usec()-began
	check(actual==expected,"all final fields, exact transforms, swept door bounds and geometry owners match the previous two-pass projection")
	check(actual[0].mesh==cpu and actual[0].collision_mesh is BoxMesh,"render capture and exact box collision retain their distinct owners")
	check(actual[1].mesh==triangles and actual[1].collision_mesh==triangles,"identical visual and collision sources reuse the same CPU capture")
	check(actual[0].rotation==nodes[0].rotation,"legacy callers retain their local fallback rotation field")
	for node:Node in nodes:node.free()
	print("FINAL_POSE_PROJECTION ",JSON.stringify({"sources":nodes.size(),"legacy_us":old_us,"final_us":new_us,"failures":failures}))
	quit(1 if failures else 0)
