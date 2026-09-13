extends Node2D
## One 16×16 (or remainder) baked map chunk. GPU textures only; data lives on the pack.

var chunk: Vector2i = Vector2i.ZERO
var _below: Sprite2D
var _ground: Sprite2D
var _upper: Sprite2D
var _roof: Sprite2D
var _fx: Sprite2D


func setup(p_chunk: Vector2i, origin: Vector2) -> void:
	chunk = p_chunk
	position = origin
	name = "Chunk_%d_%d" % [p_chunk.x, p_chunk.y]
	z_as_relative = true


func apply_bucket(bucket: String, img: Image, z_index: int, additive: bool = false) -> void:
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		return
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var spr := _ensure_sprite(bucket, z_index, additive)
	spr.texture = ImageTexture.create_from_image(img)
	spr.visible = true


func set_roof_visible(on: bool) -> void:
	if _roof != null:
		_roof.visible = on


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
		spr.modulate = Color(1, 1, 1, 1)
		# Light decals: keep mix; additive via CanvasItem material if needed.
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
