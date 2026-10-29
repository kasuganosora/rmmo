extends RefCounted
## Automatic selection never turns unresolved ownership into an outdoor permit.
## Unsupported catalogues keep the complete legacy wait; forced tests still deny.
static func select(adapter:RefCounted,map_root:Node,map_ref:String,revision:String)->Dictionary:
	var result:Dictionary=adapter.register_root(map_ref,revision,map_root)
	if not result.ok:return {"mode":"full","reason":str(result.reason)}
	var catalogue:Dictionary=adapter._maps[map_ref]
	if not catalogue.unknown.is_empty():return {"mode":"full","reason":"unresolved_volumes"}
	for building:Dictionary in catalogue.buildings.values():
		if not building.semantic_ready:return {"mode":"full","reason":"incomplete_building_semantics"}
	return {"mode":"staged","reason":"verified_complete_catalogue"}
