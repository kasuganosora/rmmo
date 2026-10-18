extends SceneTree
const Cursor=preload("res://scripts/world3d/instance_spec_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Node3D:
	var holder:=Node3D.new();holder.transform=Transform3D(Basis.from_euler(Vector3(.1,.3,-.1)).scaled(Vector3(1.2,.8,1.1)),Vector3(312,.2,-81))
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,3,1)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.3,.5,.7);mesh.material=material
	for i:int in 128:
		var parent:=MeshInstance3D.new();parent.name="part%d"%i;parent.mesh=mesh
		parent.transform=Transform3D(Basis.from_euler(Vector3(.03*i,.02*i,-.01*i)),Vector3(i*.2,i*.04,i*-.3))
		parent.set_meta("extras",{"uuid":"source__part%d"%i,"rmmo_collision":"walk"})
		holder.add_child(parent)
		var child:=MeshInstance3D.new();child.name="child";child.mesh=mesh
		child.transform=Transform3D(Basis.from_euler(Vector3(.2,-.3,.1)).scaled(Vector3(.7,1.3,.9)),Vector3(1,2,3))
		child.set_meta("extras",{"uuid":"source__child%d"%i,"rmmo_collision":"walk"})
		parent.add_child(child)
	return holder
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	check(DisplayServer.get_name()!="headless","private GPU fixture uses actual mesh resources")
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for local_collision:bool in [false,true]:
		var holder:=fixture();var expected:Array=[]
		if local_collision:Deferred._collect_collision_asset(holder,expected)
		else:Deferred._collect(holder,Transform3D.IDENTITY,expected)
		for i:int in expected.size():expected[i].map_draw_order=150+i
		var reference:WeakRef=weakref(holder);var cursor:=Cursor.new();cursor.begin(holder,local_collision,150)
		var done:=cursor.advance(1)
		check(not done and cursor.specs.size()<expected.size(),"large namespace remains private after first bounded step: "+str(local_collision))
		while not done:await process_frame;done=cursor.advance(100)
		check(cursor.specs==expected,"sliced transform, exact collision multiplication, material and UUID order match synchronous collector: "+str(local_collision))
		check(reference.get_ref()==null and cursor.holder==null and cursor.nodes.is_empty() and cursor.visited.is_empty(),"complete projection frees all original private nodes before publication: "+str(local_collision))
		check(cursor.profile.slices>2,"large collection and child-before-parent destruction both span slices: "+str(local_collision))
		cursor.dispose();expected.clear()
	for steps:int in [1,100,500]:
		var holder:=fixture();var reference:WeakRef=weakref(holder);var cursor:=Cursor.new();cursor.begin(holder,false,0)
		for i:int in steps:
			if cursor.advance(1):break
		cursor.dispose()
		check(reference.get_ref()==null and cursor.specs.is_empty() and cursor.nodes.is_empty() and cursor.visited.is_empty(),"cancellation owns and releases partially collected or dismantled hierarchy after "+str(steps)+" steps")
	var queue:=Deferred.new();root.add_child(queue)
	var holder:=fixture();var reference:WeakRef=weakref(holder);var cursor:=Cursor.new();cursor.begin(holder,false,0);cursor.advance(1)
	var token:=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new()
	check(queue._admission.reserve("fixture",{"estimated_bytes":65536,"exclusive":false}),"actual queue holds admission through private multi-frame preparation")
	queue._jobs.fixture={"token":token,"instance_preparation":{"uuid":"withdrawn","cursor":cursor},"result":{}}
	queue._prepared_paths.fixture=true
	check(queue._publication_ready().is_empty() and reference.get_ref()==null and not queue._jobs.fixture.has("instance_preparation"),"withdrawn demand releases its private preparation without publishing a partial namespace")
	queue._discard_job("fixture")
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"normal discard returns the actual queue's private preparation lease")
	queue.free()
	print("INSTANCE_SPEC_PREPARATION checks=",checks," failures=",failures);quit(1 if failures else 0)
