extends Node2D
## World-space skill VFX: impact burst, bolt tween, caster flash.
## Loads optional PNGs from content://fx/; falls back to drawn polygons.

var _flame_tex: Texture2D = null
var _bolt_tex: Texture2D = null
var _ring_tex: Texture2D = null
var _slash_tex: Texture2D = null
var _cast_tex: Texture2D = null
var _dash_tex: Texture2D = null
var _spin_tex: Texture2D = null


func _ready() -> void:
	z_index = 12
	_flame_tex = _load_fx("fx_flame.png")
	_bolt_tex = _load_fx("fx_bolt.png")
	_ring_tex = _load_fx("aim_ring.png")
	_slash_tex = _load_fx("fx_slash.png")
	_cast_tex = _load_fx("fx_cast.png")
	_dash_tex = _load_fx("fx_dash.png")
	_spin_tex = _load_fx("fx_spin.png")


func _load_fx(fname: String) -> Texture2D:
	var am = get_node_or_null("/root/AssetManager")
	if am != null and am.has_method("load_texture"):
		return am.load_texture("content://fx/%s" % fname)
	return null


func play_impact(kind: String, world_pos: Vector2, radius_px: float = 48.0) -> void:
	var spr := Sprite2D.new()
	spr.centered = true
	spr.position = world_pos
	spr.z_index = 12
	var tex: Texture2D = _flame_tex
	if kind == "bolt" or kind == "arcane":
		tex = _bolt_tex if _bolt_tex != null else _flame_tex
	if tex != null:
		spr.texture = tex
		var tw0: float = float(tex.get_width())
		var sc: float = (radius_px * 2.2) / maxf(tw0, 1.0)
		spr.scale = Vector2(sc * 0.45, sc * 0.45)
	else:
		spr.texture = _make_blob(kind)
		spr.scale = Vector2(0.5, 0.5)
	add_child(spr)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", spr.scale * 1.85, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "modulate:a", 0.0, 0.38).set_delay(0.08)
	tw.chain().tween_callback(spr.queue_free)


func play_bolt(from_world: Vector2, to_world: Vector2, kind: String = "bolt") -> void:
	var spr := Sprite2D.new()
	spr.centered = true
	spr.position = from_world
	spr.z_index = 13
	spr.texture = _bolt_tex if _bolt_tex != null else _make_blob(kind)
	var dist: float = from_world.distance_to(to_world)
	var sc: float = clampf(dist / 180.0, 0.22, 0.55)
	if spr.texture != null:
		var tw0: float = float(spr.texture.get_width())
		sc = clampf(72.0 / maxf(tw0, 1.0), 0.08, 0.28)
	spr.scale = Vector2(sc, sc)
	spr.rotation = from_world.angle_to_point(to_world)
	add_child(spr)
	var dur: float = clampf(dist / 520.0, 0.12, 0.32)
	var tw := create_tween()
	tw.tween_property(spr, "position", to_world, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		play_impact(kind, to_world, 36.0)
		spr.queue_free()
	)


func play_ring(world_pos: Vector2, radius_px: float) -> void:
	var spr := Sprite2D.new()
	spr.centered = true
	spr.position = world_pos
	spr.z_index = 11
	if _ring_tex != null:
		spr.texture = _ring_tex
		var tw0: float = float(_ring_tex.get_width())
		var sc: float = (radius_px * 2.0) / maxf(tw0, 1.0)
		spr.scale = Vector2(sc, sc)
		spr.modulate = Color(1, 1, 1, 0.85)
	else:
		spr.texture = _make_blob("ring")
		spr.scale = Vector2(0.4, 0.4)
	add_child(spr)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", spr.scale * 1.15, 0.45)
	tw.tween_property(spr, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(spr.queue_free)


func flash_actor(node: Node2D, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base: Color = node.modulate
	var tw := create_tween()
	tw.tween_property(node, "modulate", color, 0.06)
	tw.tween_property(node, "modulate", base, 0.18)


func play_action(kind: String, actor: Node2D, facing: String = "front") -> void:
	if actor == null or not is_instance_valid(actor):
		return
	kind = kind.strip_edges().to_lower()
	var vis := _visual(actor)
	var fwd := _facing_vec(facing)
	var feet: Vector2 = actor.global_position
	match kind:
		"strike":
			flash_actor(actor, Color(1.0, 0.92, 0.55))
			_lunge(vis, fwd, 10.0, 0.16)
			_spawn_overlay(_slash_tex, feet + fwd * 14.0, 52.0, fwd.angle(), 0.28)
		"cast":
			flash_actor(actor, Color(0.7, 0.85, 1.0))
			_pulse(vis, 1.08, 0.28)
			_spawn_overlay(_cast_tex if _cast_tex != null else _ring_tex, feet + Vector2(0, 6), 46.0, 0.0, 0.5)
		"dash":
			flash_actor(actor, Color(0.75, 0.95, 1.0))
			_lunge(vis, fwd, 22.0, 0.22)
			_spawn_overlay(_dash_tex, feet - fwd * 8.0, 64.0, fwd.angle(), 0.28)
		"spin":
			flash_actor(actor, Color(1.0, 0.82, 0.35))
			_spin(vis, 0.38)
			_spawn_overlay(_spin_tex, feet + Vector2(0, -8), 58.0, 0.0, 0.42)
		_:
			flash_actor(actor)


func _visual(actor: Node2D) -> Node2D:
	var n: Node = actor.get_node_or_null("%Anim")
	if n == null:
		n = actor.get_node_or_null("Anim")
	if n is Node2D:
		return n
	return actor


func _facing_vec(facing: String) -> Vector2:
	match facing.strip_edges().to_lower():
		"back", "up":
			return Vector2(0, -1)
		"left":
			return Vector2(-1, 0)
		"right":
			return Vector2(1, 0)
		_:
			return Vector2(0, 1)


func _spawn_overlay(tex: Texture2D, world_pos: Vector2, size_px: float, rot: float, dur: float) -> void:
	var spr := Sprite2D.new()
	spr.centered = true
	spr.position = world_pos
	spr.rotation = rot
	spr.z_index = 14
	if tex != null:
		spr.texture = tex
		var tw0: float = float(maxi(tex.get_width(), tex.get_height()))
		var sc: float = size_px / maxf(tw0, 1.0)
		spr.scale = Vector2(sc, sc)
	else:
		spr.texture = _make_blob("ring")
		spr.scale = Vector2(0.45, 0.45)
	add_child(spr)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", spr.scale * 1.25, dur)
	tw.tween_property(spr, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(spr.queue_free)


func _lunge(node: Node2D, dir: Vector2, dist: float, dur: float) -> void:
	var origin: Vector2 = node.position
	var tw := create_tween()
	tw.tween_property(node, "position", origin + dir * dist, dur * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", origin, dur * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _pulse(node: Node2D, scale_to: float, dur: float) -> void:
	var origin: Vector2 = node.scale
	var tw := create_tween()
	tw.tween_property(node, "scale", origin * scale_to, dur * 0.4)
	tw.tween_property(node, "scale", origin, dur * 0.6)


func _spin(node: Node2D, dur: float) -> void:
	var origin: float = node.rotation
	var tw := create_tween()
	tw.tween_property(node, "rotation", origin + TAU, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(node):
			node.rotation = origin
	)


func _make_blob(kind: String) -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var col := Color(1.0, 0.45, 0.12, 0.95)
	if kind == "bolt" or kind == "arcane":
		col = Color(0.45, 0.55, 1.0, 0.95)
	elif kind == "ring":
		col = Color(0.95, 0.8, 0.25, 0.9)
	for y in range(32):
		for x in range(32):
			var dx := float(x) - 15.5
			var dy := float(y) - 15.5
			var d := sqrt(dx * dx + dy * dy)
			if kind == "ring":
				if absf(d - 12.0) < 2.2:
					img.set_pixel(x, y, col)
			elif d <= 14.0:
				var a: float = clampf(1.0 - d / 14.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a * col.a))
	return ImageTexture.create_from_image(img)
