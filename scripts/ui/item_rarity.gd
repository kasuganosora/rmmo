extends RefCounted
## Item rarity → Chinese tooltip prefix 「[优秀] 名称」.
## Keys: common|uncommon|rare|epic → 普通/优秀/精良/史诗.

const VALID: Array[String] = ["common", "uncommon", "rare", "epic"]

const LABEL_CN: Dictionary = {
	"common": "普通",
	"uncommon": "优秀",
	"rare": "精良",
	"epic": "史诗",
}


## Normalize free-form rarity; unknown / empty → common.
static func normalize(rarity: Variant) -> String:
	var r := str(rarity).strip_edges().to_lower()
	if r in VALID:
		return r
	return "common"


static func label_cn(rarity: Variant) -> String:
	return str(LABEL_CN.get(normalize(rarity), "普通"))


## 「[优秀] 木剑」— empty name falls back to "?" .
static func format_name_line(item_name: String, rarity: Variant = "common") -> String:
	var nm := str(item_name).strip_edges()
	if nm.is_empty():
		nm = "?"
	return "[%s] %s" % [label_cn(rarity), nm]


static func rarity_of_def(def: Dictionary) -> String:
	if def.is_empty():
		return "common"
	return normalize(def.get("rarity", "common"))


static func format_def_name(def: Dictionary, fallback_name: String = "") -> String:
	var nm := fallback_name.strip_edges()
	if nm.is_empty():
		nm = str(def.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = str(def.get("id", "")).strip_edges()
	return format_name_line(nm, rarity_of_def(def))
