extends RefCounted
## Domain module: continent editor support (edit camera/observer, layer visibility, edit_doc, reference image).

var ctrl
func _init(c):
	ctrl = c

const MapExt = preload("res://scripts/map/map_ext.gd")

func set_edit_camera_cell(cell: Vector2i) -> void:
	var prev: Vector2i = ctrl.cell_to_chunk(ctrl._obs_cell)
	ctrl._obs_cell = cell
	ctrl._refresh_chunk_set()
	var now: Vector2i = ctrl.cell_to_chunk(ctrl._obs_cell)
	if now != prev or not ctrl._chunks.has(ctrl._chunk_key(now)):
		ctrl.bake_observer_chunk()



func _edit_observer_cell() -> Vector2i:
	if ctrl.edit_start_cell.x >= 0 and ctrl.edit_start_cell.y >= 0:
		return Vector2i(clampi(ctrl.edit_start_cell.x, 0, maxi(ctrl.grid_width - 1, 0)), clampi(ctrl.edit_start_cell.y, 0, maxi(ctrl.grid_height - 1, 0)))
	return Vector2i(clampi(2, 0, maxi(ctrl.grid_width - 1, 0)), clampi(2, 0, maxi(ctrl.grid_height - 1, 0)))



func is_layer_drawn_z(z: int) -> bool:
	if not ctrl.edit_mode:
		return true
	if z < 0 or z >= ctrl.edit_hidden_z.size():
		return true
	return int(ctrl.edit_hidden_z[z]) == 0



func is_layer_drawn_ext(id: String) -> bool:
	if not ctrl.edit_mode:
		return true
	return not bool(ctrl.edit_hidden_ext.get(id, false))



func set_layer_hidden_z(z: int, hidden: bool) -> void:
	if z < 0 or z > 5:
		return
	if ctrl.edit_hidden_z.size() < 6:
		ctrl.edit_hidden_z.resize(6)
	ctrl.edit_hidden_z[z] = 1 if hidden else 0
	ctrl.rebake_loaded_chunks()



func set_layer_hidden_ext(id: String, hidden: bool) -> void:
	if hidden:
		ctrl.edit_hidden_ext[id] = true
	else:
		ctrl.edit_hidden_ext.erase(id)
	ctrl.rebake_loaded_chunks()



func _apply_edit_doc_size() -> void:
	if ctrl.edit_doc == null:
		return
	ctrl.grid_width = int(ctrl.edit_doc.width)
	ctrl.grid_height = int(ctrl.edit_doc.height)
	ctrl.tile_size = maxi(int(ctrl.edit_doc.tile_size), 1)



func set_edit_flags(flags: PackedInt32Array) -> void:
	if ctrl.pack != null:
		ctrl.pack.flags = flags
		if ctrl.pack.collision != null:
			ctrl.pack.collision.flags = flags



func edit_cell_passable(x: int, y: int) -> int:
	## 0 walk, 1 block, 2 force-pass, 3 force-block.
	if x < 0 or y < 0 or x >= ctrl.grid_width or y >= ctrl.grid_height or ctrl.edit_doc == null:
		return 1
	var meta = 0
	if ctrl.edit_doc.has_method("ext_tile"):
		meta = int(ctrl.edit_doc.ext_tile("meta", x, y))
	if (meta & MapExt.META_FORCE_BLOCK) != 0:
		return 3
	if (meta & MapExt.META_FORCE_PASS) != 0:
		return 2
	var t0: int = int(ctrl.edit_doc.tile(x, y, 0))
	var t1: int = int(ctrl.edit_doc.tile(x, y, 1))
	var t2: int = int(ctrl.edit_doc.tile(x, y, 2))
	var t3: int = int(ctrl.edit_doc.tile(x, y, 3))
	if t0 == 0 and t1 == 0 and t2 == 0 and t3 == 0:
		return 1
	var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack != null else PackedInt32Array()
	for z in [3, 2, 1, 0]:
		var t: int = int(ctrl.edit_doc.tile(x, y, z))
		if t <= 0:
			continue
		var f: int = int(flags[t]) if t < flags.size() else 0
		if (f & 0x10) != 0:
			continue
		if (f & 0x0F) == 0x0F:
			return 1
		return 0
	return 1



func _ensure_edit_overlay() -> void:
	if not ctrl.edit_mode:
		if ctrl._edit_overlay != null and is_instance_valid(ctrl._edit_overlay):
			ctrl._edit_overlay.visible = false
		return
	if ctrl._edit_overlay == null or not is_instance_valid(ctrl._edit_overlay):
		ctrl._edit_overlay = preload("res://scripts/map/map_edit_overlay.gd").new()
		ctrl._edit_overlay.name = "EditOverlay"
		ctrl._edit_overlay.z_as_relative = false
		ctrl._edit_overlay.z_index = 4096
		ctrl.add_child(ctrl._edit_overlay)
	ctrl._edit_overlay.visible = true
	ctrl.move_child(ctrl._edit_overlay, ctrl.get_child_count() - 1)



func set_reference_image(path: String, alpha: float = 0.35) -> void:
	ctrl._ref_alpha = clampf(alpha, 0.0, 1.0)
	if ctrl._ref_sprite == null or not is_instance_valid(ctrl._ref_sprite):
		ctrl._ref_sprite = Sprite2D.new()
		ctrl._ref_sprite.name = "RefOverlay"
		ctrl._ref_sprite.centered = false
		ctrl._ref_sprite.z_as_relative = false
		ctrl._ref_sprite.z_index = 3500
		ctrl.add_child(ctrl._ref_sprite)
	if path.strip_edges() == "":
		ctrl._ref_sprite.texture = null
		ctrl._ref_sprite.visible = false
		return
	var img = Image.new()
	if img.load(path) != OK:
		var glob = ProjectSettings.globalize_path(path)
		if img.load(glob) != OK:
			ctrl._ref_sprite.visible = false
			return
	var mw = float(maxi(ctrl.grid_width, 1) * maxi(ctrl.tile_size, 1))
	var mh = float(maxi(ctrl.grid_height, 1) * maxi(ctrl.tile_size, 1))
	ctrl._ref_sprite.texture = ImageTexture.create_from_image(img)
	ctrl._ref_sprite.visible = true
	ctrl._ref_sprite.modulate = Color(1, 1, 1, ctrl._ref_alpha)
	if ctrl._ref_sprite.texture:
		ctrl._ref_sprite.scale = Vector2(mw / float(maxi(ctrl._ref_sprite.texture.get_width(), 1)), mh / float(maxi(ctrl._ref_sprite.texture.get_height(), 1)))


