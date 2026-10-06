extends SceneTree
const Rig=preload("res://scripts/world3d/third_person_camera.gd")
const Settings=preload("res://scripts/world3d/environment_settings.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	var scene:=Node3D.new();root.add_child(scene)
	var slab:=MeshInstance3D.new();slab.mesh=BoxMesh.new();scene.add_child(slab)
	scene.set_meta("stream_meshes",{"slab":slab})
	var rig:=Rig.new();var camera:=Camera3D.new();camera.name="Camera3D";rig.add_child(camera);scene.add_child(rig)
	var config:=Settings.defaults();config.interior_cutaway=true
	rig.bind_map(scene,config);rig.cutaway.apply_hidden({"slab":true})
	rig._initialized=true;rig._focus=Vector3(1,2,3);rig._arm_length=2.7
	for i in 200:
		config=Settings.updated({"environment":config},{"time_hours":0 if i%2 else 12})
		rig.configure_environment(config)
	check(not slab.visible and rig.cutaway.hidden.has("slab"),"200 clock changes preserve active ceiling cutaway")
	check(rig._initialized and rig._focus==Vector3(1,2,3) and rig._arm_length==2.7,"clock changes preserve camera smoothing and arm")
	config.interior_cutaway=false;rig.configure_environment(config)
	check(slab.visible and rig.cutaway.hidden.is_empty(),"disabling cutaway restores authored visibility immediately")
	# Exact asynchronous CPU extraction and multi-frame source insertion.
	var nav:=Navigation.new();root.add_child(nav);nav.ready_for_queries=true
	var triangles:=PackedVector3Array()
	for i in 10000:
		triangles.append(Vector3(i,0,0));triangles.append(Vector3(i,0,1));triangles.append(Vector3(i+1,0,0))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=triangles
	var cpu:=Cpu.new();cpu.surfaces=[arrays]
	var pose:=Transform3D(Basis(Vector3.UP,.4),Vector3(3,2,1))
	var spec:={"mesh":cpu,"transform":pose}
	var expected:=NavigationMeshSourceGeometryData3D.new();expected.add_faces(triangles,pose)
	var actual:=NavigationMeshSourceGeometryData3D.new();var yields:=0
	while not nav._add_source(actual,spec):yields+=1;await process_frame
	var prepared:NavigationMeshSourceGeometryData3D=nav._prepare_source(actual)
	while prepared==null:await process_frame;prepared=nav._prepare_source(actual)
	actual=prepared
	check(yields>=1 and actual.get_vertices()==expected.get_vertices() and actual.get_indices()==expected.get_indices(),"worker extraction and source assembly preserve all transformed triangles exactly")
	check(nav._source_jobs.is_empty(),"completed source releases its worker")
	# A second target may interrupt the first one without sharing its cursor.
	var a:=NavigationMeshSourceGeometryData3D.new();var b:=NavigationMeshSourceGeometryData3D.new()
	check(nav._add_source(a,spec) and nav._add_source(b,spec),"full/nearby source jobs share immutable cached triangles")
	var a_result:=nav._prepare_source(a);var b_result:=nav._prepare_source(b)
	while a_result==null or b_result==null:
		await process_frame
		if a_result==null:a_result=nav._prepare_source(a)
		if b_result==null:b_result=nav._prepare_source(b)
	a=a_result;b=b_result
	check(a.get_vertices()==expected.get_vertices() and b.get_vertices()==expected.get_vertices(),"interleaved source jobs neither duplicate nor skip faces")
	var next_cpu:=Cpu.new();next_cpu.surfaces=[arrays]
	var discarded:=NavigationMeshSourceGeometryData3D.new()
	nav._add_source(discarded,spec);nav._prepare_source(discarded);nav._discard_source(discarded)
	nav._add_source(NavigationMeshSourceGeometryData3D.new(),{"mesh":next_cpu,"transform":pose})
	nav.free();check(true,"teardown joins pending and discarded source/triangle workers")
	scene.free();print("ENVIRONMENT_PERF_REGRESSIONS failures=",failures);quit(1 if failures else 0)
