extends SceneTree
const Materials=preload("res://scripts/world3d/wind_material.gd")
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
const Prepare=preload("res://scripts/world3d/wind_material_preparer.gd")
var checks:Array=[]
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks.append({"ok":value,"label":label})
	if not value:failures+=1;print("FAIL ",label)
func fixture(source:StandardMaterial3D)->Dictionary:
	var view:=SubViewport.new();view.own_world_3d=true;root.add_child(view)
	var scene:=Node3D.new();view.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera)
	var runtime:=Runtime.new();scene.add_child(runtime);runtime.camera=camera;runtime.cached_variants_only=true;runtime.set_physics_process(false)
	var mesh:=PlaneMesh.new();mesh.material=source
	var node:=MeshInstance3D.new();node.mesh=mesh;scene.add_child(node)
	node.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}});Response.register(node)
	return {"view":view,"runtime":runtime,"node":node,"source":source}
func progress(items:Array)->void:
	for f:Dictionary in items:
		if is_instance_valid(f.runtime):f.runtime._physics_process(.36)
func settle(items:Array)->bool:
	var until:=Time.get_ticks_msec()+30000
	while Materials.background_profile().pending>0 and Time.get_ticks_msec()<until:
		progress(items);await process_frame
	progress(items)
	for i in 3:await process_frame;progress(items)
	return Materials.background_profile().pending==0
func run()->void:
	Materials.shaders.clear()
	var gate:=Semaphore.new();Materials.preparation_test_gate=gate
	var first:=StandardMaterial3D.new();first.albedo_color=Color.RED
	var second:=StandardMaterial3D.new();second.albedo_color=Color.BLUE
	var a:=fixture(first);var b:=fixture(second)
	a.runtime.refresh();b.runtime.refresh()
	var started:Dictionary=Materials.background_profile()
	check(started.started==1 and started.pending==1 and started.active==1,"two worlds share one pending shader task for the same variant")
	check(a.node.get_active_material(0)==first and b.node.get_active_material(0)==second,"both worlds remain visible with their exact authored materials while worker is blocked")
	var other:=StandardMaterial3D.new();other.cull_mode=BaseMaterial3D.CULL_FRONT
	var abandoned:=fixture(other);abandoned.runtime.refresh()
	check(Materials.background_profile().started==1 and Materials.background_profile().pending==2,"a different variant queues without starting a second cold shader task")
	var cancelled_key:=Materials.variant_key(other)
	var dead_runtime:WeakRef=weakref(abandoned.runtime);abandoned.view.free()
	check(dead_runtime.get_ref()==null,"retiring a queued consumer destroys its runtime without joining the blocked task")
	var frames:=0
	for i in 8:
		await process_frame;frames+=1
		a.runtime._physics_process(.36);b.runtime._physics_process(.36)
	check(frames==8 and Materials.background_profile().completed==0,"main loop keeps advancing while cold shader worker is deliberately blocked")
	var covered:=Prepare.new();covered.enqueue(a.runtime.pending_specs())
	covered.step_covered(true)
	check(covered.has_pending() and covered.snapshot().cold_variants==0,"covered preparation yields to an existing task instead of duplicating or joining it")
	var timing:Dictionary={}
	var material:ShaderMaterial=Materials.make(first,Response.defaults(),a.node.get_aabb(),timing)
	check(material==null and timing.cache_miss,"legacy factory does not synchronously duplicate an in-flight variant")
	Materials.preparation_test_gate=null;gate.post()
	check(await settle([a,b]),"background preparation completes without a presentation cover")
	var finished:Dictionary=Materials.background_profile()
	check(finished.started==1 and finished.completed==1 and finished.main_thread_builds==0,"exactly one real shader preparation runs on a worker and publishes once")
	check(finished.cancelled==1 and not Materials.shaders.has(cancelled_key),"queued variant with no living consumer is cancelled before compilation")
	check(a.runtime.capability_status().ready and b.runtime.capability_status().ready,"both worlds bind their receivers on ordinary sliced refresh after publication")
	var ma:ShaderMaterial=a.node.get_active_material(0);var mb:ShaderMaterial=b.node.get_active_material(0)
	check(ma!=null and mb!=null and ma!=mb and ma.shader==mb.shader,"receivers reuse the prepared shader while keeping independent material state")
	check(ma.get_shader_parameter("tint")==Color.RED and mb.get_shader_parameter("tint")==Color.BLUE,"per-instance authored uniforms survive shared background preparation")
	await covered.finish_covered(self)
	check(covered.snapshot().cold_variants==0,"waiting covered queue reuses the published shader instead of rebuilding it")
	a.runtime.set_enabled(false)
	check(a.node.get_active_material(0)==first and not a.node.has_meta("wind_original"),"disabling wind restores exact source material after asynchronous activation")
	a.view.free();b.view.free()
	# Retiring the active owner also must not retain the scene or wait on main.
	var live_source:=StandardMaterial3D.new();live_source.texture_repeat=false
	var live:=fixture(live_source);var active_owner:WeakRef=weakref(live.runtime)
	var last_gate:=Semaphore.new();Materials.preparation_test_gate=last_gate
	live.runtime.refresh();live.view.free()
	check(active_owner.get_ref()==null and Materials.background_profile().active==1,"active worker owns no scene node and does not block scene destruction")
	Materials.preparation_test_gate=null;last_gate.post()
	check(await settle([]),"orphaned active task safely completes its shared resource handoff")
	var result:={"checks":checks,"passed":checks.size()-failures,"failed":failures,"background":Materials.background_profile()}
	var out:=OS.get_environment("RMMO_WIND_BACKGROUND_OUTPUT")
	if not out.is_empty():FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("WIND_VARIANT_BACKGROUND ",JSON.stringify(result));quit(1 if failures else 0)
