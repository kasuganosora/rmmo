extends RefCounted
## Shop definitions for MockServer vendors.
## shops.json: { "shops": { shop_id: { "title": "...", "items": [{item_id, buy_price?}] } } }

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/shops.json",
	"res://data/combat/shops.json",
]

## shop_id -> { title, items: [{item_id, buy_price}] }
var _shops: Dictionary = {}
## Optional ItemCatalog for sell_price defaults / names.
var catalog = null


func set_catalog(p_catalog) -> void:
	catalog = p_catalog


func load_catalog() -> void:
	_shops.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var shops_v: Variant = (raw as Dictionary).get("shops", {})
	if typeof(shops_v) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	for sid_v in (shops_v as Dictionary).keys():
		var sid := str(sid_v).strip_edges()
		if sid.is_empty():
			continue
		var def_v: Variant = (shops_v as Dictionary)[sid_v]
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = def_v
		var items_out: Array = []
		var items_v: Variant = def.get("items", [])
		if typeof(items_v) == TYPE_ARRAY:
			for it in items_v:
				if typeof(it) != TYPE_DICTIONARY:
					continue
				var iid := str(it.get("item_id", "")).strip_edges()
				if iid.is_empty():
					continue
				var entry := {"item_id": iid}
				if it.has("buy_price"):
					entry["buy_price"] = maxi(int(it.get("buy_price", 0)), 0)
				items_out.append(entry)
		_shops[sid] = {
			"title": str(def.get("title", sid)),
			"items": items_out,
		}
	if _shops.is_empty():
		_load_builtin_fallback()


func has_shop(shop_id: String) -> bool:
	return _shops.has(shop_id.strip_edges())


func get_shop(shop_id: String) -> Dictionary:
	shop_id = shop_id.strip_edges()
	if not _shops.has(shop_id):
		return {}
	return (_shops[shop_id] as Dictionary).duplicate(true)


func buy_price_for(shop_id: String, item_id: String) -> int:
	shop_id = shop_id.strip_edges()
	item_id = item_id.strip_edges()
	if shop_id.is_empty() or item_id.is_empty() or not _shops.has(shop_id):
		return -1
	var def: Dictionary = _shops[shop_id]
	for it in def.get("items", []):
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("item_id", "")) != item_id:
			continue
		if it.has("buy_price"):
			return maxi(int(it.get("buy_price", 0)), 0)
		return _default_buy_price(item_id)
	return -1


func sells_item(shop_id: String, item_id: String) -> bool:
	return buy_price_for(shop_id, item_id) >= 0


## Listings for open_shop action: [{item_id, name, buy_price, sell_price}, ...]
func build_listings(shop_id: String) -> Array:
	shop_id = shop_id.strip_edges()
	var out: Array = []
	if not _shops.has(shop_id):
		return out
	var def: Dictionary = _shops[shop_id]
	for it in def.get("items", []):
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid := str(it.get("item_id", "")).strip_edges()
		if iid.is_empty():
			continue
		var buy: int = int(it.get("buy_price", -1))
		if buy < 0:
			buy = _default_buy_price(iid)
		var sell: int = _sell_price(iid)
		out.append({
			"item_id": iid,
			"name": _item_name(iid),
			"buy_price": buy,
			"sell_price": sell,
		})
	return out


func shop_title(shop_id: String) -> String:
	shop_id = shop_id.strip_edges()
	if not _shops.has(shop_id):
		return shop_id
	return str((_shops[shop_id] as Dictionary).get("title", shop_id))


func _default_buy_price(item_id: String) -> int:
	var sell: int = _sell_price(item_id)
	if sell > 0:
		return sell * 2
	return 10


func _sell_price(item_id: String) -> int:
	if catalog != null and catalog.has_method("get_item"):
		var def: Dictionary = catalog.get_item(item_id)
		if not def.is_empty():
			return maxi(int(def.get("sell_price", 0)), 0)
	return 0


func _item_name(item_id: String) -> String:
	if catalog != null and catalog.has_method("get_item"):
		var def: Dictionary = catalog.get_item(item_id)
		if not def.is_empty():
			return str(def.get("name", item_id))
	return item_id


func _load_builtin_fallback() -> void:
	_shops = {
		"starter_goods": {
			"title": "杂货商人",
			"items": [
				{"item_id": "potion_hp_small", "buy_price": 10},
				{"item_id": "potion_mp_small", "buy_price": 10},
				{"item_id": "leather_cap"},
				{"item_id": "wooden_sword"},
			],
		},
	}


static func _load_json_first(paths: Array) -> Variant:
	for p in paths:
		var path := str(p)
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return null
