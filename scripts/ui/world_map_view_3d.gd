extends Control
## North-up X/Z projection, shared by radar and resizable overview.
static var terrain_cache_enabled:=true
static var preparation_profile_enabled:=false
const TerrainLayer=preload("res://scripts/ui/world_map_terrain_layer.gd")
var _terrain:TerrainLayer
var _background:ColorRect
var _coverage:=Rect2()
var _cached_data:RefCounted
var _cached_revision:=-1
var _cached_scale:=-1.0
var _cached_count:=-1
var terrain_preparation_timing:Dictionary={}
var _preparation_size:=Vector2.ZERO
var _preparation_scale:=-1.0
var _preparation_frame:=-1
var world:Node
var radar:=false
var radius:=22.0
var center:=Vector2.ZERO
var span:=40.0
var elapsed:=0.0
var pressed:=false
var dragged:=false
var press_position:=Vector2.ZERO

func _ready()->void:
	if preparation_profile_enabled:set_meta("profile_frame",true)
	clip_contents=true
	_background=ColorRect.new();_background.color=Color("202b30");_background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_background.show_behind_parent=true;add_child(_background);_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terrain=TerrainLayer.new();_terrain.show_behind_parent=true;add_child(_terrain);_terrain.set_process(false)
	resized.connect(_terrain_layout_changed)
	visibility_changed.connect(_terrain_layout_changed)
	mouse_filter=Control.MOUSE_FILTER_STOP
	gui_input.connect(_input_map)
	tooltip_text="左键：寻路 · 右键 / Shift+左键：标记 · 滚轮：缩放 · 拖动：平移 · 双击：回到角色"

func bind_world(value:Node,small:bool=false)->void:
	world=value;radar=small
	center=world._map_data.bounds.get_center()
	if radar:center=Vector2(world._player.position.x,world._player.position.z)
	span=maxf(world._map_data.bounds.size.x,world._map_data.bounds.size.y)*1.1
	# A container may still resize again after its first draw. Preparation is
	# budgeted and restarts at the final size; gameplay waits for completion.
	_preparation_frame=-1
	_terrain_layout_changed()

func set_view_radius(value:float)->void:
	radius=maxf(2,value*2);_terrain_layout_changed()

func _process(delta:float)->void:
	if not is_instance_valid(world) or not is_visible_in_tree():return
	elapsed+=delta
	if elapsed<.1:return
	elapsed=0
	if radar:center=Vector2(world._player.position.x,world._player.position.z)
	queue_redraw()
	world._hud._refresh_map_window_info()

func scale_factor()->float:return maxf(1,minf(size.x,size.y))/(radius*2 if radar else maxf(span,1))
func to_screen(point:Vector2)->Vector2:return size*.5+(point-center)*scale_factor()
func to_world(point:Vector2)->Vector2:return center+(point-size*.5)/scale_factor()
func hint_line()->String:
	if not is_instance_valid(world):return ""
	return "%s  (%.1f, %.1f) m"%[world._map_data.title,world._player.position.x,world._player.position.z]

func _terrain_layout_changed()->void:
	_preparation_frame=-1
	if is_instance_valid(_terrain):
		if not _prepare_terrain():_terrain.set_process(false)
	queue_redraw()

func _prepare_terrain()->bool:
	if not terrain_cache_enabled or not is_inside_tree() or not is_visible_in_tree() or size.x<=0 or size.y<=0:return false
	if not is_instance_valid(world) or world._map_data==null or not is_instance_valid(_terrain):return false
	var data:RefCounted=world._map_data
	var scale:=scale_factor()
	var generation_changed:bool=_terrain._data!=data or _terrain._revision!=data.shape_revision or _terrain._items.size()!=data.shapes.size() or _preparation_size!=size or _preparation_scale!=scale or _preparation_frame<0
	if generation_changed:
		_preparation_size=size;_preparation_scale=scale;_preparation_frame=Engine.get_process_frames()
		if has_meta("profile_frame"):
			terrain_preparation_timing={"frame":_preparation_frame,"begin_usec":Time.get_ticks_usec(),"end_usec":0,"size":size,"radius":radius,"width":1.0/scale,"ready_for_play":bool(world.get("_ready_for_play")) if "_ready_for_play" in world else false}
	if _terrain.prepare(data,1.0/scale):
		_cached_data=null
		queue_redraw()
	return true

func _terrain_preparation_finished()->void:
	if has_meta("profile_frame") and not terrain_preparation_timing.is_empty() and int(terrain_preparation_timing.end_usec)==0:
		terrain_preparation_timing.end_usec=Time.get_ticks_usec()
		terrain_preparation_timing.commands_recorded=_terrain.commands_recorded
		terrain_preparation_timing.warm_slices=_terrain.warm_slices
		terrain_preparation_timing.max_warm_slice_ms=_terrain.max_warm_slice_ms

func terrain_is_prepared()->bool:
	# A hidden/zero-size radar has no drawing requirement and must not hold
	# world loading or a removed HUD open. Showing/resizing restarts warming.
	if not _prepare_terrain():return true
	var ready:bool=_terrain.is_prepared() and Engine.get_process_frames()-_preparation_frame>=2
	if ready:_terrain_preparation_finished()
	return ready

func terrain_preparation_progress()->Vector2i:
	return Vector2i(_terrain._warm_cursor,_terrain._items.size()) if is_instance_valid(_terrain) else Vector2i.ZERO

func _update_terrain(rect:Rect2,scale:float)->void:
	if not _prepare_terrain():return
	var data:RefCounted=world._map_data
	var invalid:bool=_cached_data!=data or _cached_revision!=data.shape_revision or _cached_count!=data.shapes.size()
	if invalid or _cached_scale!=scale or not _coverage.encloses(rect):
		# Only the visible coverage needs immediate exact outlines. Offscreen
		# commands are completed by the layer's one-millisecond idle slices.
		_coverage=rect.grow(minf(8,maxf(rect.size.x,rect.size.y)*.25))
		_terrain.show_shapes(data.visible_shapes(_coverage),1/scale)
		_cached_data=data;_cached_revision=data.shape_revision;_cached_count=data.shapes.size();_cached_scale=scale
	_terrain.position=size*.5-center*scale;_terrain.scale=Vector2.ONE*scale

func get_draw_timing()->Dictionary:
	var result:Dictionary=get_meta("draw_timing",{}).duplicate()
	if not result.is_empty() and terrain_cache_enabled and _terrain.timing.get("frame",-1)==result.frame:
		# show_shapes now runs inside _draw; its time is already in result.ms.
		result.terrain_ms=_terrain.timing.ms
		for key in ["recorded_delta","visible_added","visible_removed","width","prepared_width","commands_recorded"]:
			result["terrain_"+key]=_terrain.timing.get(key,0)
	return result

func _draw()->void:
	if not is_instance_valid(world) or world._map_data==null:return
	var started:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var drawn_shapes:=0
	var visible_rect:=Rect2(to_world(Vector2.ZERO),size/scale_factor())
	var scale:=scale_factor()
	_background.visible=terrain_cache_enabled;_terrain.visible=terrain_cache_enabled
	if terrain_cache_enabled:
		_update_terrain(visible_rect,scale);drawn_shapes=_terrain.shapes.size()
	else:
		draw_rect(Rect2(Vector2.ZERO,size),Color("202b30"))
		draw_set_transform(size*.5-center*scale,0,Vector2.ONE*scale)
		for shape in world._map_data.visible_shapes(visible_rect):
			drawn_shapes+=1
			draw_colored_polygon(shape.polygon,shape.color)
			draw_polyline(shape.polygon,shape.color.darkened(.25),1/scale,true)
		draw_set_transform(Vector2.ZERO)
	var drawn:Dictionary={}
	for marker in world._map_data.markers:
		drawn[marker.id]=true
		var position:Vector2=marker.position
		if world._combat.actors.has(marker.id):
			var actor=world._combat.actors[marker.id]
			if not is_instance_valid(actor) or actor.respawn_remaining>=0:continue
			position=Vector2(actor.position.x,actor.position.z)
		var color:=Color("e88170") if marker.hostile else Color("80d6a4")
		if marker.kind=="warp":color=Color("c1a1ff")
		if marker.kind=="gather":color=Color("f4ce72")
		draw_circle(to_screen(position),3 if radar else 5,color)
	# Summons enter the actor registry after the map document has loaded.
	for id in world._combat.actors:
		if drawn.has(id):continue
		var actor=world._combat.actors[id]
		if not is_instance_valid(actor) or actor.respawn_remaining>=0:continue
		var color:=Color("80d6a4") if actor.spec.extras.get("ally",false) else Color("e88170")
		draw_circle(to_screen(Vector2(actor.position.x,actor.position.z)),3 if radar else 5,color)
	for point in world._map_data.pins:
		var p:=to_screen(point)
		draw_line(p-Vector2(5,0),p+Vector2(5,0),Color.CYAN,2)
		draw_line(p-Vector2(0,5),p+Vector2(0,5),Color.CYAN,2)
	var player=world._player
	var p:=to_screen(Vector2(player.position.x,player.position.z))
	if player.click_target is Vector3:
		var route:=PackedVector2Array([p,to_screen(Vector2(player.click_target.x,player.click_target.z))])
		for waypoint in player._route:route.append(to_screen(Vector2(waypoint.x,waypoint.z)))
		draw_polyline(route,Color("f3dc85"),2,true)
	var facing:Vector3=player.global_basis.z
	var direction:=Vector2(facing.x,facing.z).normalized()
	var side:=direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([p+direction*8,p-direction*5+side*5,p-direction*5-side*5]),Color("fff1ad"))
	draw_string(ThemeDB.fallback_font,Vector2(8,18),"N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	if not radar:draw_string(ThemeDB.fallback_font,Vector2(8,size.y-8),"绿：友方  红：敌方  紫：传送  青：标记",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	if started>0:set_meta("draw_timing",{"frame":Engine.get_process_frames(),"ms":(Time.get_ticks_usec()-started)/1000.0,"shapes":drawn_shapes,"candidates":world._map_data.last_query_candidates,"indexed":world._map_data.last_query_indexed,"terrain_cached":terrain_cache_enabled,"terrain_redraws":_terrain.redraws})

func _input_map(event:InputEvent)->void:
	if not is_instance_valid(world):return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var factor:=.8 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.25
			if radar:radius=clampf(radius*factor,4,256)
			else:span=clampf(span*factor,4,maxf(world._map_data.bounds.size.x,world._map_data.bounds.size.y)*4)
		elif event.pressed and (event.button_index==MOUSE_BUTTON_RIGHT or (event.button_index==MOUSE_BUTTON_LEFT and event.shift_pressed)):
			var point:=to_world(event.position)
			for pin in world._map_data.pins:
				if to_screen(pin).distance_to(event.position)<10:point=pin;break
			world.toggle_world_map_pin(point);pressed=false
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.double_click:center=Vector2(world._player.position.x,world._player.position.z);pressed=false
			elif event.pressed:pressed=true;dragged=false;press_position=event.position
			elif pressed:
				pressed=false
				if not dragged:world.request_world_map_move(to_world(event.position))
		accept_event();queue_redraw()
	elif event is InputEventMouseMotion and pressed:
		if event.position.distance_to(press_position)>5:dragged=true
		if dragged and not radar:center-=event.relative/scale_factor()
		accept_event();queue_redraw()
