extends SceneTree
const Prepare=preload("res://scripts/world3d/wind_material_preparer.gd")
const Materials=preload("res://scripts/world3d/wind_material.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
var failures:=0
var checks:=0

func check(value:bool,message:String)->void:
	checks+=1
	print("PASS " if value else "FAIL ",message)
	if not value:failures+=1

func _initialize()->void:call_deferred("run")

func spec(source:Material)->Dictionary:
	var mesh:=PlaneMesh.new();mesh.material=source
	return {"mesh":mesh,"extras":{"rmmo_wind":Response.defaults().merged({"profile":"cloth","anchor":"left","shelter":false},true)}}

func run()->void:
	Materials.shaders.clear()
	var source:=StandardMaterial3D.new()
	var same:=StandardMaterial3D.new();same.albedo_color=Color.RED
	var other:=StandardMaterial3D.new();other.cull_mode=BaseMaterial3D.CULL_DISABLED
	var first:=spec(source);var second:=spec(same);var third:=spec(other)
	check(Materials.variant_key(source)==Materials.variant_key(same) and Materials.variant_key(other)!=Materials.variant_key(source),"variant identity excludes per-instance uniforms and includes render state")
	var queue:=Prepare.new();queue.enqueue([first,second,third])
	var blocked:Dictionary=queue.step_covered(false)
	check(blocked.materials==0 and Materials.shaders.is_empty() and queue.has_pending(),"uncovered step cannot submit a cold Shader or consume queued work")
	queue.step_covered(true,0,1);queue.step_covered(true,2000,0)
	check(Materials.shaders.is_empty(),"zero available time or variant allowance cannot start an indivisible call")
	var partial:Dictionary=queue.step_covered(true,2000,1)
	check(partial.cold_variants==1 and Materials.shaders.size()==1 and queue.has_pending(),"one covered step submits at most one indivisible cold variant")
	var completed:Dictionary=await queue.finish_covered(self)
	check(completed.materials==2 and completed.cold_variants==2 and Materials.shaders.size()==2,"different materials sharing a shader key warm once")
	check(not completed.pending and completed.variants.size()==2,"covered queue drains and records each cold variant")
	check(completed.preparation_span_ms==completed.elapsed_ms and completed.cpu_ms>=completed.make_ms and completed.cpu_ms<=completed.preparation_span_ms,"work CPU and cold make time remain distinct from the full covered preparation span")
	for row:Dictionary in completed.variants:
		check(row.has("shader_code_ms") and row.has("material_shader_ms") and row.has("uniforms_ms") and row.has("textures_ms") and row.total_ms>=0,"shader code, material assignment, uniforms and textures have independent timings")
	queue.enqueue([first,second]);await queue.finish_covered(self)
	check(queue.snapshot().cold_variants==2,"re-enqueueing published specs cannot repeat the cold shader preparation")
	var cancelled:=Prepare.new();cancelled.enqueue([third]);cancelled.cancel();cancelled.enqueue([first]);cancelled.step_covered(true)
	check(not cancelled.has_pending() and cancelled.snapshot().materials==0,"cancel discards source snapshots and prevents later submission")
	var mid_source:=StandardMaterial3D.new();mid_source.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var mid_spec:=spec(mid_source);var mid_original:Dictionary=mid_spec.duplicate(true)
	var mid_queue:=Prepare.new();mid_queue.enqueue([mid_spec]);mid_queue.step_covered(true,2000,1)
	check(not mid_queue._spec.is_empty(),"cancel fixture holds an active authored record after its first surface")
	mid_queue.cancel()
	check(mid_spec==mid_original and not mid_spec.is_empty() and mid_queue._spec.is_empty(),"mid-record cancellation releases the queue reference without clearing authored data")
	var missing:=StandardMaterial3D.new();missing.texture_repeat=false
	var missing_spec:=spec(missing)
	var key:=Materials.variant_key(missing)
	var timing:Dictionary={}
	check(Materials.make(missing,missing_spec.extras.rmmo_wind,missing_spec.mesh.get_aabb(),timing,false)==null and timing.cache_miss and not Materials.shaders.has(key),"cache-only material factory cannot create a missing shader")
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera)
	var runtime:=Runtime.new();scene.add_child(runtime);runtime.camera=camera;runtime.set_physics_process(false);runtime.set_meta("profile_frame",true)
	check(not runtime.cached_variants_only,"legacy/default runtime policy remains unchanged")
	runtime.cached_variants_only=true
	# A receiver with one ready and one missing surface must remain wholly static.
	var mesh:=ArrayMesh.new()
	for item:Dictionary in [first,missing_spec]:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,item.mesh.get_mesh_arrays())
		mesh.surface_set_material(mesh.get_surface_count()-1,item.mesh.material)
	var receiver:=MeshInstance3D.new();receiver.mesh=mesh;receiver.set_meta("extras",first.extras);scene.add_child(receiver);Response.register(receiver)
	var before:int=Materials.shaders.size()
	runtime.refresh()
	check(runtime.receivers.is_empty() and not receiver.has_meta("wind_original") and receiver.get_surface_override_material(0)==null and receiver.get_surface_override_material(1)==null,"a multisurface cache miss leaves all authored materials installed")
	var capability:Dictionary=runtime.capability_status()
	check(capability.pending_receivers==1 and capability.pending_variants==[key] and capability.reason=="covered_variant_preparation_pending","cold miss exposes a bounded retryable capability instead of silent loss")
	check(Materials.shaders.size()==before and runtime.get_meta("refresh_timing").bound==0,"gameplay refresh does not create cold shaders or count static misses as bound")
	var pending:Array=runtime.pending_specs()
	check(pending.size()==1 and pending[0].mesh==mesh,"later cover receives only already-resident pending receiver resources")
	var later:=Prepare.new();later.enqueue(pending);await later.finish_covered(self)
	check(Materials.variant_is_prepared(key),"later covered transaction completes previously missing variant")
	runtime.refresh()
	check(runtime.receivers.size()==1 and runtime.capability_status().pending_receivers==0,"pending receiver automatically binds after the covered variant becomes ready")
	var phases:Dictionary=runtime.get_meta("refresh_timing").bind_details[0]
	check(phases.has("install_ms") and phases.has("shared_state_ms") and phases.materials.size()==2 and not phases.materials[0].cold and not phases.materials[1].cold,"runtime reports material, install and shared-state phases separately")
	runtime.set_enabled(false)
	check(receiver.get_surface_override_material(0)==null and receiver.get_surface_override_material(1)==null and not receiver.has_meta("wind_original"),"disabling after deferred activation restores the exact authored row")
	runtime.set_enabled(true);runtime.set_physics_process(false)
	var abandoned_source:=StandardMaterial3D.new();abandoned_source.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var abandoned_spec:=spec(abandoned_source)
	var abandoned:=MeshInstance3D.new();abandoned.mesh=abandoned_spec.mesh;abandoned.set_meta("extras",abandoned_spec.extras);scene.add_child(abandoned);Response.register(abandoned)
	runtime.refresh();check(runtime.capability_status().pending_receivers==1,"new post-entry variant remains explicitly pending")
	abandoned.free();check(runtime.capability_status().pending_receivers==0,"retired pending receiver is not retained by the capability queue")
	scene.free()
	print("test_wind_covered_variants: ",checks-failures," PASS / ",failures," FAIL")
	quit(0 if failures==0 else 1)
