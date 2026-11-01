extends SceneTree
const World=preload("res://scripts/world3d/world_3d.gd")
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
const Materials=preload("res://scripts/world3d/wind_material.gd")
var checks:Array=[]
var failures:=0

class PlayWorld extends World:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
class Player extends CharacterBody3D:
	var input_locked:=false
	var geometry_blocked:=false
class Weather extends Node3D:
	var wind_objects:Node3D

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks.append({"ok":value,"label":label})
	if not value:failures+=1;print("FAIL ",label)
func run()->void:
	Materials.shaders.clear()
	var world:=PlayWorld.new();root.add_child(world)
	world._status=Label.new();world.add_child(world._status)
	world._player=Player.new();world.add_child(world._player);world._player.set_physics_process(true)
	world._combat=Node.new();world.add_child(world._combat);world._combat.set_physics_process(true)
	world._weather=Weather.new();world.add_child(world._weather)
	var camera:=Camera3D.new();world.add_child(camera)
	var wind:=Runtime.new();world._weather.add_child(wind);world._weather.wind_objects=wind
	wind.camera=camera;wind.cached_variants_only=true;wind.set_physics_process(false)
	var mesh:=PlaneMesh.new();var source:=StandardMaterial3D.new()
	source.texture_repeat=false;source.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST;mesh.material=source
	var receiver:=MeshInstance3D.new();receiver.mesh=mesh
	receiver.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}})
	world.add_child(receiver);Response.register(receiver);wind.refresh()
	check(wind.capability_status().pending_receivers==1,"real late receiver exposes an unprepared variant")
	check(receiver.get_active_material(0)==source,"pending receiver retains authored visible material")
	world._ready_for_play=true;world._preparation_sample_at=0;world._update_preparation_hint()
	await process_frame;await process_frame
	check(world.find_child("TransferLoading",true,false)==null,"late wind preparation never creates a full-screen cover")
	check(not world._transfer_pending and not world._player.input_locked,"late wind preparation never enters a transfer or locks input")
	check(world._player.is_physics_processing() and world._combat.is_physics_processing(),"late wind preparation keeps player and combat physics running")
	check(not root.disable_3d,"late wind preparation keeps the world viewport rendering")
	# SceneTree shutdown owns this graph. The old implementation has a live
	# presentation coroutine; deleting it then advancing another frame would
	# test that separate coroutine-lifetime bug instead of the cover contract.
	var result:={"checks":checks,"passed":checks.size()-failures,"failed":failures}
	var out:=OS.get_environment("RMMO_WIND_NO_COVER_OUTPUT")
	if not out.is_empty():FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("STREAMED_WIND_NO_COVER ",JSON.stringify(result));quit(1 if failures else 0)
