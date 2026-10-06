extends Control
## North-up X/Z projection, shared by radar and resizable overview.
static var terrain_cache_enabled:=true
class TerrainLayer extends Node2D:
	var shapes:Array=[]
	var line_width:=1.0
	var redraws:=0
	var timing:Dictionary={}
	func _draw()->void:
		var began:=Time.get_ticks_usec() if get_parent().has_meta("profile_frame") else 0
		for shape:Dictionary in shapes:
			draw_colored_polygon(shape.polygon,shape.color)
			draw_polyline(shape.polygon,shape.color.darkened(.25),line_width,true)
		redraws+=1
		if began>0:timing={"frame":Engine.get_process_frames(),"ms":(Time.get_ticks_usec()-began)/1000.0}
var _terrain:TerrainLayer
var _background:ColorRect
var _coverage:=Rect2()
var _cached_data:RefCounted
var _cached_revision:=-1
var _cached_scale:=-1.0
var _cached_count:=-1
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
	clip_contents=true
	_background=ColorRect.new();_background.color=Color("202b30");_background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_background.show_behind_parent=true;add_child(_background);_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terrain=TerrainLayer.new();_terrain.show_behind_parent=true;add_child(_terrain)
	mouse_filter=Control.MOUSE_FILTER_STOP
	gui_input.connect(_input_map)
	tooltip_text="左键：寻路 · 右键 / Shift+左键：标记 · 滚轮：缩放 · 拖动：平移 · 双击：回到角色"

func bind_world(value:Node,small:bool=false)->void:
	world=value;radar=small
	center=world._map_data.bounds.get_center()
	if radar:center=Vector2(world._player.position.x,world._player.position.z)
	span=maxf(world._map_data.bounds.size.x,world._map_data.bounds.size.y)*1.1
	queue_redraw()

func set_view_radius(value:float)->void:
	radius=maxf(2,value*2);queue_redraw()

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

func _update_terrain(rect:Rect2,scale:float)->void:
	var data:RefCounted=world._map_data
	if _cached_data!=data or _cached_revision!=data.shape_revision or _cached_count!=data.shapes.size() or _cached_scale!=scale or not _coverage.encloses(rect):
		# Retain native canvas commands across movement; the margin avoids a
		# rebuild at every pixel while keeping the radar's GPU coverage bounded.
		_coverage=rect.grow(minf(8,maxf(rect.size.x,rect.size.y)*.25))
		_terrain.shapes=data.visible_shapes(_coverage);_terrain.line_width=1/scale
		_cached_data=data;_cached_revision=data.shape_revision;_cached_count=data.shapes.size();_cached_scale=scale
		_terrain.queue_redraw()
	_terrain.position=size*.5-center*scale;_terrain.scale=Vector2.ONE*scale

func get_draw_timing()->Dictionary:
	var result:Dictionary=get_meta("draw_timing",{}).duplicate()
	if not result.is_empty() and terrain_cache_enabled and _terrain.timing.get("frame",-1)==result.frame:
		result.terrain_ms=_terrain.timing.ms;result.ms+=_terrain.timing.ms
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
