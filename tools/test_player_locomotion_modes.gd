extends SceneTree
const Player=preload("res://scripts/game/player.gd")
const View=preload("res://scripts/char/character_view_3d.gd")
const TileId=preload("res://scripts/map/tile_id.gd")
class OpenGrid extends RefCounted:
	var streaming:=false
	var no_run:=false
	func can_pass(_x:int,_y:int,_d:int)->bool:return true
	func set_extra_blocked(_x:int,_y:int,_blocked:bool)->void:pass
	func no_dash_at(_x:int,_y:int)->bool:return no_run
func _initialize()->void:call_deferred("run")
func run()->void:
	var server=root.get_node("MockServer")
	var collision:=OpenGrid.new();server.map_collision=collision
	server.set_player_cell(10,10)
	var settings=root.get_node("GameSettings");var old:bool=settings.always_run;settings.always_run=false
	var player:=Player.new()
	var anim:=AnimatedSprite2D.new();anim.name="Anim";player.add_child(anim);anim.owner=player;anim.unique_name_in_owner=true
	anim.sprite_frames=View.control_frames();root.add_child(player);player.set_physics_process(false)
	player.cell=Vector2i(10,10);player.position=Vector2(504,504)
	assert(is_equal_approx(player.run_duration,.16) and is_equal_approx(player.step_duration,.32))
	# Execute the real keyboard branch and retain the slower tween for this step.
	Input.action_press("ui_right");player._physics_process(1.0/60);Input.action_release("ui_right")
	assert(player.moving and not player._step_running and str(anim.animation)=="walk_right")
	await create_timer(.20).timeout
	assert(player.moving,"Keyboard walk must still be moving after 0.2 seconds")
	await player.arrived_cell
	# The actual path queue runs, including its final cell.
	var path:Array[Vector2i]=[player.cell+Vector2i.RIGHT]
	player.set_move_path(path)
	assert(player._step_running and str(anim.animation)=="dash_right")
	await create_timer(.21).timeout
	assert(not player.moving and not player.has_move_path(),"Mouse path finishes a step at the original normal speed")
	# Pressing a movement key cancels the path; current step finishes consistently,
	# and the next keyboard step changes both speed and animation to walking.
	path=[player.cell+Vector2i.RIGHT,player.cell+Vector2i(2,0)]
	player.set_move_path(path)
	Input.action_press("ui_down");player._physics_process(1.0/60)
	assert(not player.has_move_path() and player._step_running)
	await player.arrived_cell
	player._physics_process(1.0/60);Input.action_release("ui_down")
	assert(not player._step_running and str(anim.animation)=="walk_front")
	await player.arrived_cell
	collision.no_run=true
	path=[player.cell+Vector2i.RIGHT];player.set_move_path(path)
	assert(not player._step_running and str(anim.animation)=="walk_right","No-run map tile must change speed AND animation")
	await player.arrived_cell
	settings.always_run=old
	print("PASS keyboard walk, mouse run, path interruption, last path step, restricted-tile animation and durations")
	quit()
