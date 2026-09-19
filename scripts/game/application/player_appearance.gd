extends RefCounted
## Application layer: gear look composition, weapon overlay, equip texture loading.

const LookCatalog = preload("res://scripts/char/look_catalog.gd")
const MV = preload("res://scripts/char/mv_generator.gd")
const Customization = preload("res://scripts/char/customization.gd")

static func apply_gear_look(ctrl, ch: Dictionary, equipment: Array, catalog = null) -> void:
	if ctrl.anim == null:
		ctrl.anim = ctrl.get_node_or_null("%Anim") as AnimatedSprite2D
	if ctrl.anim == null:
		return
	var PaperdollLook = load("res://scripts/char/paperdoll_look.gd")
	var gender = LookCatalog.normalize_gender(str(ch.get("gender", ctrl.gender)))
	var cust_d: Dictionary = {}
	var raw: Variant = ch.get("customization", {})
	if typeof(raw) == TYPE_DICTIONARY:
		cust_d = raw
	var cust = Customization.from_dict(cust_d) if not cust_d.is_empty() else null
	var parts: Dictionary = {}
	var colors: Dictionary = {}
	if cust != null:
		parts = cust.part_ids.duplicate()
		colors = cust.colors()
	if parts.is_empty():
		parts = MV.default_parts(gender)
	if PaperdollLook != null and PaperdollLook.has_method("equipment_to_mv_parts"):
		var overlay: Dictionary = PaperdollLook.equipment_to_mv_parts(gender, equipment, catalog)
		parts = MV.apply_equipment(parts, overlay)
	parts = MV.validate_parts(gender, parts)
	var frames: SpriteFrames = MV.compose_frames(gender, parts, colors)
	if frames == null:
		return
	var facing = ctrl._facing
	ctrl.anim.sprite_frames = frames
	ctrl.anim.scale = Vector2(1.35, 1.35)
	ctrl.anim.centered = true
	ctrl.anim.offset = Vector2(0, -32)
	var idle = "idle_%s" % facing
	if ctrl.anim.sprite_frames.has_animation(idle):
		ctrl.anim.play(idle)
	else:
		ctrl.anim.play("idle_front")
	ctrl._sync_weapon_overlay(equipment)

static func _sync_weapon_overlay(ctrl, equipment: Array) -> void:
	var item_id = ""
	for it in equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var sid = str(it.get("slot", "")).strip_edges()
		var iid = str(it.get("item_id", it.get("id", ""))).strip_edges()
		if sid == "weapon_main" and iid != "":
			item_id = iid
			break
	if item_id.is_empty():
		if ctrl._weapon_spr != null:
			ctrl._weapon_spr.visible = false
		return
	var tex = ctrl._load_equip_tex(item_id)
	if tex == null:
		if ctrl._weapon_spr != null:
			ctrl._weapon_spr.visible = false
		return
	if ctrl._weapon_spr == null or not is_instance_valid(ctrl._weapon_spr):
		ctrl._weapon_spr = Sprite2D.new()
		ctrl._weapon_spr.name = "WeaponOverlay"
		ctrl._weapon_spr.centered = true
		ctrl._weapon_spr.z_index = 6
		ctrl.add_child(ctrl._weapon_spr)
	ctrl._weapon_spr.texture = tex
	ctrl._weapon_spr.visible = true
	ctrl._place_weapon_overlay()

static func _place_weapon_overlay(ctrl) -> void:
	if ctrl._weapon_spr == null:
		return
	var tw: float = float(ctrl._weapon_spr.texture.get_width()) if ctrl._weapon_spr.texture else 64.0
	var sc: float = 28.0 / maxf(tw, 1.0)
	ctrl._weapon_spr.scale = Vector2(sc, sc)
	match ctrl._facing:
		"left":
			ctrl._weapon_spr.position = Vector2(-11, -26)
			ctrl._weapon_spr.flip_h = true
			ctrl._weapon_spr.rotation = -0.35
			ctrl._weapon_spr.z_index = 6
		"right":
			ctrl._weapon_spr.position = Vector2(11, -26)
			ctrl._weapon_spr.flip_h = false
			ctrl._weapon_spr.rotation = 0.35
			ctrl._weapon_spr.z_index = 6
		"back":
			ctrl._weapon_spr.position = Vector2(-7, -30)
			ctrl._weapon_spr.flip_h = false
			ctrl._weapon_spr.rotation = -0.2
			ctrl._weapon_spr.z_index = 4
		_:
			ctrl._weapon_spr.position = Vector2(8, -22)
			ctrl._weapon_spr.flip_h = false
			ctrl._weapon_spr.rotation = 0.45
			ctrl._weapon_spr.z_index = 6

static func _load_equip_tex(ctrl, item_id: String) -> Texture2D:
	var path = "res://assets/fx/equip_%s.png" % item_id.strip_edges()
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img = Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null

