class_name Customization
extends RefCounted
## 角色外观数据（玩家捏脸与 NPC 形象共用）。
##
## 一个外观 = 体型(gender) + 部件表(part_ids) + 配色(色带下标) + 装备(equipment)。
## 配色保存稳定 ID：旧色带 0..69，K 系列发色 1001..1230。合成时由 MVGenerator 按部件的
## _mNNN 色组「参考色锚点 + 色带映射」上色。
##
## 装备不混进 part_ids：equipment 单独存，取 effective_part_ids() 时才叠加，
## 这样换装只改 equipment，身体外观 part_ids 保持干净。

const MV = preload("res://scripts/char/mv_generator.gd")
const Shapes = preload("res://scripts/char/character_body_shapes.gd")

const GROUPS := ["skin", "hair", "cloth"]

var skin_row: int = MV.default_row("skin")
var hair_row: int = MV.default_row("hair")
var cloth_row: int = MV.default_row("cloth")
var skin_on: bool = true
var hair_on: bool = true
var cloth_on: bool = false
## Empty eye colour preserves the source iris. Bust 0.5 is the original adult female shape.
var eye_color: String = ""
var bust_size: float = 0.5
## Versioned renderer selection during migration; empty preserves saved actors.
var body_model: String = ""
## New-body identity weights; zero is the approved original, separate from legacy bust_size.
var body_shapes: Dictionary = {}

static func valid_body_model(value:Variant)->String:
	return "female_base_v2" if value is String and value=="female_base_v2" else ""

static func valid_eye_color(value:Variant)->String:
	var text:=str(value)
	return "#"+Color.from_string(text,Color.WHITE).to_html(false) if text.begins_with("#") and text.length()==7 and Color.html_is_valid(text) else ""

static func valid_bust_size(value:Variant)->float:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return 0.5
	var number:=float(value)
	return clampf(number,0.0,1.0) if is_finite(number) else 0.5

## 分层部件 id（MV Generator）：{ 类别: 变体号(int) }。
var part_ids: Dictionary = {}
## 预留给装备系统：{ 类别: 变体号 }；值为 null 表示该部位不穿。
var equipment: Dictionary = {}
## 烘好的角色表路径（user:// 缓存），世界/选角按需读取。
var mv_sheet: String = ""


## 实际用于合成的部件表 = 身体外观 + 装备覆盖。
func effective_part_ids() -> Dictionary:
	return MV.apply_equipment(part_ids, equipment)


## 交给合成器的配色字典：{ "skin"/"hair"/"cloth": 色带下标 }。
## 关闭的分组不传，保留部件参考色。
func colors() -> Dictionary:
	var d := {}
	if skin_on and skin_row >= 0:
		d["skin"] = skin_row
	if hair_on and hair_row >= 0:
		d["hair"] = hair_row
	if cloth_on and cloth_row >= 0:
		d["cloth"] = cloth_row
	return d


func get_row(group: String) -> int:
	match group:
		"skin": return skin_row
		"hair": return hair_row
		"cloth": return cloth_row
	return -1


func set_row(group: String, row: int) -> void:
	match group:
		"skin":
			skin_row = row
			skin_on = true
		"hair":
			hair_row = row
			hair_on = true
		"cloth":
			cloth_row = row
			cloth_on = true


## 随机一套配色（从 MV 色板里取；皮肤只取肤色系色带）。
func randomize_colors() -> void:
	for g in GROUPS:
		var p := MV.palette_for(g)
		if not p.is_empty():
			set_row(g, int((p[randi() % p.size()] as Dictionary)["index"]))


func to_dict() -> Dictionary:
	return {
		"skin_row": skin_row,
		"hair_row": hair_row,
		"cloth_row": cloth_row,
		"skin_on": skin_on,
		"hair_on": hair_on,
		"cloth_on": cloth_on,
		"eye_color": valid_eye_color(eye_color),
		"bust_size": valid_bust_size(bust_size),
		"body_model": valid_body_model(body_model),
		"body_shapes": Shapes.normalize(body_shapes),
		"part_ids": part_ids,
		"equipment": equipment,
		"mv_sheet": mv_sheet,
	}


static func from_dict(d: Dictionary) -> Customization:
	var c := Customization.new()
	if d == null or d.is_empty():
		return c
	c.skin_row = int(d.get("skin_row", c.skin_row))
	c.hair_row = int(d.get("hair_row", c.hair_row))
	c.cloth_row = int(d.get("cloth_row", c.cloth_row))
	c.skin_on = bool(d.get("skin_on", true))
	c.hair_on = bool(d.get("hair_on", true))
	c.cloth_on = bool(d.get("cloth_on", false))
	c.eye_color = valid_eye_color(d.get("eye_color",""))
	c.bust_size = valid_bust_size(d.get("bust_size",0.5))
	c.body_model = valid_body_model(d.get("body_model",""))
	c.body_shapes = Shapes.normalize(d.get("body_shapes",{}))
	if typeof(d.get("part_ids")) == TYPE_DICTIONARY:
		c.part_ids = d["part_ids"]
	if typeof(d.get("equipment")) == TYPE_DICTIONARY:
		c.equipment = d["equipment"]
	c.mv_sheet = str(d.get("mv_sheet", ""))
	return c


## 造一个随机外观（NPC 批量生成用）。
static func random(gender: String, include_equipment: bool = false) -> Customization:
	var c := Customization.new()
	c.part_ids = MV.random_parts(gender, include_equipment)
	c.randomize_colors()
	return c
