extends RefCounted
## Looks by gender. External content://look/{female|male}/{id}; empty until first-party looks exist.

const GENDER_FEMALE := "female"
const GENDER_MALE := "male"
const GENDER_KID := "kid"

static func normalize_gender(gender: String) -> String:
	var g := gender.strip_edges().to_lower()
	if g == GENDER_MALE or g == "m" or g == "男":
		return GENDER_MALE
	if g == GENDER_KID or g == "k" or g == "儿童" or g == "小孩":
		return GENDER_KID
	return GENDER_FEMALE

static func list_look_ids(gender: String = GENDER_FEMALE) -> PackedStringArray:
	if normalize_gender(gender) == GENDER_MALE:
		return _list_male_ids()
	return _list_walk_ids()

static func _list_walk_ids() -> PackedStringArray:
	return _list_look_dir("female")

static func _list_male_ids() -> PackedStringArray:
	return _list_look_dir("male")

static func _list_look_dir(sub: String) -> PackedStringArray:
	var ids: Array[String] = []
	var am = _am()
	if am == null or not am.has_method("content_root"):
		return PackedStringArray()
	var dir_path := "%s/assets/look/%s" % [str(am.content_root()), sub]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return PackedStringArray()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".png"):
			ids.append(name.get_basename())
		name = dir.get_next()
	return PackedStringArray(_sort_ids(ids))

static func _am():
	var loop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("AssetManager")

static func _sort_ids(ids: Array[String]) -> Array[String]:
	ids.sort_custom(func(a: String, b: String) -> bool:
		if a.is_valid_int() and b.is_valid_int():
			return a.to_int() < b.to_int()
		return a < b
	)
	return ids

static func idle_texture_path(look_id: String, facing: String = "Front", gender: String = GENDER_FEMALE) -> String:
	var sub := "male" if normalize_gender(gender) == GENDER_MALE else "female"
	return "content://look/%s/%s" % [sub, look_id]

static func walk_frame_path(look_id: String, facing: String, frame: int) -> String:
	return "content://look/female/%s_%s_%d" % [look_id, facing.to_lower(), frame]

static func load_idle(look_id: String, facing: String = "Front", gender: String = GENDER_FEMALE) -> Texture2D:
	var am = _am()
	if am == null or not am.has_method("load_texture"):
		return null
	var t: Texture2D = am.load_texture(idle_texture_path(look_id, facing, gender))
	if t != null:
		return t
	return am.load_texture("content://look/%s" % look_id)

static func world_sprite_scale(gender: String) -> Vector2:
	## Female walk sprites are 64px; male portraits ~230px — normalize height ~64.
	if normalize_gender(gender) == GENDER_MALE:
		return Vector2(0.28, 0.28)
	return Vector2(1.35, 1.35)

static func preview_sprite_scale(gender: String) -> Vector2:
	if normalize_gender(gender) == GENDER_MALE:
		return Vector2(0.55, 0.55)
	return Vector2(3.0, 3.0)

static func build_walk_frames(look_id: String, gender: String = GENDER_FEMALE) -> SpriteFrames:
	if normalize_gender(gender) == GENDER_MALE:
		return _build_static_frames(look_id)
	return _build_female_walk_frames(look_id)

static func _build_static_frames(look_id: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var tex := load_idle(look_id, "Front", GENDER_MALE)
	for facing: String in ["Front", "Back", "Left", "Right"]:
		var key: String = facing.to_lower()
		for kind: String in ["walk", "idle"]:
			var anim: String = "%s_%s" % [kind, key]
			if frames.has_animation(anim):
				frames.remove_animation(anim)
			frames.add_animation(anim)
			frames.set_animation_speed(anim, 1.0)
			frames.set_animation_loop(anim, true)
			if tex:
				frames.add_frame(anim, tex)
	return frames

static func _build_female_walk_frames(look_id: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	for facing: String in ["Front", "Back", "Left", "Right"]:
		var anim: String = "walk_%s" % facing.to_lower()
		if frames.has_animation(anim):
			frames.remove_animation(anim)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 8.0)
		frames.set_animation_loop(anim, true)
		for i in range(1, 5):
			var am = _am()
			var tex: Texture2D = null
			if am != null and am.has_method("load_texture"):
				tex = am.load_texture(walk_frame_path(look_id, facing, i))
			if tex:
				frames.add_frame(anim, tex)
		var idle_anim: String = "idle_%s" % facing.to_lower()
		if frames.has_animation(idle_anim):
			frames.remove_animation(idle_anim)
		frames.add_animation(idle_anim)
		frames.set_animation_speed(idle_anim, 1.0)
		frames.set_animation_loop(idle_anim, true)
		var idle := load_idle(look_id, facing, GENDER_FEMALE)
		if idle:
			frames.add_frame(idle_anim, idle)
	return frames
