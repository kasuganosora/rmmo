extends Node
## Autonomous real-renderer stress probe. Start once via MCP; do not keep a
## game_eval coroutine open while measuring (the debugger transport adds jitter).
var output_path: String="user://stream_stress.json"
var rounds:=3
var world: Node
var field: Node
var player: Node
var stream: RefCounted
var server: Node
var camera: Camera2D
var old_zoom: Vector2
var old_atmosphere: Dictionary
var old_light: int
var old_kind: String
var old_intensity: float
var results: Array=[]
var samples: Array=[]
var slow: Array=[]
var before: Dictionary
var index: int=-1
var began: int
var previous: int
var ready_ms: float=-1
var search_ms: float=0
var points: Array[Vector2i]=[Vector2i(112,119),Vector2i(128,144),Vector2i(112,119),Vector2i(48,48),Vector2i(208,192),Vector2i(112,119)]
func _ready():
	world=get_tree().current_scene
	assert(world.name=="World")
	field=world.map_field;player=world.get_node("Player")
	stream=field._chunk_stream_module_logic
	server=load("res://scripts/net/net.gd").server()
	camera=get_viewport().get_camera_2d();old_zoom=camera.zoom
	old_atmosphere=field.last_atmosphere.duplicate(true)
	old_light=field._atm_light;old_kind=field._atm_kind;old_intensity=field._atm_intensity
	field.stream_profile_enabled=true
	_begin_stage()
func _begin_stage():
	index+=1
	samples=[];slow=[];ready_ms=-1;search_ms=0
	before=stream.stream_stats.duplicate();field.stream_frame_samples.clear()
	previous=Time.get_ticks_usec();began=previous
	var point=points[index%6] if index<rounds*6 else points[0]
	server.set_player_cell(point.x,point.y)
	player.place_at_cell(point,field);player.snap_camera()
	camera.zoom=old_zoom*(.7 if index%6==3 else (1.3 if index%6==4 else 1.0))
	field._obs_cell=point;field._refresh_chunk_set()
	if index>=rounds*6:
		var started=Time.get_ticks_usec()
		player.click_move_to(Vector2i(134,150))
		search_ms=(Time.get_ticks_usec()-started)/1000.0
func _process(_delta):
	var now=Time.get_ticks_usec()
	var elapsed: float=(now-previous)/1000.0
	samples.append(elapsed)
	if elapsed>25:slow.append({"index":samples.size()-1,"ms":elapsed})
	previous=now
	if ready_ms<0 and stream.visible_ready():ready_ms=(now-began)/1000.0
	if index>=rounds*6:
		field.set_atmosphere(2,"clear",0.0);field._weather_fx._mix=1.0
	if now-began < (6000000 if index>=rounds*6 else 4500000):return
	_finish_stage()
	if index<rounds*6:_begin_stage()
	else:
		camera.zoom=old_zoom
		field.set_atmosphere(old_light,old_kind,old_intensity)
		field._weather_fx.apply(old_atmosphere)
		field.stream_profile_enabled=false
		server.set_player_cell(112,119);player.place_at_cell(Vector2i(112,119),field);player.snap_camera()
		queue_free()
func _finish_stage():
	samples.sort()
	var over50:=0;var over100:=0;var lights:=0;var fountains:=0
	for dt in samples:
		if dt>50:over50+=1
		if dt>100:over100+=1
	for node in field._chunks.values():
		var effects=node.get_node_or_null("MaterialEffects")
		if effects!=null:
			for effect in effects.get_children():
				if effect is PointLight2D and effect.enabled:lights+=1
				if effect is Sprite2D and str(effect.name).begins_with("Fountain"):fountains+=1
	results.append({"stage":index,"mode":"night_walk" if index>=rounds*6 else "teleport_zoom_return","cell":str(player.cell),"frames":samples.size(),"p95_ms":samples[int(samples.size()*.95)],"p99_ms":samples[int(samples.size()*.99)],"max_ms":samples[-1],"over50":over50,"over100":over100,"slow":slow,"search_ms":search_ms,"visible_ready_ms":ready_ms,"before":before,"after":stream.stream_stats.duplicate(),"active":field._chunks.size(),"retired_bytes":stream.retired_bytes,"pool_bytes":stream.texture_pool.bytes,"vram_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576,"cpu_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576,"map_frames":field.stream_frame_samples.duplicate(true),"lights":lights,"fountains":fountains})
	var file=FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"complete":index>=rounds*6,"load":field.load_profile,"runs":results},"\t"))
