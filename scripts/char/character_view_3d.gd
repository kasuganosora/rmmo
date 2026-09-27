extends Node2D
## Isolated 3D render composited at the same feet anchor as a 2D map character.
const Model = preload("res://scripts/char/character_model_3d.gd")
const MV = preload("res://scripts/char/mv_generator.gd")
# Reduce map actors by roughly one head, keeping the feet anchor and proportions.
const WORLD_RENDER_SCALE:float=.42*1.30*.82
var viewport: SubViewport
var model: Node3D
var camera: Camera3D
var display: Sprite2D
var driver: AnimatedSprite2D
var portrait_mode:=false
var render_scale:=.42
var _wide_action:=false
var _last_map_position:=Vector2.ZERO
var _map_position_valid:=false

static func enabled()->bool:return bool(ProjectSettings.get_setting("rmmo/characters_3d",true))
static func equipment_parts(gender:String,snapshot:Array,catalog=null)->Dictionary:
	var paperdoll=load("res://scripts/char/paperdoll_look.gd")
	var parts:Dictionary=paperdoll.equipment_to_mv_parts(gender,snapshot,catalog)
	# Legacy 2D variant numbers do not identify the new 3D garment assets.
	for category in ["Clothing1","Clothing2","Boots","Belt"]:
		if parts.get(category)!=null and int(parts[category])>0:parts[category]=1
	for item in snapshot:
		if not item is Dictionary:continue
		var id:String=str(item.get("item_id",item.get("id","")))
		var definition:Dictionary=paperdoll._item_def(catalog,id)
		var model_parts:Variant=definition.get("model_parts",{})
		if model_parts is Dictionary:parts.merge(model_parts,true)
		if str(item.get("slot",""))=="weapon_main" and not id.is_empty():
			parts["WeaponMain"]=1
			parts["WeaponStyle"]=str(definition.get("animation_style","heavy" if definition.get("hand","")=="both" else "sword"))
	return parts
static var _control_frames:SpriteFrames
static func control_frames()->SpriteFrames:
	if _control_frames!=null:return _control_frames
	var frames:=SpriteFrames.new();frames.remove_animation("default")
	var blank:=Image.create(1,1,false,Image.FORMAT_RGBA8)
	var texture:=ImageTexture.create_from_image(blank)
	for action in MV.ACTIONS:
		for direction in MV.DIRECTIONS:
			var id:String=action+"_"+direction
			frames.add_animation(id);frames.set_animation_speed(id,4.0/float(Model.Motion.DURATION.get(action,2.0/3.0)))
			frames.set_animation_loop(id,action in ["idle","walk","dash"])
			for i in range(1 if action=="idle" else 4):frames.add_frame(id,texture)
	_control_frames=frames
	return frames

func _ready()->void:
	viewport=SubViewport.new();viewport.name="CharacterViewport"
	viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_2X
	add_child(viewport)
	model=Model.new();model.name="CharacterModel";viewport.add_child(model)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_CLEAR_COLOR
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("f4e7d6");settings.ambient_light_energy=.45
	environment.environment=settings;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=.9;viewport.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.1 if portrait_mode else 2.6;viewport.add_child(camera)
	camera.position=Vector3(0,1.7,4) if portrait_mode else Vector3(0,3.4,6)
	camera.look_at(Vector3(0,1.52,0) if portrait_mode else Vector3(0,.85,0));camera.current=true
	display=Sprite2D.new();display.name="RenderedCharacter";display.texture=viewport.get_texture()
	display.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;display.centered=false
	display.scale=Vector2.ONE*render_scale;add_child(display)
	call_deferred("_anchor_feet")

func _anchor_feet()->void:
	display.position=-camera.unproject_position(Vector3.ZERO)*render_scale
func _draw()->void:
	if not portrait_mode:
		draw_set_transform(Vector2.ZERO,0,Vector2(1,.32))
		draw_circle(Vector2.ZERO,11,Color(0,0,0,.18))
func configure(gender:String,custom:Dictionary,parts:Dictionary)->void:
	model.configure(gender,custom,parts)
	if portrait_mode:
		var imported:bool=model.imported_rig!=null
		camera.size=.58 if imported else 1.1
		camera.position=Vector3(0,1.75,4) if imported else Vector3(0,1.7,4)
		camera.look_at(Vector3(0,1.69,0) if imported else Vector3(0,1.52,0))
func play(action:String,direction:String,restart:bool=false,variant:String="")->void:
	model.play(action,direction,restart,variant)
	_fit_action()
func _fit_action()->void:
	if portrait_mode:return
	var wide:bool=model.action=="death"
	if wide==_wide_action:return
	_wide_action=wide
	# Keep pixels per world unit and the map anchor unchanged, but reserve room
	# for the full body falling away from its standing position.
	viewport.size=Vector2i(384,384) if wide else Vector2i(256,256)
	camera.size=3.9 if wide else 2.6
	_anchor_feet()
func _process(delta:float)->void:
	if model!=null:
		model.environment_wind=Vector2.ZERO
		# Only map actors have a driver; character creation previews stay indoors.
		if driver!=null:
			var weather:=get_tree().get_first_node_in_group("character_weather")
			if weather!=null:model.environment_wind=weather.character_wind()
	if driver!=null and model!=null:
		for action in Model.ACTIONS:
			if str(driver.animation).begins_with(action+"_"):
				model.play(action,str(driver.animation).trim_prefix(action+"_"))
				break
		_sync_locomotion(delta)
		modulate=driver.modulate
	_fit_action()
	if viewport!=null:
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _sync_locomotion(delta:float)->void:
	var distance:float=global_position.distance_to(_last_map_position) if _map_position_valid else 0.0
	_last_map_position=global_position;_map_position_valid=true
	model.locomotion_rate=1.0
	if model.imported_rig==null or model.action not in ["walk","dash"]:return
	var library=model.imported_rig.animations
	var clip:Animation=library.clips.get(model.animation_clip)
	if clip==null or not clip.has_meta("ground_speed"):return
	# Map movement is measured before camera zoom. Use the same orthographic
	# pixels/unit as the composited character, never the old 2D sprite FPS.
	var pixels_per_unit:float=float(viewport.size.y)/camera.size*render_scale
	var authored_rate:float=1.25 if model.animation_clip=="dash_female" else 1.0
	var speed:float=float(clip.get_meta("ground_speed"))*model.rig.scale.x*pixels_per_unit*authored_rate
	# A warp/server snap is not locomotion. A blocked actor advances no steps.
	model.locomotion_rate=distance/(maxf(delta,.0001)*speed) if distance<96.0 else 0.0
