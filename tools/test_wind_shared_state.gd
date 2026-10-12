extends SceneTree
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func make_world()->Dictionary:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var scene:=Node3D.new();viewport.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera)
	var wind:=Runtime.new();scene.add_child(wind);wind.camera=camera;wind.set_physics_process(false)
	wind.set_shared_state_enabled(true);wind.set_meta("profile_frame",true)
	return {"viewport":viewport,"scene":scene,"camera":camera,"wind":wind}
func receiver(host:Node3D,position:Vector3,shelter:bool=false)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new();node.position=position
	node.set_meta("extras",{"rmmo_wind":{"profile":"cloth","shelter":shelter}})
	host.add_child(node);Response.register(node);return node
func state(wind:Node3D)->Color:return wind._shared_state.image.get_pixel(0,0)
func run()->void:
	var a:=make_world();var b:=make_world()
	var first:=receiver(a.scene,Vector3.ZERO,true);var second:=receiver(a.scene,Vector3(4,0,0));var other:=receiver(b.scene,Vector3.ZERO)
	a.wind.advance(Vector3(-12,2,3),11.5);b.wind.advance(Vector3(5,0,-2),27)
	a.wind.refresh();b.wind.refresh()
	var row:Dictionary=a.wind.receivers[first.get_instance_id()]
	var material:ShaderMaterial=row.materials[0]
	var original:Mesh=first.mesh
	check(a.wind.receivers.size()==2 and b.wind.receivers.size()==1,"each runtime binds only its own World3D")
	check(material.get_shader_parameter("wind_state")==a.wind.receivers[second.get_instance_id()].materials[0].get_shader_parameter("wind_state") and material.get_shader_parameter("wind_state")!=b.wind.receivers[other.get_instance_id()].materials[0].get_shader_parameter("wind_state"),"same runtime shares one texture, independent worlds never share state")
	check(state(a.wind)==Color(-12,2,3,11.5) and state(b.wind)==Color(5,0,-2,27),"linear RGBAF preserves signed/HDR wind and independent clocks")
	var updates:int=a.wind._shared_state.updates
	a.wind.advance(Vector3(-12,2,3),11.5)
	check(a.wind._shared_state.updates==updates,"paused identical state does not upload")
	a.wind.advance(Vector3(2,0,7),12.25)
	check(a.wind._shared_state.updates==updates+1 and state(b.wind)==Color(5,0,-2,27),"one state upload advances all local materials without changing another world")
	# Range/pose/mesh edits need no persistent geometry cache: every rendered
	# receiver reads current state, even if CPU membership still describes a LOD.
	first.visibility_range_end=2;a.camera.position=Vector3(0,0,15);a.wind.refresh()
	check(not a.wind._active_indices.has(first.get_instance_id()),"periodic refresh still filters active LOD membership")
	first.position=Vector3(0,0,14);first.rotation=Vector3(.2,.3,.1);first.scale=Vector3(.5,2,3)
	first.mesh=BoxMesh.new();first.custom_aabb=AABB(Vector3(-2,-1,-3),Vector3(4,2,6));first.visibility_range_end=20
	a.camera.position=Vector3(0,0,-100);a.wind.advance(Vector3(8,0,0),14)
	a.camera.position=Vector3(0,0,14);a.wind.advance(Vector3(9,0,0),15)
	check(material.get_shader_parameter("wind_state_enabled") and state(a.wind)==Color(9,0,0,15) and not a.wind._active_indices.has(first.get_instance_id()),"teleport, reversed motion and changed geometry read current state without waiting for membership scan")
	check(a.wind.get_meta("advance_timing").range_ms==0 and not a.wind.get_meta("advance_timing").has("range_detail"),"shared advance avoids synchronous range scan and stale diagnostics")
	first.mesh=original;first.position=Vector3.ZERO;first.rotation=Vector3.ZERO;first.scale=Vector3.ONE;first.custom_aabb=AABB();first.visibility_range_end=0;a.camera.position=Vector3.ZERO
	var roof:=StaticBody3D.new();roof.position=Vector3(0,3,0);a.scene.add_child(roof)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,.2,2);collision.shape=box;roof.add_child(collision)
	await physics_frame;await physics_frame;a.wind.refresh()
	check(material.get_shader_parameter("wind_exposure")==0. and a.wind.receivers[second.get_instance_id()].materials[0].get_shader_parameter("wind_exposure")==1.,"shelter changes only the covered receiver exposure")
	roof.free();await physics_frame;a.wind.refresh()
	check(material.get_shader_parameter("wind_exposure")==1.,"removed shelter restores receiver wind")
	a.wind.set_shared_state_enabled(false);a.wind.advance(Vector3(-3,0,4),31)
	check(not material.get_shader_parameter("wind_state_enabled") and material.get_shader_parameter("wind_time")==31. and material.get_shader_parameter("wind_velocity")==Vector3(-3,0,4),"legacy uniforms remain a live same-time A/B reference")
	a.wind.set_shared_state_enabled(true)
	check(material.get_shader_parameter("wind_state_enabled") and state(a.wind)==Color(-3,0,4,31),"switching back to shared mode preserves current time and direction")
	var late:=receiver(a.scene,Vector3(2,0,0));a.wind.refresh()
	check(a.wind.receivers[late.get_instance_id()].materials[0].get_shader_parameter("wind_state")==a.wind._shared_state.texture and state(a.wind).a==31.,"newly bound receivers immediately use current runtime clock")
	var late_id:=late.get_instance_id();late.free();a.wind.refresh()
	check(not a.wind.receivers.has(late_id),"freed receiver is removed without retaining its material row")
	var transferred:=receiver(a.scene,Vector3(2,0,0));a.wind.refresh();transferred.reparent(b.scene)
	a.wind.refresh();b.wind.refresh()
	check(not a.wind.receivers.has(transferred.get_instance_id()) and b.wind.receivers[transferred.get_instance_id()].materials[0].get_shader_parameter("wind_state")==b.wind._shared_state.texture,"sequential old-world restore then new-world binding uses destination clock")
	for i in 50:receiver(a.scene,Vector3(i%8,0,i/8))
	a.wind._begin_refresh();a.wind._advance_refresh(1);a.wind.advance(Vector3(-6,0,1),45)
	check(a.wind._scan_pending and state(a.wind)==Color(-6,0,1,45) and material.get_shader_parameter("wind_state")==a.wind._shared_state.texture,"pending sliced binding never freezes existing receiver clock")
	updates=a.wind._shared_state.updates;a.wind.set_enabled(false);a.wind.advance(Vector3(5,0,0),99)
	check(not a.wind._scan_pending and a.wind.receivers.is_empty() and not first.has_meta("wind_original") and first.get_surface_override_material(0)==null and a.wind._shared_state.updates==updates,"disabled runtime cancels pending slices, restores originals and stops texture uploads")
	a.wind.set_enabled(true);a.wind.set_physics_process(false);a.wind.refresh()
	check(state(a.wind)==Color(5,0,0,99) and first.has_meta("wind_original"),"reenabling binds current state rather than old paused time")
	a.wind.free()
	check(not first.has_meta("wind_original") and first.get_surface_override_material(0)==null,"runtime exit restores source materials")
	a.viewport.free();b.viewport.free()
	print("WIND_SHARED_STATE_FAILURES ",failures);quit(1 if failures else 0)
