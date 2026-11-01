extends SceneTree
## Real native notifications plus optional external native-setter call receipts.
const Street=preload("res://scripts/world3d/streetlamp_lights.gd")
const Candles=preload("res://scripts/world3d/house_candle_lights.gd")
var checks:Array=[]
var work:Dictionary={}
var failures:=0

class Weather:
	extends Node
	var values:Dictionary={"time_hours":0.0}
	var night_sky:Dictionary={"ready":false}

class Watch:
	extends Node3D
	var transforms:=0
	var visibility:=0
	func _ready()->void:set_notify_transform(true)
	func _notification(what:int)->void:
		if what==NOTIFICATION_TRANSFORM_CHANGED:transforms+=1
	func on_visibility()->void:visibility+=1

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func watch(light:OmniLight3D)->Watch:
	var result:=Watch.new();light.add_child(result)
	light.visibility_changed.connect(result.on_visibility)
	result.force_update_transform();result.transforms=0;return result
func flush(watches:Array)->void:
	for w:Watch in watches:w.force_update_transform()
func reset(watches:Array,controller:Node)->void:
	flush(watches)
	for w:Watch in watches:w.transforms=0;w.visibility=0
	if counted(controller):
		controller.get("_night_probe_calls").clear()
		controller.set("_night_getter_calls",0)
func counted(controller:Node)->bool:
	return controller.get_property_list().any(func(p):return p.name=="_night_probe_calls")
func receipt(watches:Array,controller:Node)->Dictionary:
	flush(watches)
	var result:Dictionary={"native_transform_notifications":0,"native_visibility_signals":0}
	for w:Watch in watches:
		result.native_transform_notifications+=w.transforms;result.native_visibility_signals+=w.visibility
	if counted(controller):
		result.native_setter_calls=controller.get("_night_probe_calls").duplicate()
		result.native_position_getter_calls=controller.get("_night_getter_calls")
	return result
func box(parent:Node,at:Vector3)->MeshInstance3D:
	var result:=MeshInstance3D.new();result.mesh=BoxMesh.new();parent.add_child(result);result.position=at;return result
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	await street_case()
	await candle_case()
	await occlusion_case()
	await transformed_parent_case()
	var report:Dictionary={"checks":checks,"passed":checks.size()-failures,"failed":failures,"work":work,
		"street_sha256":FileAccess.get_sha256("res://scripts/world3d/streetlamp_lights.gd"),
		"candle_sha256":FileAccess.get_sha256("res://scripts/world3d/house_candle_lights.gd"),
		"scope":"headless native property/notification and physics contract; no GPU/image/FPS claim"}
	var out:=OS.get_environment("RMMO_NIGHT_LIGHT_TEST_OUTPUT")
	if not out.is_empty():
		var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("NIGHT_LIGHT_STATE_RESULT ",JSON.stringify(report))
	quit(0 if failures==0 else 1)

func street_case()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var weather:=Weather.new();scene.add_child(weather)
	var camera:=Camera3D.new();scene.add_child(camera)
	var sources:Array=[]
	for i in 8:
		var source:=box(scene,Vector3(i+1,0,0))
		source.set_meta("extras",{"rmmo_model_light":{"position":[0,0,0],"color":[1,.8,.5],"range":5.5,"energy":.18,"flame":true,"indoor":i==7}})
		Street.register(source);sources.append(source)
	var controller:=Street.new();controller.weather=weather;controller.camera=camera;scene.add_child(controller);controller.set_process(false);controller.refresh()
	check(controller.fixtures.size()==8 and controller.lights.size()==8,"model sockets create one persistent light each")
	check(controller.lights.filter(func(l):return l.visible).size()==6,"model socket budget remains six")
	check(controller.lights.filter(func(l):return l.visible and l.shadow_enabled).size()==2,"selected model shadow budget remains two")
	var ids:Array=controller.lights.map(func(l):return l.get_instance_id())
	var watches:Array=[]
	for light:OmniLight3D in controller.lights:watches.append(watch(light))
	reset(watches,controller)
	for i in 3:controller.refresh();flush(watches)
	work.street_steady=receipt(watches,controller)
	check(work.street_steady.native_visibility_signals==0,"steady selected model lights cause zero native visibility changes")
	check(work.street_steady.native_transform_notifications==0,"steady model lights cause zero native transform notifications")
	if counted(controller):
		check(work.street_steady.native_setter_calls.get("shadow_enabled",0)==0,"steady model lights call native shadow setter zero times")
		check(work.street_steady.native_setter_calls.get("global_position",0)==0,"steady model lights call native position setter zero times")
		check(work.street_steady.native_position_getter_calls==24,"model observer getter called once per fixture refresh")
	check(controller.lights.map(func(l):return l.get_instance_id())==ids,"steady model light RIDs/nodes retained")
	check(controller.fixtures.values().all(func(f):return f.glow.mesh==Candles.flame_mesh() and f.glow.visible),"all eligible authored flames retain shared mesh regardless of light rank")
	check(controller.lights.all(func(l):return is_equal_approx(l.light_energy,.18) and l.light_color==Color(1,.8,.5) and is_equal_approx(l.omni_range,5.5)),"model light energy/color/range unchanged")
	var first:Dictionary=controller.fixtures[sources[0].get_instance_id()]
	reset(watches,controller);sources[0].position.z=2;controller.refresh();flush(watches)
	check(first.light.global_position==sources[0].global_position,"model light follows real source movement immediately")
	check(receipt(watches,controller).native_transform_notifications>0,"real movement still reaches native transform notification")
	sources[0].hide();controller.refresh();check(not first.light.visible and not first.glow.visible,"hidden model source closes light and flame in current refresh")
	sources[0].show();controller.refresh();check(first.light.visible and first.glow.visible,"visible source restores in current refresh")
	camera.position=Vector3(9,0,0);controller.refresh()
	check(not first.light.visible and controller.fixtures[sources[7].get_instance_id()].light.visible,"camera reranking disables old selection and admits new one")
	check(not controller.fixtures[sources[1].get_instance_id()].light.visible and controller.fixtures[sources[7].get_instance_id()].light.shadow_enabled and controller.fixtures[sources[6].get_instance_id()].light.shadow_enabled,"old top-two model lights leave selection and new top two enable shadows immediately")
	camera.position=Vector3.ZERO;controller.refresh()
	check(first.light.visible and first.light.shadow_enabled and controller.fixtures[sources[1].get_instance_id()].light.shadow_enabled and not controller.fixtures[sources[2].get_instance_id()].light.shadow_enabled,"model lights returning to first two restore shadows and demoted selected light drops shadows")
	camera.position=Vector3(100,0,0);controller.refresh();check(controller.lights.all(func(l):return not l.visible),"camera out of range immediately clears every selected model light")
	camera.position=Vector3.ZERO;weather.values.time_hours=12.0;controller.refresh()
	check(controller.lights.filter(func(l):return l.visible).size()==1 and controller.fixtures[sources[7].get_instance_id()].light.visible,"daylight retains authored indoor model light only")
	weather.values.time_hours=0.0;controller.refresh();check(controller.lights.filter(func(l):return l.visible).size()==6,"night transition restores original budget")
	var released_light:OmniLight3D=first.light;var released_id:int=sources[0].get_instance_id();sources[0].queue_free();controller.refresh()
	check(not controller.fixtures.has(released_id) and not released_light.visible and released_light.is_queued_for_deletion(),"queued source registration released and light hidden without waiting a frame")
	await process_frame
	check(not is_instance_valid(released_light),"retired model light actually freed")
	controller.free();scene.free();await process_frame

func record(id:String,at:Vector3)->Dictionary:
	return {"uuid":id,"size":[.26,.54,.46],"position":[at.x,at.y,at.z],"rotation":[0,0,0],"collision":"none","building_shape":"candle_sconce","building":{"id":"test","floor_y":0.0}}
func candle_case()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var records:Array=[];var sources:Dictionary={}
	for i in 4:
		var id:="candle%d"%i;var at:=Vector3(i+1,2.15,0);records.append(record(id,at));sources[id]=box(scene,at)
	scene.set_meta("extras",{"rmmo_records":records});scene.set_meta("stream_meshes",sources)
	var observer:=Node3D.new();scene.add_child(observer)
	var controller:=Candles.new();scene.add_child(controller);controller.set_process(false);controller.bind_map(scene,observer);controller.set_hours(0.0)
	check(controller.fixtures.size()==4 and controller.lit_count()==2,"candle initial registration and two-shadow-light budget")
	var watches:Array=[]
	for f:Dictionary in controller.fixtures:watches.append(watch(f.light))
	reset(watches,controller)
	for i in 3:controller.refresh();flush(watches)
	work.candle_steady=receipt(watches,controller)
	check(work.candle_steady.native_visibility_signals==0,"steady selected candles cause zero native visibility changes")
	check(work.candle_steady.native_transform_notifications==0,"steady candle effects cause zero native transform notifications")
	if counted(controller):
		check(work.candle_steady.native_setter_calls.get("global_position",0)==0,"steady candles call native position setter zero times")
		check(work.candle_steady.native_position_getter_calls==12,"steady candle getter reads committed position once per fixture refresh")
	check(controller.fixtures.all(func(f):return f.effect.get_node("Flame").mesh==Candles.flame_mesh() and f.effect.visible and is_equal_approx(f.light.light_energy,.18) and f.light.shadow_enabled),"candle flame mesh/presentation/intensity/shadows remain authored")
	var first:Dictionary=controller.fixtures[0]
	reset(watches,controller);sources.candle0.position.z=1;controller.refresh();flush(watches)
	check(first.effect.global_position==sources.candle0.global_transform*first.flame,"candle effect follows live source movement immediately")
	check(receipt(watches,controller).native_transform_notifications>0,"real candle movement still propagates native transform")
	sources.candle0.hide();controller.refresh();check(not first.effect.visible and not first.light.visible,"candle source visibility change immediately closes light and flame")
	sources.candle0.show();controller.refresh();check(first.effect.visible and first.light.visible,"candle source visible again restores light and flame")
	observer.position=Vector3(5,0,0);controller.refresh();check(not first.light.visible and controller.fixtures[3].light.visible,"candle reranking closes outgoing and enables incoming light")
	observer.position=Vector3(30,0,0);controller.refresh();check(controller.lit_count()==0 and first.effect.visible,"18m light range preserves independent 45m flame range")
	observer.position=Vector3(100,0,0);controller.refresh();check(controller.fixtures.all(func(f):return not f.light.visible and not f.effect.visible),"outside both ranges hides every candle component")
	observer.position=Vector3.ZERO;controller.set_hours(12.0);check(controller.lit_count()==0 and controller.fixtures.all(func(f):return not f.effect.visible),"day transition clears candle effects immediately")
	controller.set_hours(0.0);check(controller.lit_count()==2,"night transition restores selected candles")
	sources.candle0.free();controller.refresh();check(not first.light.visible and not first.effect.visible,"freed stale source closes candle presentation without crash")
	var doomed:Dictionary=controller.fixtures[1];var effect:Node3D=doomed.effect
	controller.remove_uuids(scene,["candle1"])
	check(controller.fixtures.size()==3 and not doomed.light.visible and not effect.visible and effect.is_queued_for_deletion(),"explicit candle removal immediately retires presentation")
	await process_frame;check(not is_instance_valid(effect),"removed candle effect actually freed")
	controller.bind_map(null);check(controller.fixtures.is_empty() and controller.lit_count()==0,"rebinding null retires all candle registrations")
	controller.free();scene.free();await process_frame

func occlusion_case()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var positions:Array=[Vector3(2,2.15,0),Vector3(-3,2.15,0),Vector3(-4,2.15,0),Vector3(0,6.15,0)]
	var records:Array=[]
	for i in positions.size():
		var r:=record("priority%d"%i,positions[i]);r.building.floor_y=positions[i].y-2.15;records.append(r)
	scene.set_meta("extras",{"rmmo_records":records})
	var observer:=Node3D.new();scene.add_child(observer)
	var wall:=StaticBody3D.new();scene.add_child(wall);wall.position=Vector3(1,2,0)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(.2,4,10);wall.add_child(shape)
	for i in 2:await physics_frame
	var controller:=Candles.new();scene.add_child(controller);controller.set_process(false);controller.bind_map(scene,observer);controller.set_hours(0.0)
	check(controller.fixtures[1].light.visible and controller.fixtures[2].light.visible and not controller.fixtures[0].light.visible and not controller.fixtures[3].light.visible,"real physics ray and floor priority preserve room selection")
	observer.position.x=2.6;controller.refresh();check(controller.fixtures[0].light.visible,"crossing wall selects newly occupied room immediately")
	controller.free();scene.free();await process_frame

func transformed_parent_case()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var records:Array=[];var sources:Dictionary={}
	for i in 4:
		var id:="transform%d"%i;var at:=Vector3(1.123+i,2.153,.247+i*.13)
		records.append(record(id,at));sources[id]=box(scene,at)
		sources[id].basis=Basis.from_euler(Vector3(.13,.29,-.17)).scaled(Vector3(1.2,.9,1.1))
	scene.set_meta("extras",{"rmmo_records":records});scene.set_meta("stream_meshes",sources)
	var observer:=Node3D.new();scene.add_child(observer);observer.position=Vector3(.15,.3,-.2)
	var controller:=Candles.new();scene.add_child(controller);controller.set_process(false)
	controller.transform=Transform3D(Basis.from_euler(Vector3(.37,.91,-.21)).scaled(Vector3(1.7,.65,2.3)),Vector3(100.123,11.876,-82.456))
	controller.bind_map(scene,observer);controller.set_hours(0.0)
	var saw_rounding:=false
	for step in 3:
		if counted(controller):controller.get("_night_ray_queries").clear()
		sources.transform0.position.z+=.173
		controller.refresh()
		check(controller.lit_count()==2 and controller.fixtures[0].light.visible and controller.fixtures[1].light.visible,"nonidentity effect parent preserves actual distance selection "+str(step))
		var query_rows:Array=controller.get("_night_ray_queries") if counted(controller) else []
		if counted(controller):check(query_rows.size()==4,"nonidentity parent still casts all four real eligible rays "+str(step))
		for i in controller.fixtures.size():
			var f:Dictionary=controller.fixtures[i]
			var actual:Vector3=f.effect.global_position
			var requested:Vector3=sources[f.uuid].global_transform*f.flame
			saw_rounding=saw_rounding or actual!=requested
			check(actual.distance_to(requested)<.0001,"transformed parent commits intended flame pose within engine precision "+str(step)+"/"+str(i))
			if counted(controller):
				check(query_rows[i].to==actual,"actual physics query endpoint equals committed position exactly "+str(step)+"/"+str(i))
				check(query_rows[i].from==observer.global_position+Vector3.UP*1.4 and not query_rows[i].areas,"physics query origin and area policy remain unchanged "+str(step)+"/"+str(i))
	check(saw_rounding,"nonidentity parent exercises actual/requested float rounding difference")
	work.transformed_parent={"saw_rounding":saw_rounding,"ray_endpoint_checked":counted(controller)}
	controller.free();scene.free();await process_frame
