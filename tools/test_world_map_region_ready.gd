extends SceneTree
## Headless retained-command readiness; no image capture or GPU scene.
const View=preload("res://scripts/ui/world_map_view_3d.gd")
const Data=preload("res://scripts/world3d/world_map_data.gd")
class Player extends Node3D:
	var click_target:Variant=null
	var _route:Array=[]
class World extends Node:
	var _map_data=Data.new()
	var _player:=Player.new()
	var _combat:Dictionary={"actors":{}}
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if value:passed+=1
	else:failures+=1
func shape_at(position_:Vector2)->Dictionary:
	var rect:=Rect2(position_,Vector2(2,2))
	return {"bounds":rect,"polygon":PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position]),"color":Color.GREEN}
func run()->void:
	var world:=World.new();root.add_child(world);world.add_child(world._player)
	world._map_data.bounds=Rect2(-120,-120,240,240)
	world._map_data.shapes=[shape_at(Vector2.ZERO),shape_at(Vector2(100,100))]
	var view:=View.new();view.size=Vector2(280,200);root.add_child(view);view.set_process(false);view.bind_world(world,true)
	view._terrain.set_process(false)
	check(not view.region_is_prepared(Vector2.ZERO),"target reports unrecorded draw IDs before preparation")
	var width:float=1.0/view.scale_factor();view._terrain._record(0,width)
	check(view.region_is_prepared(Vector2.ZERO) and not view.terrain_is_prepared(),"prepared target does not depend on unrecorded remote commands")
	world._map_data.shapes.append(shape_at(Vector2(90,90)))
	check(view.region_is_prepared(Vector2.ZERO),"appending remote background shapes keeps target commands ready")
	world._map_data.shapes.append(shape_at(Vector2(4,0)))
	check(not view.region_is_prepared(Vector2.ZERO),"new target footprint invalidates local readiness until recorded")
	view._terrain._record(3,width)
	check(view.region_is_prepared(Vector2.ZERO),"recording target addition restores readiness without waiting for remote work")
	view.radius*=.5
	check(not view.region_is_prepared(Vector2.ZERO),"zoom rejects retained commands with stale outline width")
	width=1.0/view.scale_factor();view._terrain._record(0,width);view._terrain._record(3,width)
	check(view.region_is_prepared(Vector2.ZERO),"exact new one-pixel width satisfies target readiness")
	world._map_data.rebuild_shape_index()
	check(not view.region_is_prepared(Vector2.ZERO),"same-count map revision invalidates target commands")
	check(not view.region_is_prepared(Vector2(INF,0)),"nonfinite region cannot claim readiness")
	view.free();world.free()
	print("WORLD_MAP_REGION_READY_FINISHED passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
