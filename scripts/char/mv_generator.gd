class_name MVGenerator
extends RefCounted
## RPG Maker MV Generator 部件合成器：把 MV 的分层部件 PNG 叠成角色精灵/头像。
##
## 这是「角色外观参数化」的底层模块，玩家捏脸和 NPC 形象共用同一套数据模型：
##
##   外观 = 体型(gender) + 部件表(part_ids) + 配色(colors)
##     gender   : "female" / "male" / "kid"（对应 Generator 下的 Female/Male/Kid）
##     part_ids : { 类别: 变体号 } ，同一个键同时作用于头像和行走图
##     colors   : { "skin"/"hair"/"cloth": 色带下标 } ，见 GRADIENT 相关函数
##
## 对外只需这几个入口即可生成任意形象（NPC 也走这条）：
##     slots_for() / default_parts() / random_parts() / validate_parts()
##     compose_preview() / compose_all() / bake_sheet() / variant_layer_thumb()
##
## 颜色机制：部件美术按「参考色」绘制，文件名 _mNNN 标色组；上色 = 把像素相对
## 参考色的明暗偏移，映射到 gradients.png 所选色带内的横向位置。详见 _tint()。
##
## 注意：这些美术来自 RPG Maker MV（RTP/Generator），受 RPG Maker EULA 约束，
## 只能用于 RPG Maker 制作的游戏。此处仅作原型占位，上线前必须替换为自有理材。
## 仓库不提交任何 MV 素材，运行时从外部路径读取，烘到 user:// 缓存。

const DEFAULT_ROOT := "D:/SteamLibrary/steamapps/common/RPG Maker MV/Generator"

# 体型目录名（Generator 下的子目录）
const BODY_TYPES := ["Female", "Male", "Kid"]
# 部件来源目录
const SOURCES := ["Face", "TV"]

const TV_SIZE := Vector2i(144, 192)
const FACE_SIZE := Vector2i(144, 144)
const CELL := Vector2i(48, 48)

# 叠图顺序（底 -> 顶）。
# 依据部件 PNG 的实际像素结构：
#  - RearHair2 是整块不透明头发（含眼睛区域），必须放在脸型「后面」，由脸型盖住；
#  - RearHair1 在头顶不透明、但在眼睛区域透明，必须放在脸型「前面」来盖住头顶；
#  - FrontHair 是刘海，放最前。
const TV_ORDER := [
	"Wing1", "Wing2", "Tail1", "Tail2",
	"RearHair2", "Body", "RearHair1",
	"Clothing2", "Clothing1", "Cloak2", "Cloak1",
	"Ears", "BeastEars", "FrontHair1", "FrontHair2",
	"Beard1", "Beard2", "Glasses", "AccA", "AccB", "FacialMark",
]
const FACE_ORDER := [
	"RearHair2", "Body", "Ears", "Face",
	"Eyebrows", "Eyes", "Nose", "Mouth",
	"RearHair1", "FrontHair",
	"FacialMark", "BeastEars", "Clothing1", "Clothing2",
	"Cloak1", "Cloak2", "AccA", "AccB", "Glasses", "Beard",
]

# 归属「装备系统」的类别：建角界面不开放给玩家选（由装备系统在运行时决定）。
# 注意：合成器本身完整支持这些类别，装备系统直接把对应 part_ids 传进来即可出图。
const EQUIPMENT_CATS := [
	"Clothing1", "Clothing2", "Cloak1", "Cloak2",
	"AccA", "AccB", "Wing1", "Wing2", "Tail1", "Tail2",
	"Glasses",
]

# RPG Maker MV 官方调色板：Generator/gradients.png。
# 每条色带 4px 厚，只有最上面 1px 真正用于上色，共 280/4 = 70 条色带。
const GRADIENT_FILE := "gradients.png"

# 各色组（文件名 _mNNN）的官方参考色：部件美术就是用这些颜色画的，
# 上色 = 把像素相对参考色的明暗偏移映射到所选色带内的横向位置。
const M_REF := {
	1: Color(0.976, 0.757, 0.616),   # m001 肤色
	2: Color(0.173, 0.502, 0.796),   # m002 眼色
	3: Color(0.988, 0.796, 0.039),   # m003 发色
	4: Color(0.722, 0.573, 0.773),   # m004 发副色
	5: Color(0.0, 0.569, 0.588),     # m005 面部印记
	6: Color(0.827, 0.808, 0.780),   # m006 兽耳
	7: Color(0.682, 0.525, 0.510),   # m007 服装主色
	8: Color(0.996, 0.616, 0.118),   # m008 服装副色1
	9: Color(0.110, 0.463, 0.816),   # m009 服装副色2
	10: Color(0.851, 0.643, 0.016),  # m010 服装副色3
	11: Color(0.847, 0.675, 0.0),    # m011 披风主色
	12: Color(0.847, 0.675, 0.0),    # m012 披风副色(推测)
	13: Color(0.827, 0.808, 0.761),  # m013 配饰1主
	14: Color(0.855, 0.204, 0.431),  # m014 配饰1副1
	15: Color(0.643, 0.788, 0.067),  # m015 配饰1副2
	16: Color(0.780, 0.518, 0.027),  # m016 配饰2主
	17: Color(0.753, 0.827, 0.824),  # m017 配饰2副1
	18: Color(0.255, 0.333, 0.714),  # m018 配饰2副2
	19: Color(0.729, 0.231, 0.271),  # m019 配饰2副3
	20: Color(0.6, 0.6, 0.6),        # m020 眼镜主
	21: Color(0.8, 0.729, 0.824),    # m021 眼镜副1
	22: Color(0.376, 0.494, 0.294),  # m022 眼镜副2
}

# 可选部件（默认不显示，UI 提供「无」选项）。其余为必显部件（默认变体 1）。
const OPTIONAL := {
	"Wing1": 1, "Wing2": 1, "Tail1": 1, "Tail2": 1,
	"Cloak1": 1, "Cloak2": 1, "Glasses": 1, "AccA": 1, "AccB": 1,
	"BeastEars": 1, "Ears": 1, "FacialMark": 1, "Beard": 1,
	"Beard1": 1, "Beard2": 1,
}

# 槽位在 UI 里的显示顺序（只影响排序，绘制顺序由 TV_ORDER / FACE_ORDER 决定）。
const SLOT_ORDER := [
	"Face", "Body", "Ears", "BeastEars",
	"RearHair1", "RearHair2", "FrontHair", "FrontHair1", "FrontHair2",
	"Eyebrows", "Eyes", "Nose", "Mouth", "Beard", "Beard1", "Beard2",
	"FacialMark", "Glasses",
	"Clothing1", "Clothing2", "Cloak1", "Cloak2",
	"Wing1", "Wing2", "Tail1", "Tail2", "AccA", "AccB",
]

# 部件类别中文名。
const LABELS := {
	"Face": "脸型", "Body": "身体", "Ears": "耳朵", "BeastEars": "兽耳",
	"RearHair1": "后发1", "RearHair2": "后发2",
	"FrontHair": "前发", "FrontHair1": "前发1", "FrontHair2": "前发2",
	"Eyebrows": "眉毛", "Eyes": "眼睛", "Nose": "鼻子", "Mouth": "嘴",
	"Beard": "胡子", "Beard1": "胡子1", "Beard2": "胡子2",
	"FacialMark": "面部印记", "Glasses": "眼镜",
	"Clothing1": "上装", "Clothing2": "下装", "Cloak1": "披风1", "Cloak2": "披风2",
	"Wing1": "翅膀1", "Wing2": "翅膀2", "Tail1": "尾巴1", "Tail2": "尾巴2",
	"AccA": "配饰A", "AccB": "配饰B",
}

static var _re: RegEx = null
static var _re_mask: RegEx = null
static var _catalog_cache: Dictionary = {}
static var _grad: Image = null
static var _palette_rows: Array = []
static var _row_cache: Dictionary = {}
static var _thumb_cache: Dictionary = {}
static var _png_cache: Dictionary = {}
static var _slots_cache: Dictionary = {}
static var _variants_cache: Dictionary = {}
static var _preview_cache_key: String = ""
static var _preview_cache: Dictionary = {}
static var _preview_tv_key: String = ""
static var _preview_tv_sheet: Image = null
static var _preview_tv_frames: SpriteFrames = null
static var _preview_face_key: String = ""
static var _preview_face_img: Image = null
static var _preview_face_tex: Texture2D = null
static var _tinted_cache: Dictionary = {}
static var _lut_cache: Dictionary = {}
const TINTED_CACHE_MAX := 160


static func root_path() -> String:
	var configured := str(ProjectSettings.get_setting("rmmo/mv_generator_root", "")).strip_edges()
	if configured != "" and DirAccess.dir_exists_absolute(configured):
		return configured
	if DirAccess.dir_exists_absolute(DEFAULT_ROOT):
		return DEFAULT_ROOT
	# Box / Linux fallbacks (no Steam Generator install).
	for cand in [
		"/workspace/rmmo_runtime/Generator",
		"/workspace/rmmo_runtime/mv_generator",
		"/workspace/rmmo_runtime/mv_img/Generator",
	]:
		if DirAccess.dir_exists_absolute(cand):
			return cand
	return configured if configured != "" else DEFAULT_ROOT


static func _regex() -> RegEx:
	if _re == null:
		_re = RegEx.create_from_string("^(TV|FG)_([A-Za-z0-9]+)_p(\\d+)")
	return _re


static func _regex_mask() -> RegEx:
	if _re_mask == null:
		_re_mask = RegEx.create_from_string("_m(\\d+)")
	return _re_mask


## 体型字符串归一到 Generator 目录名：female/male/kid。
static func gender_cap(gender: String) -> String:
	var g := gender.strip_edges().to_lower()
	if g == "male" or g == "m" or g == "男":
		return "Male"
	if g == "kid" or g == "child" or g == "k" or g == "儿童" or g == "小孩":
		return "Kid"
	return "Female"


static func _gender_cap(gender: String) -> String:
	return gender_cap(gender)


## 清空所有缓存（目录扫描 / 渐变图 / 色带）。换素材目录或热重载时调用。
static func clear_cache() -> void:
	_catalog_cache.clear()
	_row_cache.clear()
	_palette_rows.clear()
	_thumb_cache.clear()
	_png_cache.clear()
	_slots_cache.clear()
	_variants_cache.clear()
	_tinted_cache.clear()
	_lut_cache.clear()
	_preview_cache_key = ""
	_preview_cache.clear()
	_preview_tv_key = ""
	_preview_tv_sheet = null
	_preview_tv_frames = null
	_preview_face_key = ""
	_preview_face_img = null
	_preview_face_tex = null
	_grad = null


## 扫描某 (src, gender) 目录，返回 { 类别: { 变体号(int): {path, m} } }。
## m = 文件名里的 _mNNN 色组编号（1=肤 2=眼 3/4=发 5=印记 6=兽耳 7+=衣/披风/配饰/眼镜）。
static func _catalog(src: String, gender: String) -> Dictionary:
	var key := "%s/%s" % [src, _gender_cap(gender)]
	if _catalog_cache.has(key):
		return _catalog_cache[key]
	var folder := "%s/%s/%s" % [root_path(), src, _gender_cap(gender)]
	var out := {}
	var d := DirAccess.open(folder)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			# 注意：不能用 continue 跳过本层，否则会漏掉 f = d.get_next() 造成死循环。
			if not d.current_is_dir() and f.ends_with(".png") and not f.ends_with("_c.png"):
				var m := _regex().search(f)
				if m != null:
					var mm := _regex_mask().search(f)
					var cat := m.get_string(2)
					var v := m.get_string(3).to_int()
					if not out.has(cat):
						out[cat] = {}
					# 同一变体可能有多个染色层（如 m003 主发色 + m004 副色），原型只取第一层。
					# TV 部件文件名没有 _mNNN（色组按类别隐含），m 记 0，由 _user_group 兜底。
					if not out[cat].has(v):
						var mi := 0
						if mm != null:
							mi = mm.get_string(1).to_int()
						out[cat][v] = {"path": folder + "/" + f, "m": mi}
			f = d.get_next()
		d.list_dir_end()
	_catalog_cache[key] = out
	return out


static func _available(src: String, gender: String, cat: String) -> bool:
	var c := _catalog(src, gender)
	return c.has(cat) and (c[cat] as Dictionary).size() > 0


## 某类别的可用变体号（升序）。
static func list_variants(src: String, gender: String, cat: String) -> PackedInt32Array:
	var key := "%s/%s/%s" % [src, _gender_cap(gender), cat]
	if _variants_cache.has(key):
		return _variants_cache[key]
	var out := PackedInt32Array()
	if not _available(src, gender, cat):
		_variants_cache[key] = out
		return out
	var vs := (_catalog(src, gender)[cat] as Dictionary).keys()
	vs.sort()
	for v in vs:
		out.append(int(v))
	_variants_cache[key] = out
	return out


## MV 官方上色机制（来自生成器结构文档）：
##  1. gradients.png 每条色带 4px 厚，只有最上面 1px 用于上色，共 280/4 = 70 条色带；
##  2. 部件美术用「参考色」（M_REF）绘制，文件名 _mNNN 标明它属于哪个色组；
##  3. 上色时把部件像素相对参考色的明暗偏移，映射到所选色带内的横向位置：
##     比参考色亮 → 取色带里更亮的颜色，比参考色暗 → 取更深的阴影色。

static func _gradients() -> Image:
	if _grad != null:
		return _grad
	var img := Image.new()
	if img.load(root_path() + "/" + GRADIENT_FILE) == OK:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		_grad = img
	return _grad


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## 文件名 _mNNN 色组 -> 用户可调的三组配色（肤 / 发 / 衣）。
## 眼色(m002)、面部印记(m005)、兽耳(m006) 不在用户可调范围，保留参考色。
static func _m_user_group(m: int) -> String:
	if m == 1:
		return "skin"
	if m == 3 or m == 4:
		return "hair"
	if m >= 7:
		return "cloth"
	return ""


## TV 部件文件名没有 _mNNN，按类别名兜底归入配色分组。
const CAT_FALLBACK_GROUP := {
	"Body": "skin", "Ears": "skin",
	"RearHair1": "hair", "RearHair2": "hair",
	"FrontHair1": "hair", "FrontHair2": "hair",
	"Beard1": "hair", "Beard2": "hair",
	"Clothing1": "cloth", "Clothing2": "cloth",
	"Cloak1": "cloth", "Cloak2": "cloth",
}


static func _user_group(cat: String, m: int) -> String:
	if m > 0:
		return _m_user_group(m)
	return str(CAT_FALLBACK_GROUP.get(cat, ""))


## 取第 index 条色带（0..69）的缓存数据：rgb 字节 + 每列亮度。
static func _row_data(index: int) -> Dictionary:
	if _row_cache.has(index):
		return _row_cache[index]
	var rgb := PackedByteArray()
	var lum := PackedFloat32Array()
	var grad := _gradients()
	var y := index * 4
	if grad != null and not grad.is_empty() and y < grad.get_height():
		var w := grad.get_width()
		var data := grad.get_data()
		var off := y * w * 4
		rgb.resize(w * 3)
		lum.resize(w)
		for x in range(w):
			var i := off + x * 4
			rgb[x * 3] = data[i]
			rgb[x * 3 + 1] = data[i + 1]
			rgb[x * 3 + 2] = data[i + 2]
			lum[x] = _lum(Color(float(data[i]) / 255.0, float(data[i + 1]) / 255.0, float(data[i + 2]) / 255.0))
	_row_cache[index] = {"rgb": rgb, "lum": lum}
	return _row_cache[index]


## 第 index 条色带的代表色（亮度最接近 0.55 的那格，作 UI 色块用）。
static func row_color(index: int) -> Color:
	if index < 0:
		return Color(0.5, 0.5, 0.5)
	var rd := _row_data(index)
	var lum: PackedFloat32Array = rd["lum"]
	var rgb: PackedByteArray = rd["rgb"]
	if lum.is_empty():
		return Color(0.5, 0.5, 0.5)
	var best_x := 0
	var best_d := 2.0
	for x in range(lum.size()):
		var d := absf(lum[x] - 0.55)
		if d < best_d:
			best_d = d
			best_x = x
	return Color8(rgb[best_x * 3], rgb[best_x * 3 + 1], rgb[best_x * 3 + 2])


## 全部色带 [{index, color}]。
static func palette() -> Array:
	if not _palette_rows.is_empty():
		return _palette_rows
	var grad := _gradients()
	var out := []
	if grad != null and not grad.is_empty():
		for i in range(grad.get_height() / 4):
			out.append({"index": i, "color": row_color(i)})
	_palette_rows = out
	return out


## 指定分组的色板。皮肤只保留肤色系的色带（暖色、中低饱和、够亮）；
## 发色/服装开放全部色带。若肤色筛选结果为空则退回全量。
static func palette_for(group: String) -> Array:
	var all := palette()
	if group != "skin":
		return all
	var out := []
	for e in all:
		if _is_skin(e["color"] as Color):
			out.append(e)
	if out.is_empty():
		return all
	return out


static func _is_skin(c: Color) -> bool:
	var hue := c.h * 360.0
	return hue >= 5.0 and hue <= 55.0 and c.s <= 0.75 and maxf(c.r, maxf(c.g, c.b)) >= 0.45


## 某分组的默认色带下标（无可用色带返回 -1，表示不上色）。
static func default_row(group: String) -> int:
	var p := palette_for(group)
	if p.is_empty():
		return -1
	return int((p[0] as Dictionary)["index"])


## 按 MV 官方机制给部件上色：
## 部件美术用参考色绘制，把每个像素相对 ref_lum 的明暗偏移
## 映射到所选色带内的横向位置（亮 -> 色带更亮处，暗 -> 更深处）。
static func _tint(img: Image, index: int, ref_lum: float) -> void:
	if index < 0:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var rd := _row_data(index)
	var lum: PackedFloat32Array = rd["lum"]
	var rgb: PackedByteArray = rd["rgb"]
	if lum.is_empty():
		return
	var w := lum.size()
	# 色带里与参考色亮度最接近的位置 = 「纯色」锚点。
	var x_ref := 0
	var best_d := 2.0
	for x in range(w):
		var d := absf(lum[x] - ref_lum)
		if d < best_d:
			best_d = d
			x_ref = x
	var lut := _tint_lut(index, x_ref, ref_lum, rgb, w)
	var data := img.get_data()
	var n := data.size()
	var i := 0
	while i < n:
		if data[i + 3] > 0:
			# 0.299/0.587/0.114 → 77/150/29；>>8 后落在 0..255。
			var L := (77 * int(data[i]) + 150 * int(data[i + 1]) + 29 * int(data[i + 2])) >> 8
			var li := L * 3
			data[i] = lut[li]
			data[i + 1] = lut[li + 1]
			data[i + 2] = lut[li + 2]
		i += 4
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## 8bit 亮度 -> 色带 RGB。同一条色带 + 同一参考亮度只建一次。
static func _tint_lut(index: int, x_ref: int, ref_lum: float, rgb: PackedByteArray, w: int) -> PackedByteArray:
	var key := "%d|%d|%d" % [index, x_ref, int(round(ref_lum * 255.0))]
	if _lut_cache.has(key):
		return _lut_cache[key]
	var lut := PackedByteArray()
	lut.resize(256 * 3)
	var ref_off := int(round(ref_lum * 255.0))
	for L in range(256):
		var x := clampi(x_ref + ref_off - L, 0, w - 1)
		var xi := x * 3
		var li := L * 3
		lut[li] = rgb[xi]
		lut[li + 1] = rgb[xi + 1]
		lut[li + 2] = rgb[xi + 2]
	_lut_cache[key] = lut
	return lut


## 递归创建目录（仅使用 DirAccess 实例方法，避免不同 Godot 版本对静态 API 的差异）。
static func ensure_dir(abs_path: String) -> bool:
	abs_path = abs_path.simplify_path()
	if abs_path.is_empty() or abs_path == "." or abs_path == "/":
		return true
	var parent := abs_path.get_base_dir()
	var child := abs_path.get_file()
	if parent.is_empty() or child.is_empty():
		return true
	if not ensure_dir(parent):
		return false
	var da := DirAccess.open(parent)
	if da == null:
		return false
	if da.dir_exists(child):
		return true
	return da.make_dir_recursive(child) == OK


## 建角界面槽位：自动扫描该体型下 Face + TV 的可用类别，带 optional 标记。
## include_equipment=false（默认）时排除装备系统负责的类别，只留身体外观。
static func slots_for(gender: String, include_equipment: bool = false) -> Array:
	var cache_key := "%s|%s" % [_gender_cap(gender), str(include_equipment)]
	if _slots_cache.has(cache_key):
		return _slots_cache[cache_key]
	# part_ids 只按类别名存一份（同一个键同时作用于头像和行走图），所以同名类别
	# （Body/Ears/上装... Face 与 TV 都有）只留一行：保留变体更多的那一侧，
	# 避免像「上装」那样 Face 只有 1 个变体、TV 有 26 个时把选项弄丢。
	var best := {}
	for src in ["Face", "TV"]:
		var cmap := _catalog(src, gender)
		for cat in cmap.keys():
			if not include_equipment and (cat in EQUIPMENT_CATS):
				continue
			if not cmap.has(cat) or (cmap[cat] as Dictionary).is_empty():
				continue
			var n := (cmap[cat] as Dictionary).size()
			if (not best.has(cat)) or n > int(best[cat]["n"]):
				best[cat] = {"src": src, "n": n}
	var entries := []
	for cat in best.keys():
		entries.append({"src": best[cat]["src"], "cat": cat})
	entries.sort_custom(func(a, b): return _slot_rank(a["cat"]) < _slot_rank(b["cat"]))
	var out := []
	for e in entries:
		var cat: String = e["cat"]
		out.append({cat = cat, src = e["src"], label = _label(cat), optional = OPTIONAL.has(cat)})
	_slots_cache[cache_key] = out
	return out


static func _slot_rank(cat: String) -> int:
	var i := SLOT_ORDER.find(cat)
	return i if i >= 0 else SLOT_ORDER.size()


static func _label(cat: String) -> String:
	return str(LABELS.get(cat, cat))


## 选角页空闲时预热目录扫描和默认部件 PNG，避免点「创建角色」才卡一下。
static func warmup(gender: String) -> void:
	palette()
	slots_for(gender)
	var parts := default_parts(gender)
	for src in SOURCES:
		var size: Vector2i = TV_SIZE if src == "TV" else FACE_SIZE
		var catmap := _catalog(src, gender)
		for cat in parts.keys():
			if not catmap.has(cat):
				continue
			var cmap: Dictionary = catmap[cat]
			var v := int(parts[cat])
			if cmap.has(v):
				_load_part_image(str(cmap[v]["path"]), size)


## 默认部件选择：必显部件给变体 1，可选部件不出现。
static func default_parts(gender: String) -> Dictionary:
	var d := {}
	for cat in TV_ORDER:
		if not OPTIONAL.has(cat) and _available("TV", gender, cat):
			d[cat] = _default_variant("TV", gender, cat)
	for cat in FACE_ORDER:
		if not OPTIONAL.has(cat) and _available("Face", gender, cat):
			d[cat] = _default_variant("Face", gender, cat)
	return d


static func _default_variant(src: String, gender: String, cat: String) -> int:
	var vs := list_variants(src, gender, cat)
	if vs.is_empty():
		return 1
	return vs[0]


## 校验并修正部件表：丢弃该体型不存在的类别，变体号越界时退到 1。
## 外部数据（存档 / NPC 配置 / 装备）进入合成前都应先过一遍，避免渲染异常。
static func validate_parts(gender: String, part_ids: Dictionary) -> Dictionary:
	var out := {}
	for cat in part_ids.keys():
		var v := int(part_ids[cat])
		var found := false
		for src in SOURCES:
			if not _available(src, gender, cat):
				continue
			found = true
			if not list_variants(src, gender, cat).has(v):
				v = 1
			break
		if found:
			out[cat] = v
	return out


## 随机生成一套部件（NPC 批量出形象用）。
## include_equipment 控制是否也随机服装/披风/配饰等装备系统负责的类别。
static func random_parts(gender: String, include_equipment: bool = false) -> Dictionary:
	var d := default_parts(gender)
	for slot in slots_for(gender, include_equipment):
		var cat: String = slot["cat"]
		var vs := list_variants(slot["src"], gender, cat)
		if vs.is_empty():
			continue
		d[cat] = vs[randi() % vs.size()]
	return d


## 把装备叠加到部件表上（返回新字典，不改动入参）。
## equipment 里值为 null 表示卸下该部位；装备系统只维护 equipment 即可。
static func apply_equipment(part_ids: Dictionary, equipment: Dictionary) -> Dictionary:
	var out := part_ids.duplicate()
	for cat in equipment.keys():
		var v = equipment[cat]
		if v == null:
			out.erase(cat)
		else:
			out[cat] = int(v)
	return out


## 部件的参考色：优先用文件名色组 _mNNN 的官方参考色；
## TV 部件没有 _mNNN，用所属分组的主参考色兜底（肤=m001 发=m003 衣=m007）。
static func _ref_for(cat: String, m: int) -> Color:
	if m > 0 and M_REF.has(m):
		return M_REF[m]
	match _user_group(cat, m):
		"hair":
			return M_REF[3]
		"cloth":
			return M_REF[7]
		_:
			return M_REF[1]



## 缓存部件 PNG（未上色，只读）。需要改像素（上色）时再 duplicate。
static func _load_part_image(path: String, size: Vector2i) -> Image:
	var key := "%s|%d×%d" % [path, size.x, size.y]
	if _png_cache.has(key):
		return _png_cache[key]
	var img := Image.new()
	if img.load(path) != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_size() != size:
		img.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	_png_cache[key] = img
	return img


## 已上色的一层（只读）。换单个部件时其它层直接复用，避免整脸重算。
static func _tinted_part(path: String, size: Vector2i, row: int, ref_lum: float) -> Image:
	if row < 0:
		return _load_part_image(path, size)
	var key := "%s|%d×%d|%d|%d" % [path, size.x, size.y, row, int(round(ref_lum * 10000.0))]
	if _tinted_cache.has(key):
		return _tinted_cache[key]
	var src := _load_part_image(path, size)
	if src == null:
		return null
	var img := src.duplicate()
	_tint(img, row, ref_lum)
	if _tinted_cache.size() >= TINTED_CACHE_MAX:
		_tinted_cache.clear()
	_tinted_cache[key] = img
	return img


## 把一层层部件叠成一张图。
## colors 支持两种键：
##   "skin"/"hair"/"cloth" —— 用户可调的三组（部件按色组自动归属）
##   "m3" / "m007" 形式的色组键 —— 精确指定某个 _mNNN 色组（细粒度，装备/NPC 用）
static func _render(src: String, gender: String, part_ids: Dictionary, colors: Dictionary = {}) -> Image:
	var size: Vector2i = TV_SIZE if src == "TV" else FACE_SIZE
	var base := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var catmap := _catalog(src, gender)
	var order := TV_ORDER if src == "TV" else FACE_ORDER
	for cat in order:
		if not part_ids.has(cat):
			continue
		var v := int(part_ids[cat])
		if not catmap.has(cat) or not (catmap[cat] as Dictionary).has(v):
			continue
		var info: Dictionary = catmap[cat][v]
		# 按 MV 色组上色：优先精确色组键，其次用户分组。
		var m := int(info["m"])
		var row := -1
		if m > 0 and colors.has("m%d" % m):
			row = int(colors["m%d" % m])
		if row < 0:
			var g := _user_group(cat, m)
			if g != "" and colors.has(g):
				row = int(colors[g])
		var pimg: Image
		if row >= 0:
			pimg = _tinted_part(str(info["path"]), size, row, _lum(_ref_for(cat, m)))
		else:
			pimg = _load_part_image(str(info["path"]), size)
		if pimg == null:
			continue
		base.blend_rect(pimg, Rect2i(0, 0, size.x, size.y), Vector2i.ZERO)
	return base


## 把 144x192 的 MMV 部件表切成 4 向 × 3 帧 SpriteFrames（命名兼容 LookCatalog）。
static func sheet_to_frames(sheet: Image) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var atlas := ImageTexture.create_from_image(sheet)
	var dirs := ["front", "left", "right", "back"]
	for di in range(4):
		var walk := "walk_%s" % dirs[di]
		if frames.has_animation(walk):
			frames.remove_animation(walk)
		frames.add_animation(walk)
		frames.set_animation_speed(walk, 8.0)
		frames.set_animation_loop(walk, true)
		var idle := "idle_%s" % dirs[di]
		if frames.has_animation(idle):
			frames.remove_animation(idle)
		frames.add_animation(idle)
		frames.set_animation_speed(idle, 1.0)
		frames.set_animation_loop(idle, true)
		for f in range(3):
			frames.add_frame(walk, _cell_atlas(atlas, f, di))
		frames.add_frame(idle, _cell_atlas(atlas, 1, di))
	return frames


static func _cell_atlas(atlas: Texture2D, col: int, row: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = atlas
	at.region = Rect2(col * CELL.x, row * CELL.y, CELL.x, CELL.y)
	return at


static func _cell_tex(sheet: Image, col: int, row: int) -> Texture2D:
	var sub := Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
	sub.blit_rect(sheet, Rect2(col * CELL.x, row * CELL.y, CELL.x, CELL.y), Vector2.ZERO)
	return ImageTexture.create_from_image(sub)



## 建角下拉用：只渲「这一层」部件（不上全套叠图），区分变体足够且极快。
## Face 槽缩到 size；TV 槽取正面站立 48 格再缩。
static func variant_layer_thumb(
	src: String,
	gender: String,
	cat: String,
	variant: int,
	size: int = 40
) -> Texture2D:
	if src != "TV" and src != "Face":
		src = "Face"
	var key := "layer|%s|%s|%s|%d|%d" % [src, gender, cat, variant, size]
	if _thumb_cache.has(key):
		return _thumb_cache[key]
	var catmap := _catalog(src, gender)
	if not catmap.has(cat) or not (catmap[cat] as Dictionary).has(variant):
		# 对侧来源兜底（Face 没有就试 TV）
		var other := "TV" if src == "Face" else "Face"
		catmap = _catalog(other, gender)
		src = other
		if not catmap.has(cat) or not (catmap[cat] as Dictionary).has(variant):
			var empty := Image.create(size, size, false, Image.FORMAT_RGBA8)
			var et := ImageTexture.create_from_image(empty)
			_thumb_cache[key] = et
			return et
	var info: Dictionary = catmap[cat][variant]
	var full: Vector2i = TV_SIZE if src == "TV" else FACE_SIZE
	var raw := _load_part_image(str(info["path"]), full)
	var img: Image
	if raw == null:
		img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	elif src == "TV":
		img = Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
		img.blit_rect(raw, Rect2i(CELL.x, 0, CELL.x, CELL.y), Vector2i.ZERO)
	else:
		img = raw.duplicate()
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[key] = tex
	return tex


## 整套叠图缩略（重）；建角下拉请用 variant_layer_thumb。
static func part_thumb(
	gender: String,
	part_ids: Dictionary,
	colors: Dictionary = {},
	prefer_src: String = "Face",
	size: int = 48
) -> Texture2D:
	var src := prefer_src
	if src != "TV" and src != "Face":
		src = "Face"
	var cats: Array = part_ids.keys()
	cats.sort()
	var key := "full|%s|%s|%d|" % [gender, src, size]
	for c in cats:
		key += "%s=%d;" % [str(c), int(part_ids[c])]
	var color_keys: Array = colors.keys()
	color_keys.sort()
	for ck in color_keys:
		key += "%s=%d;" % [str(ck), int(colors[ck])]
	if _thumb_cache.has(key):
		return _thumb_cache[key]
	var img: Image
	if src == "TV":
		var sheet := _render("TV", gender, part_ids, colors)
		img = Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
		img.blit_rect(sheet, Rect2i(CELL.x, 0, CELL.x, CELL.y), Vector2i.ZERO)
	else:
		img = _render("Face", gender, part_ids, colors)
		if img.get_used_rect().size == Vector2i.ZERO:
			var sheet2 := _render("TV", gender, part_ids, colors)
			img = Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
			img.blit_rect(sheet2, Rect2i(CELL.x, 0, CELL.x, CELL.y), Vector2i.ZERO)
	if img.get_width() != size or img.get_height() != size:
		img = img.duplicate()
		img.resize(size, size, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[key] = tex
	return tex



static func _src_preview_key(src: String, gender: String, part_ids: Dictionary, colors: Dictionary) -> String:
	var order := TV_ORDER if src == "TV" else FACE_ORDER
	var key := "%s|%s|" % [src, _gender_cap(gender)]
	for cat in order:
		if part_ids.has(cat):
			key += "%s=%d;" % [cat, int(part_ids[cat])]
	var cks: Array = colors.keys()
	cks.sort()
	for ck in cks:
		key += "%s=%d;" % [str(ck), int(colors[ck])]
	return key


## 建角实时预览：只切正面 walk 3 帧 + 头像（不做四向），比 compose_all 轻很多。
static func compose_preview(gender: String, part_ids: Dictionary, colors: Dictionary = {}) -> Dictionary:
	var cats: Array = part_ids.keys()
	cats.sort()
	var key := "%s|" % gender
	for c in cats:
		key += "%s=%d;" % [str(c), int(part_ids[c])]
	var cks: Array = colors.keys()
	cks.sort()
	for ck in cks:
		key += "%s=%d;" % [str(ck), int(colors[ck])]
	if key == _preview_cache_key and not _preview_cache.is_empty():
		return _preview_cache
	var tv_key := _src_preview_key("TV", gender, part_ids, colors)
	var sheet: Image
	var frames: SpriteFrames
	if tv_key == _preview_tv_key and _preview_tv_sheet != null and _preview_tv_frames != null:
		sheet = _preview_tv_sheet
		frames = _preview_tv_frames
	else:
		sheet = _render("TV", gender, part_ids, colors)
		frames = SpriteFrames.new()
		frames.add_animation("walk_front")
		frames.set_animation_speed("walk_front", 8.0)
		frames.set_animation_loop("walk_front", true)
		var atlas := ImageTexture.create_from_image(sheet)
		for f in range(3):
			frames.add_frame("walk_front", _cell_atlas(atlas, f, 0))
		_preview_tv_key = tv_key
		_preview_tv_sheet = sheet
		_preview_tv_frames = frames
	var face_key := _src_preview_key("Face", gender, part_ids, colors)
	var pimg: Image
	var portrait: Texture2D
	if face_key == _preview_face_key and _preview_face_img != null and _preview_face_tex != null:
		pimg = _preview_face_img
		portrait = _preview_face_tex
	else:
		pimg = _render("Face", gender, part_ids, colors)
		portrait = ImageTexture.create_from_image(pimg)
		_preview_face_key = face_key
		_preview_face_img = pimg
		_preview_face_tex = portrait
	var res := {"sheet": sheet, "frames": frames, "portrait": portrait}
	_preview_cache_key = key
	_preview_cache = res
	return res


## 一次性合成身体(4向行走) + 头像，返回 {sheet, frames, portrait}。
## colors 形如 {"skin"/"hair"/"cloth": 色带下标}，缺省的分组保留部件参考色。
static func compose_all(gender: String, part_ids: Dictionary, colors: Dictionary = {}) -> Dictionary:
	var sheet := _render("TV", gender, part_ids, colors)
	var frames := sheet_to_frames(sheet)
	var pimg := _render("Face", gender, part_ids, colors)
	var portrait := ImageTexture.create_from_image(pimg)
	return {"sheet": sheet, "frames": frames, "portrait": portrait}


static func compose_frames(gender: String, part_ids: Dictionary, colors: Dictionary = {}) -> SpriteFrames:
	return sheet_to_frames(_render("TV", gender, part_ids, colors))


## 烘一张角色表到磁盘（user:// 缓存，不进仓库）。
static func bake_sheet(gender: String, part_ids: Dictionary, save_path: String, colors: Dictionary = {}) -> bool:
	var sheet := _render("TV", gender, part_ids, colors)
	ensure_dir(save_path.get_base_dir())
	return sheet.save_png(save_path) == OK


## 选角/世界：从已烘表读取（同步，无需渲染）。
static func load_sheet_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	# 取 front 中间帧作图标
	return _cell_tex(img, 1, 0)


static func load_sheet_frames(path: String) -> SpriteFrames:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return sheet_to_frames(img)
