extends SceneTree
## Headless behavior regression through the real WeatherController.bind path.
## A third-person camera's orbit/collision arm is not the occupied-room anchor.
const WeatherController=preload("res://scripts/world3d/weather_controller.gd")
const Street=preload("res://scripts/world3d/streetlamp_lights.gd")
const OUTPUT_ROOT="D:/code/rmmo_runtime/review_artifacts/guild_pillar_light_20261101/"
var checks:Array=[]
var states:Array=[]
var failures:=0
var out:=""
var scene:Node3D
var camera:Camera3D
var actor:Node3D
var sun:DirectionalLight3D
var environment:Environment
var weather:Node3D
var street:Node3D
var sources:Dictionary={}
var visibility_events:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
	if not out.begins_with(OUTPUT_ROOT) or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out):
		push_error("--out must be a fresh child directory of "+OUTPUT_ROOT);quit(2);return
	if DirAccess.make_dir_recursive_absolute(out)!=OK:
		push_error("Could not create model-light observer test output directory");quit(2);return
	create_timer(90).timeout.connect(func():quit(124))
	make_scene()
	# Real bind constructs and wires the production controller. Do not replace
	# its actor propagation with a test stub or assign Street.observer directly.
	weather.bind(camera,sun,environment,actor)
	weather.values={"time_hours":0.0}
	street=weather.streetlamps
	street.refresh()
	check(weather.observer==actor,"real Weather.bind retains the game actor")
	check(street.fixtures.size()==10 and street.lights.size()==10,"all ten model sockets registered by production controller")
	var hall_origin:={"lit":["hall_1","hall_2","hall_3","hall_4","hall_5","hall_6"],"shadow":["hall_1","hall_2"]}
	var hall_east:={"lit":["hall_3","hall_4","hall_5","hall_6","hall_7","hall_8"],"shadow":["hall_7","hall_8"]}
	check(snapshot("game_initial")==hall_origin,"initial ground-floor actor selects its six hall lights and two nearest shadows")
	var original_controller_id:int=street.get_instance_id()
	var render_ids:Array=street.lights.map(func(light):return light.get_instance().get_id())
	check(render_ids.all(func(id):return id!=0),"all retained model light render-instance RIDs are valid")
	for light:OmniLight3D in street.lights:light.visibility_changed.connect(func():visibility_events+=1)
	var camera_cases:Array=[
		["orbit_left",Vector3(-4,1.7,0)],
		["orbit_right",Vector3(4,1.7,0)],
		["orbit_high",Vector3(0,5.4,-3)],
		["full_camera_arm",Vector3(0,1.7,-5)],
		["pillar_shortens_camera_arm",Vector3(.4,1.7,-.45)],
		["arm_restores",Vector3(0,1.7,-5)],
	]
	visibility_events=0
	for entry in camera_cases:
		camera.position=entry[1];street.refresh()
		check(snapshot(entry[0])==hall_origin,"stationary actor keeps lit/shadow sets during "+entry[0])
	check(visibility_events==0,"camera-only orbit and collision-arm movement emit zero light visibility transitions")
	check(street.lights.map(func(light):return light.get_instance().get_id())==render_ids,"camera-only movement preserves all light render-instance RIDs")
	for i in 5:street.refresh()
	check(visibility_events==0,"repeated stationary refreshes cause no native light visibility churn")
	# Hold camera fixed while the actor actually crosses the hall. The same
	# nearest-room calculation must now update promptly, not freeze forever.
	actor.position=Vector3(9,0,0);street.refresh()
	check(snapshot("actor_walks_east")==hall_east,"real actor movement immediately admits new lights and shadow owners")
	actor.position=Vector3.ZERO;street.refresh()
	check(snapshot("actor_returns")==hall_origin,"returning actor restores the original occupied-floor lights")
	# Raising only the camera was covered above. Raising the observer must
	# really admit the authored upstairs lights.
	actor.position=Vector3(0,4,0);street.refresh()
	var upstairs:Dictionary=snapshot("actor_upstairs")
	check(upstairs.shadow==["upstairs_1","upstairs_2"],"actor changing floor selects upstairs shadow lights immediately")
	actor.position=Vector3.ZERO;street.refresh()
	# Rebinding reuses the controller; this exercises Weather.bind's early
	# return, where forgetting to replace/reset the observer leaves stale state.
	var replacement:=Node3D.new();scene.add_child(replacement);replacement.position=Vector3(9,0,0)
	camera.position=Vector3.ZERO
	weather.bind(camera,sun,environment,replacement);street.refresh()
	check(street.get_instance_id()==original_controller_id,"rebind reuses the existing model-light controller")
	check(snapshot("replacement_actor")==hall_east,"rebind replaces actor even when the new camera remains near the old actor")
	actor.position=Vector3(-100,0,0);street.refresh()
	check(snapshot("old_actor_moves_away")==hall_east,"previous actor cannot steer lights after rebind")
	var editor_camera:=Camera3D.new();scene.add_child(editor_camera);editor_camera.position=Vector3.ZERO
	weather.bind(editor_camera,sun,environment);street.refresh()
	check(weather.observer==null,"omitting actor on real rebind resets Weather observer for editor use")
	check(snapshot("editor_initial")==hall_origin,"editor null-actor binding falls back to its current camera")
	replacement.position=Vector3(-100,0,0);street.refresh()
	check(snapshot("previous_replacement_moves")==hall_origin,"editor binding retains no influence from the previous game actor")
	editor_camera.position=Vector3(9,0,0);street.refresh()
	check(snapshot("editor_camera_east")==hall_east,"editor camera movement immediately selects its new nearby lights")
	# Both repeated transitions matter: editor -> game and game -> editor.
	actor.position=Vector3.ZERO
	weather.bind(editor_camera,sun,environment,actor);street.refresh()
	check(snapshot("editor_to_game")==hall_origin,"editor-to-game rebind restores actor anchor despite distant camera")
	weather.bind(editor_camera,sun,environment,null);street.refresh()
	check(snapshot("game_to_editor_explicit_null")==hall_east,"explicit null resets game anchor on repeated rebind")
	weather.bind(editor_camera,sun,environment,actor)
	actor.free();street.refresh()
	check(snapshot("freed_actor_fallback")==hall_east,"freed actor safely falls back to current camera")
	var report:Dictionary={"checks":checks,"passed":checks.size()-failures,"failed":failures,"states":states,
		"street_sha256":FileAccess.get_sha256("res://scripts/world3d/streetlamp_lights.gd"),
		"weather_sha256":FileAccess.get_sha256("res://scripts/world3d/weather_controller.gd"),
		"engine":Engine.get_version_info(),"scope":"Headless model-socket selection via real Weather.bind. Camera collision-arm displacement is simulated. No GPU brightness or actual guild asset claim."}
	var file:=FileAccess.open(out.path_join("report.json"),FileAccess.WRITE)
	if file==null:push_error("Could not open observer report");quit(2);return
	file.store_string(JSON.stringify(report,"  "));var error:=file.get_error();file.close()
	if error!=OK:push_error("Could not write observer report");quit(2);return
	print("MODEL_LIGHT_OBSERVER_RESULT ",JSON.stringify({"passed":report.passed,"failed":failures,"out":out}))
	scene.free();await process_frame
	quit(0 if failures==0 else 1)

func make_scene()->void:
	scene=Node3D.new();root.add_child(scene)
	camera=Camera3D.new();scene.add_child(camera)
	actor=Node3D.new();scene.add_child(actor)
	sun=DirectionalLight3D.new();scene.add_child(sun)
	environment=Environment.new()
	weather=WeatherController.new();weather.process_mode=Node.PROCESS_MODE_DISABLED;scene.add_child(weather)
	for i in 8:add_source("hall_"+str(i+1),Vector3(i+1,2.2,0))
	add_source("upstairs_1",Vector3(.5,5.4,0))
	add_source("upstairs_2",Vector3(1.5,5.4,0))

func add_source(label:String,at:Vector3)->void:
	var source:=MeshInstance3D.new();source.name=label;source.mesh=BoxMesh.new()
	scene.add_child(source);source.position=at
	source.set_meta("extras",{"rmmo_model_light":{"position":[0,0,0],"color":[1,.8,.5],"range":5.5,"energy":.18,"flame":true,"indoor":true}})
	Street.register(source);sources[label]=source

func snapshot(label:String)->Dictionary:
	var lit:Array=[];var shadow:Array=[]
	for key:String in sources:
		var id:int=sources[key].get_instance_id()
		if not street.fixtures.has(id):continue
		var light:OmniLight3D=street.fixtures[id].light
		if light.visible:
			lit.append(key)
			if light.shadow_enabled:shadow.append(key)
	lit.sort();shadow.sort()
	var result:={"lit":lit,"shadow":shadow}
	states.append({"label":label,"camera":str(street.camera.global_position),"actor":str(weather.observer.global_position) if is_instance_valid(weather.observer) else "none","selection":result.duplicate(true)})
	return result
