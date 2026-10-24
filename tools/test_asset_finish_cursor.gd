extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Wind=preload("res://scripts/world3d/wind_response.gd")
const Lights=preload("res://scripts/world3d/streetlamp_lights.gd")
const Vegetation=preload("res://scripts/world3d/vegetation_render.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func source(count:int)->Node3D:
	var holder:=Node3D.new();holder.name="house"
	var shared:=BoxMesh.new()
	for i in count:
		var mesh:=MeshInstance3D.new();mesh.name="Part%d"%i;mesh.mesh=shared
		var extras:Dictionary={"uuid":"house__Part%d"%i}
		if i%127==0:extras.rmmo_wind={"profile":"cloth","mesh":"*","amplitude":.2,"stiffness":.4,"anchor":"top","shelter":true}
		if i%137==0:extras.rmmo_small_wall_lantern=true
		mesh.set_meta("extras",extras);holder.add_child(mesh)
	var proxy:=Node3D.new();proxy.name="Excluded";proxy.set_meta("editor_shadow_proxy",true);holder.add_child(proxy)
	var hidden:=MeshInstance3D.new();hidden.name="Hidden";hidden.mesh=shared
	hidden.set_meta("extras",{"rmmo_wind":{"profile":"cloth"},"rmmo_small_wall_lantern":true});proxy.add_child(hidden)
	return holder
func old_finish(holder:Node3D,record:Dictionary)->Node3D:
	Banner.apply(holder,record);Paint.apply(holder,record);Wind.annotate(holder,record)
	for visual in Paint.meshes(holder):Wind.register(visual);Lights.register(visual)
	return Vegetation.flatten(holder,record)
func projection(holder:Node3D)->Array:
	var result:Array=[]
	for node:Node in [holder]+holder.find_children("*","",true,false):
		var groups:Array=node.get_groups();groups.sort()
		result.append([str(holder.get_path_to(node)),node.get_meta("extras",{}).duplicate(true),groups,node.transform if node is Node3D else null])
	return result
func run()->void:
	var doc:=Doc.new();var record:Dictionary={"uuid":"house","kind":"asset","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var expected:=old_finish(source(2007),record);var actual:=source(2007)
	var samples:Array=[];var slices:=0
	if doc.has_method("begin_asset_finish"):
		var cursor:RefCounted=doc.call("begin_asset_finish",actual,record)
		var ready:=false
		while not ready:
			var began:=Time.get_ticks_usec();ready=cursor.advance(250);samples.append(Time.get_ticks_usec()-began);slices+=1
		actual=cursor.take_holder()
	else:
		var began:=Time.get_ticks_usec();actual=doc._finish_asset_instance(actual,record);samples.append(Time.get_ticks_usec()-began);slices=1
	check(projection(actual)==projection(expected),"large finish preserves exact hierarchy, transforms, authored extras and receiver groups")
	check(slices>1,"large finish is interruptible before all receiver registrations complete")
	check(actual.get_node("Excluded/Hidden").get_groups().is_empty(),"shadow proxy subtree remains excluded from receiver registration")
	expected.free();actual.free()
	for state:Dictionary in [{"profile":"off"},{"profile":"cloth","mesh":"Part1","anchor":"top"}]:
		var r:=record.duplicate(true);r.wind_response=state
		expected=old_finish(source(5),r);actual=doc._finish_asset_instance(source(5),r)
		check(projection(actual)==projection(expected),"explicit wind override keeps existing selection and removal behavior: "+str(state.profile))
		expected.free();actual.free()
	var banner:=source(3);banner.get_child(1).get_meta("extras").rmmo_banner_slot=true
	expected=banner.duplicate();expected=old_finish(expected,record);actual=doc._finish_asset_instance(banner,record)
	check(projection(actual)==projection(expected),"authored banner slot still receives collision and wind annotations")
	expected.free();actual.free()
	var crop:=Node3D.new();crop.name="house";crop.position=Vector3(4,2,1)
	var leaf:=MeshInstance3D.new();leaf.mesh=BoxMesh.new();crop.add_child(leaf)
	var crop_record:=record.duplicate(true);crop_record.vegetation_batch=true
	expected=old_finish(crop.duplicate(),crop_record);actual=doc._finish_asset_instance(crop,crop_record)
	check(actual is MeshInstance3D and projection(actual)==projection(expected) and actual.get_meta("ground_batch_record")==expected.get_meta("ground_batch_record"),"eligible crop still transfers the replacement mesh and independent batch record")
	expected.free();actual.free()
	if doc.has_method("begin_asset_finish"):
		actual=source(2007);var owner:WeakRef=weakref(actual);var cursor:RefCounted=doc.call("begin_asset_finish",actual,record)
		cursor.advance(1);cursor.dispose();actual.free()
		check(owner.get_ref()==null,"cancelled finish releases private traversal state without retaining a graph")
	print("ASSET_FINISH_CURSOR ",JSON.stringify({"checks":checks,"failures":failures,"slices":slices,"cpu_us":samples.reduce(func(a,b):return a+b,0),"max_slice_us":samples.max()}))
	quit(0 if failures==0 else 1)
