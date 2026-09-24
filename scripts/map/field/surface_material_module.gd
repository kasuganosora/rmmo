extends RefCounted
## Optional pack-authored normal/height channels, baked with the SAME tile IDs.
## A padded neighborhood lets shadows cross streamed chunk boundaries.
const Blit = preload("res://scripts/map/tile_blit.gd")
const SurfaceShader = preload("res://scripts/map/surface_lighting.gdshader")
const FountainShader = preload("res://scripts/map/fountain_water.gdshader")
const PAD := 4
var ctrl
var source_pack: RefCounted
var normals: Array = []
var heights: Array = []
var emissions: Array = []
var profile: Dictionary = {}
var terrain_textures: Dictionary = {}
var white: ImageTexture
var black: ImageTexture
var light_texture: GradientTexture2D
var tick_timer:=0.0
var last_night: float = -1.0
var prop_pack: RefCounted
var prop_tiles: Dictionary = {}
var prop_textures: Dictionary = {}
func _init(owner): ctrl=owner

# Whole props scale about their ground contact, never tile by tile. The map
# keeps its authored footprint and collision; the visual may cross chunks.
func is_scaled_prop_tile(id: int) -> bool:
	if prop_pack != ctrl.pack:
		prop_pack=ctrl.pack
		prop_tiles.clear();prop_textures.clear()
		if prop_pack != null:
			for definition in prop_pack.render_profile.get("lights",[]):
				if float(definition.get("visual_scale",1.0)) == 1.0:continue
				for tile in definition.get("sprite_tiles",[]):prop_tiles[int(tile)]=true
	return prop_tiles.has(id)

func _add_scaled_prop(root: Node2D, definition: Dictionary, origin: Vector2) -> void:
	var ids: Array=definition.get("sprite_tiles",[])
	if ids.is_empty() or float(definition.get("visual_scale",1.0))==1.0:return
	var key: int=int(definition.anchor)
	var columns: int=maxi(1,int(definition.get("sprite_columns",1)))
	var size:=Vector2i(columns*ctrl.tile_size,ceili(float(ids.size())/columns)*ctrl.tile_size)
	if not prop_textures.has(key):
		var textures=[]
		for sheets in [ctrl.pack.sheets,normals,emissions]:
			var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
			image.fill(Color(0,0,0,0))
			for i in range(ids.size()):
				Blit.blit_tile(image,int(ids[i]),(i%columns)*ctrl.tile_size,(i/columns)*ctrl.tile_size,sheets,ctrl.tile_size,ctrl.tile_size,ctrl.pack.flags,0)
			textures.append(ImageTexture.create_from_image(image))
		prop_textures[key]=textures
	var textures: Array=prop_textures[key]
	var sprite:=Sprite2D.new();sprite.name="ScaledLamp";sprite.centered=false
	var factor:=float(definition.visual_scale)
	var foot: Array=definition.get("foot_offset",[28,189])
	sprite.position=origin+Vector2(foot[0],foot[1])*(1.0-factor)
	sprite.scale=Vector2.ONE*factor;sprite.texture=textures[0];sprite.z_index=10
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.set_meta("scaled_prop",true)
	var mat:=ShaderMaterial.new();mat.shader=SurfaceShader
	mat.set_shader_parameter("normal_tex",textures[1]);mat.set_shader_parameter("emission_tex",textures[2])
	if black==null:
		var empty:=Image.create(1,1,false,Image.FORMAT_RGBA8);empty.fill(Color(0,0,0,0))
		black=ImageTexture.create_from_image(empty)
	mat.set_shader_parameter("height_tex",black)
	mat.set_shader_parameter("receive_shadows",false)
	mat.set_shader_parameter("normal_strength",float(profile.get("normal_strength",1.0)))
	sprite.material=mat;root.add_child(sprite)

func _load_channels() -> void:
	if source_pack == ctrl.pack and normals.size()==ctrl.pack.sheets.size():return
	source_pack=ctrl.pack
	prop_textures.clear()
	normals.clear();heights.clear();emissions.clear()
	profile=source_pack.render_profile if source_pack != null else {}
	if profile.is_empty():return
	terrain_textures.clear()
	for channel in ["normal_sheets","height_sheets","emission_sheets"]:
		var images: Array=[]
		for name in profile.get(channel,[]):
			var image: Image=null
			if str(name) != "":
				var path: String=source_pack.pack_dir+"/assets/tilesheet/"+str(name)+".png"
				if FileAccess.file_exists(path):image=Image.load_from_file(path)
				if image != null and channel=="height_sheets":
					image.resize(image.get_width()/4,image.get_height()/4,Image.INTERPOLATE_NEAREST)
			images.append(image)
		if channel=="normal_sheets":normals=images
		elif channel=="height_sheets":heights=images
		else:emissions=images

func bake_images(x0: int,y0: int,cw: int,ch: int) -> Dictionary:
	_load_channels()
	if profile.is_empty() or normals.size()!=ctrl.pack.sheets.size():return {}
	var ts: int=ctrl.tile_size
	var flags: PackedInt32Array=ctrl.pack.flags
	var normal_images={}
	var emission_images={}
	for bucket in ["Ground","Upper"]:
		var image:=Image.create(cw*ts,ch*ts,false,Image.FORMAT_RGBA8)
		image.fill(Color(.5,.5,1,0));normal_images[bucket]=image
		var glow:=Image.create(cw*ts,ch*ts,false,Image.FORMAT_RGBA8)
		glow.fill(Color(0,0,0,0));emission_images[bucket]=glow
	var height_image:=Image.create((cw+PAD*2)*12,(ch+PAD*2)*12,false,Image.FORMAT_RGBA8)
	height_image.fill(Color(0,0,0,0))
	for y in range(-PAD,ch+PAD):
		for x in range(-PAD,cw+PAD):
			var gx:=x0+x;var gy:=y0+y
			if gx<0 or gy<0 or gx>=ctrl.grid_width or gy>=ctrl.grid_height:continue
			for z in range(4):
				if not ctrl.is_layer_drawn_z(z):continue
				var tid: int=ctrl._src_tile(ctrl.collision,gx,gy,z)
				if tid<=0:continue
				if is_scaled_prop_tile(tid):continue
				if x>=0 and y>=0 and x<cw and y<ch:
					var bucket: String="Upper" if tid<flags.size() and (flags[tid]&16)!=0 else "Ground"
					Blit.blit_tile(normal_images[bucket],tid,x*ts,y*ts,normals,ts,ts,flags,0)
					Blit.blit_tile(emission_images[bucket],tid,x*ts,y*ts,emissions,ts,ts,flags,0)
				Blit.blit_tile(height_image,tid,(x+PAD)*12,(y+PAD)*12,heights,12,12,flags,0)
	var effects=collect_effects(x0,y0,cw,ch)
	return {"normals":normal_images,"emissions":emission_images,"height":height_image,"lights":effects.lights,"fountains":effects.fountains,"prop_channels":{"normals":normals,"emissions":emissions}}

func apply_chunk(node: Node2D,x0: int,y0: int,cw: int,ch: int, baked: Dictionary = {}, gpu: Dictionary = {}) -> void:
	if baked.is_empty():baked=bake_images(x0,y0,cw,ch)
	if baked.is_empty():return
	profile=ctrl.pack.render_profile
	if source_pack!=ctrl.pack:
		source_pack=ctrl.pack
		terrain_textures.clear()
		prop_textures.clear()
	# Reuse worker-decoded source channels; never decode the whole tileset on
	# the main thread when the first lamp enters view.
	if baked.has("prop_channels"):
		normals=baked.prop_channels.normals;emissions=baked.prop_channels.emissions
	if terrain_textures.is_empty():
		for key in profile.get("terrain_textures",{}):
			var path: String=source_pack.pack_dir+"/assets/tilesheet/"+str(profile.terrain_textures[key])+".png"
			if FileAccess.file_exists(path):terrain_textures[key]=ImageTexture.create_from_image(Image.load_from_file(path))
	var ts: int=ctrl.tile_size
	var normal_images: Dictionary=baked.normals
	var emission_images: Dictionary=baked.emissions
	var height_image: Image=baked.height
	var height_texture: Texture2D=gpu.get("height")
	if height_texture==null:height_texture=ImageTexture.create_from_image(height_image)
	for bucket in normal_images:
		var sprite:=node.get_node_or_null(bucket) as Sprite2D
		if sprite==null or not sprite.visible:continue
		var mat:=ShaderMaterial.new();mat.shader=SurfaceShader
		mat.set_shader_parameter("normal_tex",gpu["normal_"+bucket] if gpu.has("normal_"+bucket) else ImageTexture.create_from_image(normal_images[bucket]))
		mat.set_shader_parameter("height_tex",height_texture)
		var emission_texture: Texture2D=gpu.get("emission_"+bucket)
		if emission_texture==null:
			var glow: Image=emission_images[bucket]
			if glow.get_size()==Vector2i.ONE and glow.is_invisible():
				if black==null:black=ImageTexture.create_from_image(glow)
				emission_texture=black
			else:emission_texture=ImageTexture.create_from_image(glow)
		mat.set_shader_parameter("emission_tex",emission_texture)
		mat.set_shader_parameter("chunk_pixels",Vector2(cw*ts,ch*ts))
		mat.set_shader_parameter("padding",float(PAD*ts))
		mat.set_shader_parameter("world_origin",Vector2(x0*ts,y0*ts))
		mat.set_shader_parameter("terrain_enabled",terrain_textures.has("meadow") and terrain_textures.has("river") and bucket=="Ground")
		for key in terrain_textures:mat.set_shader_parameter(key+"_tex",terrain_textures[key])
		var direction: Array=profile.get("sun_direction",[.72,.69])
		mat.set_shader_parameter("sun_direction",Vector2(float(direction[0]),float(direction[1])))
		for key in ["normal_strength","shadow_strength","shadow_length"]:
			if profile.has(key):mat.set_shader_parameter(key,float(profile[key]))
		mat.set_shader_parameter("receive_shadows",bucket=="Ground")
		sprite.material=mat
	_add_fountains(node,x0,y0,cw,ch,baked.get("fountains",[]))
	_add_lights(node,x0,y0,cw,ch,baked.get("lights",[]))
	_update_night(node,_night_factor())

func _add_fountains(node: Node2D,x0: int,y0: int,cw: int,ch: int, placements: Array) -> void:
	var old:=node.get_node_or_null("MaterialEffects")
	if old!=null:node.remove_child(old);old.queue_free()
	var root:=Node2D.new();root.name="MaterialEffects";node.add_child(root)
	if white==null:
		var image:=Image.create(1,1,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
		white=ImageTexture.create_from_image(image)
	for entry in placements:
		var x: int=entry.x;var y: int=entry.y
		var effect: Dictionary=entry.definition
		var sprite:=Sprite2D.new();sprite.name="Fountain_%d_%d"%[x0+x,y0+y]
		sprite.texture=white;sprite.centered=false
		sprite.position=Vector2(x*ctrl.tile_size+effect.offset[0],y*ctrl.tile_size+effect.offset[1])
		sprite.scale=Vector2(effect.size[0],effect.size[1]);sprite.z_index=10
		var mat:=ShaderMaterial.new();mat.shader=FountainShader;sprite.material=mat
		root.add_child(sprite)

func _add_lights(node: Node2D,x0: int,y0: int,cw: int,ch: int, placements: Array) -> void:
	var root: Node2D=node.get_node("MaterialEffects")
	if light_texture==null:
		light_texture=GradientTexture2D.new();light_texture.width=256;light_texture.height=256
		light_texture.fill=GradientTexture2D.FILL_RADIAL
		light_texture.fill_from=Vector2(.5,.5);light_texture.fill_to=Vector2(1,.5)
		var gradient:=Gradient.new()
		gradient.offsets=PackedFloat32Array([0,.22,.65,1])
		gradient.colors=PackedColorArray([Color(1,1,1,1),Color(.75,.75,.75,1),Color(.18,.18,.18,1),Color(0,0,0,1)])
		light_texture.gradient=gradient
	for entry in placements:
		var x: int=entry.x;var y: int=entry.y;var z: int=entry.z
		var definition: Dictionary=entry.definition
		var factor:=float(definition.get("visual_scale",1.0))
		var foot_offset: Array=definition.get("foot_offset",[28,189])
		var pivot:=Vector2(foot_offset[0],foot_offset[1])
		var origin:=Vector2(x*ctrl.tile_size,y*ctrl.tile_size)
		_add_scaled_prop(root,definition,origin)
		var light:=PointLight2D.new();light.name="Light_%d_%d_%d"%[x0+x,y0+y,z]
		light.position=origin+pivot+(Vector2(definition.offset[0],definition.offset[1])-pivot)*factor
		light.texture=light_texture;light.texture_scale=float(definition.radius)*2.0/256.0
		light.color=Color(1.0,.76,.43);light.height=100.0
		light.energy=0.0;light.set_meta("base_energy",float(definition.energy))
		light.range_z_min=-10;light.range_z_max=12
		light.shadow_enabled=str(definition.get("kind",""))=="lamp"
		light.shadow_filter=Light2D.SHADOW_FILTER_PCF5
		light.shadow_color=Color(.12,.16,.24,.75)
		root.add_child(light)
		if str(definition.get("kind",""))=="lamp":
			var shadow:=Line2D.new();shadow.name="PoleShadow_%d_%d"%[x0+x,y0+y]
			var foot:=origin+pivot
			shadow.points=PackedVector2Array([foot,foot+Vector2(64,42)*factor])
			shadow.width=3.0*factor;shadow.default_color=Color(.12,.14,.12,.28);shadow.z_index=1
			root.add_child(shadow)
		if definition.has("occluder"):
			var rect: Array=definition.occluder
			var polygon:=OccluderPolygon2D.new()
			polygon.polygon=PackedVector2Array([Vector2(rect[0],rect[1]),Vector2(rect[0]+rect[2],rect[1]),Vector2(rect[0]+rect[2],rect[1]+rect[3]),Vector2(rect[0],rect[1]+rect[3])])
			var occluder:=LightOccluder2D.new();occluder.occluder=polygon
			occluder.position=Vector2(x*ctrl.tile_size,y*ctrl.tile_size);root.add_child(occluder)

func _night_factor() -> float:
	var tint: Color=ctrl.weather_display_modulate()
	var luma:=tint.r*.2126+tint.g*.7152+tint.b*.0722
	return clampf((.85-luma)/.5,0,1)

func _update_night(node: Node,night: float) -> void:
	for bucket in ["Ground","Upper"]:
		var sprite:=node.get_node_or_null(bucket) as Sprite2D
		if sprite!=null and sprite.material is ShaderMaterial and sprite.material.shader==SurfaceShader:
			sprite.material.set_shader_parameter("night_factor",night)
	var root:=node.get_node_or_null("MaterialEffects")
	if root!=null:
		for effect in root.get_children():
			if effect is PointLight2D:
				effect.enabled=night>.01
				effect.energy=float(effect.get_meta("base_energy",1.0))*night
			elif effect is Line2D:effect.modulate.a=1.0-night
			elif effect is Sprite2D and effect.has_meta("scaled_prop"):effect.material.set_shader_parameter("night_factor",night)

func tick(delta: float) -> void:
	if profile.is_empty():return
	tick_timer+=delta
	if tick_timer<.1:return
	tick_timer=0.0
	var night:=_night_factor()
	if absf(night-last_night)<.002:return
	last_night=night
	for node in ctrl._chunks.values():
		if is_instance_valid(node):_update_night(node,night)

# Run with the image baker; avoid rescanning each map cell on GPU submission.
func collect_effects(x0: int,y0: int,cw: int,ch: int) -> Dictionary:
	var lamps={};var fountains={};var out={"lights":[],"fountains":[]}
	for definition in profile.get("lights",[]):lamps[int(definition.anchor)]=definition
	for definition in profile.get("fountains",[]):fountains[int(definition.anchor)]=definition
	for y in range(ch):
		for x in range(cw):
			for z in range(1,4):
				var id: int=ctrl._src_tile(ctrl.collision,x0+x,y0+y,z)
				if lamps.has(id):out.lights.append({"x":x,"y":y,"z":z,"definition":lamps[id]})
				if z==3 and fountains.has(id):out.fountains.append({"x":x,"y":y,"definition":fountains[id]})
	return out
