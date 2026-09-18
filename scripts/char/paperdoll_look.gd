extends RefCounted
## Standing paperdoll portrait: gender body + equipped MV layers.
## Combat slots map onto Generator clothing/accessory cats; items may set mv_parts.

const MV = preload("res://scripts/char/mv_generator.gd")
const LookCatalog = preload("res://scripts/char/look_catalog.gd")
const Customization = preload("res://scripts/char/customization.gd")

## paperdoll slot -> MV Generator category (上装/下装/配饰).
const SLOT_MV_CAT := {
	"chest": "Clothing1",
	"legs": "Clothing2",
	"necklace": "AccA",
	"earring_l": "AccB",
	"earring_r": "AccB",
}


static func standing_texture(ch: Dictionary, equipment: Array, catalog = null) -> Texture2D:
	var gender := LookCatalog.normalize_gender(str(ch.get("gender", LookCatalog.GENDER_FEMALE)))
	var cust := Customization.from_dict(_custom_dict(ch))
	var parts: Dictionary = cust.part_ids.duplicate()
	if parts.is_empty():
		parts = MV.default_parts(gender)
	var mv_eq := equipment_to_mv_parts(gender, equipment, catalog)
	parts = MV.apply_equipment(parts, mv_eq)
	parts = MV.validate_parts(gender, parts)
	var tex := _compose_standing(gender, parts, cust.colors())
	if tex != null:
		return tex
	return _fallback_idle(ch, gender)


## Combat equipment snapshot -> { MV_cat: variant_id }.
static func equipment_to_mv_parts(gender: String, equipment: Array, catalog = null) -> Dictionary:
	var out := {}
	for it in equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid := str(it.get("item_id", it.get("id", ""))).strip_edges()
		if iid.is_empty():
			continue
		var sid := str(it.get("slot", "")).strip_edges()
		var def := _item_def(catalog, iid)
		var explicit: Variant = def.get("mv_parts", null)
		if typeof(explicit) == TYPE_DICTIONARY and not (explicit as Dictionary).is_empty():
			for cat in (explicit as Dictionary).keys():
				out[str(cat)] = int(explicit[cat])
			continue
		var cat := str(def.get("mv_cat", "")).strip_edges()
		if cat.is_empty():
			cat = str(SLOT_MV_CAT.get(sid, "")).strip_edges()
		if cat.is_empty():
			continue
		if out.has(cat):
			continue
		var variant := int(def.get("mv_variant", 0))
		if variant <= 0:
			variant = _pick_variant(gender, cat, iid)
		if variant > 0:
			out[cat] = variant
	return out


static func _compose_standing(gender: String, parts: Dictionary, colors: Dictionary) -> Texture2D:
	if parts.is_empty():
		return null
	var res: Dictionary = MV.compose_preview(gender, parts, colors)
	var frames: SpriteFrames = res.get("frames", null)
	if frames != null and frames.has_animation("walk_front"):
		var n: int = frames.get_frame_count("walk_front")
		if n > 0:
			var idx := 1 if n > 1 else 0
			var t: Texture2D = frames.get_frame_texture("walk_front", idx)
			if t != null:
				return t
	var sheet: Image = res.get("sheet", null)
	if sheet != null and not sheet.is_empty():
		## TV sheet 3×4 of 48px; front standing = col 1 row 0.
		var cell := MV.CELL
		if sheet.get_width() >= cell.x * 2 and sheet.get_height() >= cell.y:
			var crop := sheet.get_region(Rect2i(cell.x, 0, cell.x, cell.y))
			if crop != null and not crop.is_empty():
				return ImageTexture.create_from_image(crop)
	return null


static func _fallback_idle(ch: Dictionary, gender: String) -> Texture2D:
	var look_id := str(ch.get("look_id", "1")).strip_edges()
	if look_id.is_empty():
		look_id = "1"
	var idle: Texture2D = LookCatalog.load_idle(look_id, "Front", gender)
	if idle != null:
		return idle
	return null


static func _pick_variant(gender: String, cat: String, item_id: String) -> int:
	var vs := MV.list_variants("TV", gender, cat)
	if vs.is_empty():
		vs = MV.list_variants("Face", gender, cat)
	if vs.is_empty():
		return -1
	return vs[absi(item_id.hash()) % vs.size()]


static func _custom_dict(ch: Dictionary) -> Dictionary:
	var v: Variant = ch.get("customization", {})
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}


static func _item_def(catalog, item_id: String) -> Dictionary:
	if catalog == null or item_id.is_empty():
		return {}
	if catalog.has_method("get_item"):
		var d: Dictionary = catalog.get_item(item_id)
		if typeof(d) == TYPE_DICTIONARY:
			return d
	return {}
