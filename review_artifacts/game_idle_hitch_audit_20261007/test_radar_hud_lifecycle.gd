extends SceneTree
const Data=preload("res://scripts/world3d/world_map_data.gd")
const View=preload("res://scripts/ui/world_map_view_3d.gd")
const Settings=preload("res://scripts/game/game_settings.gd")
class Player extends Node3D:
	var click_target:Variant=null
	var _route:Array=[]
class World extends Node:
	var _map_data=Data.new()
	var _player:=Player.new()
	var _combat:Dictionary={"actors":{}}
	var _hud:Control
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func snapshot(view:Control)->Dictionary:
	var widths:Dictionary={}
	for width:float in view._terrain._widths:
		var key:=str(width);widths[key]=int(widths.get(key,0))+1
	return {"size":view.size,"radius":view.radius,"scale":view.scale_factor(),"width":1.0/view.scale_factor(),"prepared_width":view._terrain.prepared_width,"widths":widths,"recorded":view._terrain.commands_recorded}
func update_terrain(view:Control)->void:
	view._update_terrain(Rect2(view.to_world(Vector2.ZERO),view.size/view.scale_factor()),view.scale_factor())
func wait_warm(view:Control)->void:
	var frames:=0
	while is_instance_valid(view) and (view.size.x<=0 or not view.terrain_is_prepared()) and frames<600:
		await process_frame;frames+=1
	check(frames<600,"HUD background preparation completes within bounded frames")
func run()->void:
	create_timer(30).timeout.connect(func():quit(2))
	root.size=Vector2i(1280,720)
	View.preparation_profile_enabled=true
	var world:=World.new();root.add_child(world);world.add_child(world._player)
	world._map_data.title="Lifecycle fixture";world._map_data.bounds=Rect2(-100,-100,200,200)
	for y in 12:
		for x in 12:
			var rect:=Rect2(-80+x*14,-80+y*14,11,12)
			var polygon:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position])
			world._map_data.shapes.append({"bounds":rect,"polygon":polygon,"color":Color("68765b")})
	var settings=Settings.get_i();var saved_radius:int=settings.radar_view_radius if settings!=null else 11
	for configured_radius in [11,16]:
		if settings!=null:settings.radar_view_radius=configured_radius
		var hud:Control=load("res://scenes/ui/game_hud.tscn").instantiate()
		world._hud=hud;root.add_child(hud);hud.set_process(false)
		hud.bind_world_map_3d(world)
		var radar:Control=hud._radar;radar.set_process(false);radar.set_meta("profile_frame",true)
		var at_bind:=snapshot(radar)
		await wait_warm(radar)
		update_terrain(radar)
		var after_layout:=snapshot(radar)
		var recorded:int=radar._terrain.commands_recorded
		radar.center=Vector2(60,40);update_terrain(radar)
		var after_walk:=snapshot(radar)
		print("HUD_LIFECYCLE ",JSON.stringify({"configured_radius":configured_radius,"bind":at_bind,"layout":after_layout,"walk":after_walk,"timing":radar.get_draw_timing(),"prepare":radar.terrain_preparation_timing}))
		check(at_bind.recorded==0,"binding before layout records no wrong-width commands "+str(configured_radius))
		check(radar._terrain.prepared_width==1.0/radar.scale_factor(),"actual HUD prepares final layout width "+str(configured_radius))
		check(radar.radius==configured_radius*2,"actual HUD applies radius "+str(configured_radius))
		check(radar._terrain.commands_recorded==recorded,"actual HUD layout prewarms unseen shapes at final width "+str(configured_radius))
		check(not radar._terrain.is_processing(),"completed terrain stops its extra process callback")
		radar.set_view_radius(8)
		check(not radar.terrain_is_prepared(),"zoom invalidates preparation before walking")
		await wait_warm(radar)
		update_terrain(radar);recorded=radar._terrain.commands_recorded
		radar.center=Vector2(-50,-40);update_terrain(radar)
		check(radar._terrain.commands_recorded==recorded,"zoom prewarms offscreen widths before new coverage")
		world._map_data.shapes[0].color=Color.RED;world._map_data.rebuild_shape_index()
		check(not radar.terrain_is_prepared(),"same-count revision invalidates warm state")
		await wait_warm(radar)
		check(radar._terrain._revision==world._map_data.shape_revision,"warm completion includes current map revision")
		var hidden_before:int=radar._terrain.commands_recorded
		radar.hide();radar.set_view_radius(12)
		check(radar.terrain_is_prepared() and not radar._terrain.is_processing(),"hidden radar does not block loading or retain a warm callback")
		check(radar._terrain.commands_recorded==hidden_before,"hidden radius change records no commands")
		radar.show();await wait_warm(radar)
		var original_size:=radar.size
		radar.size=Vector2(0,100)
		check(radar.terrain_is_prepared() and not radar._terrain.is_processing(),"zero-size radar skips preparation without hanging")
		radar.size=original_size;await wait_warm(radar)
		radar.set_view_radius(18)
		var host:=radar.get_parent();host.remove_child(radar)
		check(radar.terrain_is_prepared() and radar._terrain._items.is_empty() and not radar._terrain.is_processing(),"removing a warming view cancels and releases resources")
		host.add_child(radar);await wait_warm(radar)
		check(radar._terrain._items.size()==world._map_data.shapes.size(),"reentering the HUD warms current map again")
		hud.free();world._hud=null
	if settings!=null:settings.radar_view_radius=saved_radius
	world.free();print("HUD_LIFECYCLE_FINISHED failures=",failures);quit(1 if failures else 0)
