extends SceneTree
## Real published native guild; no map/source writes and no GLB import.
const Job=preload("res://scripts/world_editor/load_job.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Street=preload("res://scripts/world3d/streetlamp_lights.gd")
const Components=preload("res://scripts/world3d/model_components.gd")
const Settings=preload("res://scripts/world3d/environment_settings.gd")
class Host extends Node3D:
	var _shared_preparation_ledger=preload("res://scripts/world3d/resource_admission.gd").new()
class Weather extends Node:
	var values:Dictionary={"time_hours":22.0}
	var night_sky:Dictionary={"ready":false}
var out:=""
var rows:Array=[]
func _initialize()->void:run.call_deferred()
func vec(p:Vector3)->Array:return [p.x,p.y,p.z]
func save_json(name_:String,data:Variant)->void:
	FileAccess.open(out.path_join(name_),FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
	if not out.begins_with("D:/code/rmmo_runtime/review_artifacts/guild_pillar_light_20261101/") or DirAccess.dir_exists_absolute(out):quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(200).timeout.connect(func():quit(124))
	var host:=Host.new();root.add_child(host)
	var job:=Job.new();job.editor=host;job._timings.build={"units":{}};host.add_child(job)
	var source:="D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
	var record:={"kind":"asset","uuid":"pillar_probe","asset_path":source}
	job._begin_asset_lookahead([record])
	var result:Dictionary=await job._prepare_asset(record)
	var scene:Node3D=result.get("scene")
	if scene==null:quit(1);return
	var vp:=SubViewport.new();vp.size=Vector2i(1280,900);vp.own_world_3d=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);vp.add_child(scene)
	Components.apply(scene,{"kind":"asset","uuid":"pillar_probe"},true)
	var cam:=Camera3D.new();vp.add_child(cam);cam.current=true;cam.near=.02;cam.fov=72
	var witness:=SubViewport.new();witness.size=Vector2i(1280,900);witness.world_3d=scene.get_world_3d()
	witness.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(witness)
	var fixed:=Camera3D.new();witness.add_child(fixed);fixed.current=true;fixed.near=.02;fixed.fov=72
	fixed.position=Vector3(18,1.7,-2.2);fixed.look_at(Vector3(12.3,3.2,-8.8))
	var world:=WorldEnvironment.new();var env:=Environment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();vp.add_child(sun)
	var settings:Dictionary=Settings.updated({}, {"preset":"night","time_hours":22.0})
	Settings.apply(settings,sun,env)
	var weather:=Weather.new();vp.add_child(weather)
	var lamps:=Street.new();vp.add_child(lamps);lamps.weather=weather;lamps.camera=cam;lamps.set_process(false)
	var actor:=Node3D.new();vp.add_child(actor);actor.position=Vector3(16,0,-4.4)
	if "observer" in lamps:lamps.set("observer",actor)
	for node:Node in scene.find_children("*","MeshInstance3D",true,false):Street.register(node)
	cam.position=Vector3(18,1.7,-2.2);cam.look_at(Vector3(12.3,3.2,-8.8));lamps.refresh()
	var sockets:Array=[]
	for f:Dictionary in lamps.fixtures.values():sockets.append({"node":str(f.node.get_ref().name),"position":vec(f.light.global_position),"energy":f.light.light_energy,"range":f.light.omni_range})
	save_json("identity.json",{"source":source,"candidate":Assets.native_candidate(source),"sockets":sockets,"settings":settings})
	# The moving camera isolates light scheduling. It deliberately has no
	# collision rig: inside-mesh moving images are not gameplay evidence. The
	# fixed witness camera measures only changed room illumination. The game
	# regression separately exercises the actual camera collision arm.
	for index:int in 25:
		var angle:=float(index)*TAU/24.0
		cam.position=Vector3(16,1.7,-4.4)+Vector3(sin(angle)*3.2,.7,cos(angle)*3.2);cam.look_at(Vector3(16,1.7,-4.4))
		lamps.refresh()
		for frame:int in 6:await process_frame;await RenderingServer.frame_post_draw
		var lights:Array=[]
		for f:Dictionary in lamps.fixtures.values():lights.append({"node":str(f.node.get_ref().name),"on":f.light.visible,"shadow":f.light.shadow_enabled,"position":vec(f.light.global_position)})
		var image_:Image=vp.get_texture().get_image();image_.save_png(out.path_join("view_%02d.png"%index))
		witness.get_texture().get_image().save_png(out.path_join("fixed_%02d.png"%index))
		rows.append({"index":index,"eye":vec(cam.position),"lights":lights})
		save_json("frames.json",rows)
	print("GUILD_PILLAR_PROBE ",out," sockets=",sockets.size())
	lamps.free();witness.free();vp.free();job._clear_asset_lookahead();Assets._scenes.erase(source);host.queue_free()
	for i:int in 20:await process_frame
	quit()
