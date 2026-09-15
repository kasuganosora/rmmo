extends Node2D
## One 16×16 (or remainder) baked map chunk. GPU textures only; data lives on the pack.

const TileBlit = preload("res://scripts/map/tile_blit.gd")
const BlendShader = preload("res://scripts/map/tile_anim_blend.gdshader")

var chunk: Vector2i = Vector2i.ZERO
var _below: Sprite2D
var _ground: Sprite2D
var _upper: Sprite2D
var _roof: Sprite2D
var _fx: Sprite2D
var _fx_modulate: Color = Color(1, 1, 1, 1)
## A1 water/waterfall jobs + overlay images (static tiles stay on the main buckets).
var anim_jobs: Array = []
var anim_shadows: Array = []
var anim_images: Dictionary = {}
var anim_images_next: Dictionary = {}
var _anim_pair_frame: int = -1
## 4 ping-pong keyframes baked once; walking only swaps GPU textures.
var _anim_frame_imgs: Array = []
var _anim_frame_tex: Array = []
var _anim_prebaked: bool = false


func setup(p_chunk: Vector2i, origin: Vector2) -> void:
	chunk = p_chunk
	position = origin
	name = "Chunk_%d_%d" % [p_chunk.x, p_chunk.y]
	z_as_relative = true


func clear_visuals() -> void:
	for spr in [_below, _ground, _upper, _roof, _fx]:
		if spr != null:
			spr.texture = null
			spr.visible = false
	for child in get_children():
		if child is Sprite2D and str(child.name).ends_with("Anim"):
			(child as Sprite2D).texture = null
			(child as Sprite2D).visible = false
	anim_jobs = []
	anim_shadows = []
	anim_images = {}
	anim_images_next = {}
	_anim_pair_frame = -1
	_anim_frame_imgs = []
	_anim_frame_tex = []
	_anim_prebaked = false


func apply_bucket(bucket: String, img: Image, z_index: int, additive: bool = false) -> void:
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		_hide_bucket(bucket)
		return
	var existing: Sprite2D = get_node_or_null(bucket) as Sprite2D
	var tex: Texture2D = existing.texture if existing != null else null
	var reuse: bool = (
		tex is ImageTexture
		and tex.get_width() == img.get_width()
		and tex.get_height() == img.get_height()
	)
	# get_used_rect scans the whole bitmap — skip when we already have a same-size GPU texture.
	if not reuse:
		var used: Rect2i = img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			_hide_bucket(bucket)
			return
	var spr := _ensure_sprite(bucket, z_index, additive)
	if reuse and spr.texture is ImageTexture:
		(spr.texture as ImageTexture).update(img)
	else:
		spr.texture = ImageTexture.create_from_image(img)
	spr.visible = true


func _hide_bucket(bucket: String) -> void:
	var spr: Sprite2D = get_node_or_null(bucket) as Sprite2D
	if spr != null:
		spr.visible = false


func set_fx_modulate(c: Color) -> void:
	_fx_modulate = c
	if _fx != null:
		_fx.modulate = c
	var fa: Sprite2D = get_node_or_null("FxAnim") as Sprite2D
	if fa != null:
		fa.modulate = c


func set_roof_visible(on: bool) -> void:
	if _roof != null:
		_roof.visible = on
	var ra: Sprite2D = get_node_or_null("RoofAnim") as Sprite2D
	if ra != null:
		ra.visible = on


func set_below_offset(off: Vector2) -> void:
	if _below != null:
		_below.position = off
	var ba: Sprite2D = get_node_or_null("BelowAnim") as Sprite2D
	if ba != null:
		ba.position = off


func set_anim_data(jobs: Array, shadows: Array, images: Dictionary) -> void:
	anim_jobs = jobs
	anim_shadows = shadows
	anim_images = images
	anim_images_next = {}
	_anim_pair_frame = -1
	_anim_frame_imgs = []
	_anim_frame_tex = []
	_anim_prebaked = false


func prebake_next_anim_frame(sheets: Array, flags: PackedInt32Array, tile_px: int) -> bool:
	if _anim_prebaked or anim_jobs.is_empty():
		return false
	if _anim_frame_imgs.size() >= 4:
		_anim_prebaked = true
		return false
	var buckets: Array = anim_images.keys()
	if buckets.is_empty():
		for job_v in anim_jobs:
			if typeof(job_v) != TYPE_DICTIONARY:
				continue
			var bn: String = str(job_v.get("bucket", "Ground"))
			if not buckets.has(bn):
				buckets.append(bn)
	if buckets.is_empty():
		return false
	var w: int = 0
	var h: int = 0
	for b0 in buckets:
		var src: Image = anim_images.get(b0)
		if src != null:
			w = src.get_width()
			h = src.get_height()
			break
		if _anim_frame_imgs.size() > 0:
			var prev: Dictionary = _anim_frame_imgs[0]
			var pimg: Image = prev.get(str(b0))
			if pimg != null:
				w = pimg.get_width()
				h = pimg.get_height()
				break
	if w <= 0 or h <= 0:
		return false
	var f: int = _anim_frame_imgs.size()
	var imgs: Dictionary = {}
	var texs: Dictionary = {}
	for b in buckets:
		var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		imgs[str(b)] = im
	_blit_anim_keyframe(f, imgs, sheets, flags, tile_px)
	for b2 in imgs.keys():
		texs[b2] = ImageTexture.create_from_image(imgs[b2])
	_anim_frame_imgs.append(imgs)
	_anim_frame_tex.append(texs)
	if _anim_frame_imgs.size() >= 4:
		_anim_prebaked = true
		anim_images = _anim_frame_imgs[0]
		anim_images_next = _anim_frame_imgs[1]
	return true


func refresh_anim(
	frame: int,
	sheets: Array,
	flags: PackedInt32Array,
	tile_px: int,
	mix_t: float = 0.0,
	allow_build: bool = true
) -> void:
	if anim_jobs.is_empty():
		return
	if not _anim_prebaked:
		if allow_build:
			_ensure_anim_prebaked(sheets, flags, tile_px)
		else:
			_set_anim_mix(mix_t)
			return
	frame = posmod(frame, 4)
	var nxt_frame: int = posmod(frame + 1, 4)
	if frame != _anim_pair_frame:
		if _anim_prebaked and _anim_frame_imgs.size() == 4:
			anim_images = _anim_frame_imgs[frame]
			anim_images_next = _anim_frame_imgs[nxt_frame]
			var cur_tex: Dictionary = _anim_frame_tex[frame]
			var nxt_tex: Dictionary = _anim_frame_tex[nxt_frame]
			for b in anim_images.keys():
				_bind_anim_pair(str(b) + "Anim", cur_tex.get(b), nxt_tex.get(b), str(b) == "Fx")
		else:
			_blit_anim_keyframe(frame, anim_images, sheets, flags, tile_px)
			_blit_anim_keyframe(nxt_frame, anim_images_next, sheets, flags, tile_px)
			for b in anim_images.keys():
				var additive: bool = str(b) == "Fx"
				apply_bucket(str(b) + "Anim", anim_images[b], _anim_z(str(b)), additive)
				_bind_anim_next(str(b) + "Anim", anim_images_next.get(b))
		_anim_pair_frame = frame
	_set_anim_mix(mix_t)


func set_anim_mix_only(mix_t: float) -> void:
	if anim_jobs.is_empty():
		return
	_set_anim_mix(mix_t)


func _ensure_anim_prebaked(sheets: Array, flags: PackedInt32Array, tile_px: int) -> void:
	if _anim_prebaked or anim_jobs.is_empty():
		return
	var buckets: Array = anim_images.keys()
	if buckets.is_empty():
		for job_v in anim_jobs:
			if typeof(job_v) != TYPE_DICTIONARY:
				continue
			var bn: String = str(job_v.get("bucket", "Ground"))
			if not buckets.has(bn):
				buckets.append(bn)
	if buckets.is_empty():
		return
	var w: int = 0
	var h: int = 0
	for b0 in buckets:
		var src: Image = anim_images.get(b0)
		if src != null:
			w = src.get_width()
			h = src.get_height()
			break
	if w <= 0 or h <= 0:
		return
	_anim_frame_imgs = []
	_anim_frame_tex = []
	for f in range(4):
		var imgs: Dictionary = {}
		var texs: Dictionary = {}
		for b in buckets:
			var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
			im.fill(Color(0, 0, 0, 0))
			imgs[str(b)] = im
		_blit_anim_keyframe(f, imgs, sheets, flags, tile_px)
		for b2 in imgs.keys():
			var im2: Image = imgs[b2]
			texs[b2] = ImageTexture.create_from_image(im2)
		_anim_frame_imgs.append(imgs)
		_anim_frame_tex.append(texs)
	_anim_prebaked = true
	anim_images = _anim_frame_imgs[0]
	anim_images_next = _anim_frame_imgs[1]


func _blit_anim_keyframe(frame: int, images: Dictionary, sheets: Array, flags: PackedInt32Array, tile_px: int) -> void:
	for b in images.keys():
		var img: Image = images[b]
		if img != null:
			img.fill(Color(0, 0, 0, 0))
	for job_v in anim_jobs:
		if typeof(job_v) != TYPE_DICTIONARY:
			continue
		var job: Dictionary = job_v
		var bucket: String = str(job.get("bucket", "Ground"))
		var img2: Image = images.get(bucket)
		if img2 == null:
			continue
		TileBlit.blit_tile(
			img2,
			int(job.get("tile_id", 0)),
			int(job.get("dx", 0)),
			int(job.get("dy", 0)),
			sheets,
			tile_px,
			tile_px,
			flags,
			frame
		)
	var ganim: Image = images.get("Ground")
	if ganim != null:
		for sh_v in anim_shadows:
			if typeof(sh_v) != TYPE_DICTIONARY:
				continue
			var sh: Dictionary = sh_v
			TileBlit.blit_shadow(
				ganim,
				int(sh.get("bits", 0)),
				int(sh.get("dx", 0)),
				int(sh.get("dy", 0)),
				tile_px,
				tile_px
			)


func _bind_anim_pair(spr_name: String, cur_tex: Variant, nxt_tex: Variant, additive: bool) -> void:
	var bucket: String = spr_name
	if bucket.ends_with("Anim"):
		bucket = bucket.substr(0, bucket.length() - 4)
	var spr := _ensure_sprite(spr_name, _anim_z(bucket), additive)
	if cur_tex is Texture2D:
		spr.texture = cur_tex
	spr.visible = true
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != BlendShader:
		mat = ShaderMaterial.new()
		mat.shader = BlendShader
		spr.material = mat
	if nxt_tex is Texture2D:
		mat.set_shader_parameter("next_tex", nxt_tex)


func _bind_anim_next(spr_name: String, img: Image) -> void:
	var spr: Sprite2D = get_node_or_null(spr_name) as Sprite2D
	if spr == null or img == null:
		return
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != BlendShader:
		mat = ShaderMaterial.new()
		mat.shader = BlendShader
		spr.material = mat
	var tex: Texture2D = mat.get_shader_parameter("next_tex")
	if tex is ImageTexture and tex.get_width() == img.get_width() and tex.get_height() == img.get_height():
		(tex as ImageTexture).update(img)
	else:
		tex = ImageTexture.create_from_image(img)
		mat.set_shader_parameter("next_tex", tex)


func _set_anim_mix(mix_t: float) -> void:
	for b in anim_images.keys():
		var spr: Sprite2D = get_node_or_null(str(b) + "Anim") as Sprite2D
		if spr == null:
			continue
		var mat := spr.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("mix_t", clampf(mix_t, 0.0, 1.0))


func _anim_z(bucket: String) -> int:
	match bucket:
		"Below":
			return -21
		"Ground":
			return -1
		"Upper":
			return 9
		"Roof":
			return 11
		"Fx":
			return 15
		_:
			return -1


func unload() -> void:
	queue_free()


func _ensure_sprite(bucket: String, z_index: int, additive: bool) -> Sprite2D:
	var spr: Sprite2D = get_node_or_null(bucket) as Sprite2D
	if spr == null:
		spr = Sprite2D.new()
		spr.name = bucket
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.z_as_relative = true
		add_child(spr)
	spr.z_index = z_index
	if additive:
		spr.modulate = _fx_modulate
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		spr.material = mat
	match bucket:
		"Below":
			_below = spr
		"Ground":
			_ground = spr
		"Upper":
			_upper = spr
		"Roof":
			_roof = spr
		"Fx":
			_fx = spr
	return spr
