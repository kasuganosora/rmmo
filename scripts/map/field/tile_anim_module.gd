extends RefCounted
## Domain module: tile animation (A1 water etc. - prebake, frame advance, mix).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const ANIM_STEP_SEC := 0.5

func _cell_has_ground_anim(t0: int, t1: int, t2: int, t3: int, flags: PackedInt32Array) -> bool:
	var tiles = PackedInt32Array([t0, t1, t2, t3])
	for t in tiles:
		if not TileId.is_animated_a1(t):
			continue
		if t < flags.size() and (flags[t] & 0x10) != 0:
			continue
		return true
	return false



func _anim_image(bucket: String, like: Image) -> Image:
	if ctrl._bake_anim_imgs.has(bucket):
		return ctrl._bake_anim_imgs[bucket]
	var w: int = like.get_width() if like != null else 1
	var h: int = like.get_height() if like != null else 1
	var img = Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	ctrl._bake_anim_imgs[bucket] = img
	return img



func _begin_anim_bake() -> void:
	ctrl._bake_anim = true
	ctrl._bake_anim_jobs = []
	ctrl._bake_anim_shadows = []
	ctrl._bake_anim_imgs = {}



func _finish_anim_bake(node: Node2D, full_anim: bool = true) -> void:
	ctrl._bake_anim = false
	if node == null:
		return
	if node.has_method("set_anim_data"):
		node.set_anim_data(ctrl._bake_anim_jobs, ctrl._bake_anim_shadows, ctrl._bake_anim_imgs)
	for b in ctrl._bake_anim_imgs.keys():
		var bucket: String = str(b)
		var img: Image = ctrl._bake_anim_imgs[b]
		var additive: bool = bucket == "Fx"
		if node.has_method("apply_bucket"):
			node.apply_bucket(bucket + "Anim", img, _anim_layer_z(bucket), additive)
	if full_anim and node.has_method("refresh_anim"):
		var sheets: Array = ctrl.pack.sheets if ctrl.pack else []
		var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack else PackedInt32Array()
		node.refresh_anim(ctrl._anim_frame, sheets, flags, ctrl.tile_size, 0.0)
	ctrl._bake_anim_jobs = []
	ctrl._bake_anim_shadows = []
	ctrl._bake_anim_imgs = {}



func _anim_layer_z(bucket: String) -> int:
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



func _tick_tile_anim(delta: float) -> void:
	ctrl._anim_accum += delta
	var advanced = false
	while ctrl._anim_accum >= ANIM_STEP_SEC:
		ctrl._anim_accum -= ANIM_STEP_SEC
		ctrl._anim_frame = (ctrl._anim_frame + 1) % 4
		advanced = true
	var mix_t: float = clampf(ctrl._anim_accum / ANIM_STEP_SEC, 0.0, 1.0)
	if advanced:
		_refresh_chunk_anims(mix_t)
	else:
		_set_chunk_anim_mix(mix_t)



func tick_tile_anim() -> int:
	ctrl._anim_frame = (ctrl._anim_frame + 1) % 4
	ctrl._anim_accum = 0.0
	_refresh_chunk_anims(0.0)
	return ctrl._anim_frame



func tile_anim_mix() -> float:
	return clampf(ctrl._anim_accum / ANIM_STEP_SEC, 0.0, 1.0)



func tile_anim_frame() -> int:
	return ctrl._anim_frame



func _refresh_chunk_anims(mix_t: float = 0.0) -> void:
	if ctrl.pack == null:
		return
	var sheets: Array = ctrl.pack.sheets
	var flags: PackedInt32Array = ctrl.pack.flags
	for key in ctrl._chunks.keys():
		var ch: Node = ctrl._chunks[key]
		if ch != null and ch.has_method("refresh_anim"):
			ch.refresh_anim(ctrl._anim_frame, sheets, flags, ctrl.tile_size, mix_t, false)



func _set_chunk_anim_mix(mix_t: float) -> void:
	for key in ctrl._chunks.keys():
		var ch: Node = ctrl._chunks[key]
		if ch != null and ch.has_method("set_anim_mix_only"):
			ch.set_anim_mix_only(mix_t)



func _pump_anim_prebake() -> void:
	if ctrl.pack == null:
		return
	var sheets: Array = ctrl.pack.sheets
	var flags: PackedInt32Array = ctrl.pack.flags
	var n = 0
	for key in ctrl._chunks.keys():
		var ch: Node = ctrl._chunks[key]
		if ch == null or not ch.has_method("prebake_next_anim_frame"):
			continue
		if bool(ch.prebake_next_anim_frame(sheets, flags, ctrl.tile_size)):
			n += 1
			if n >= 1:
				return


