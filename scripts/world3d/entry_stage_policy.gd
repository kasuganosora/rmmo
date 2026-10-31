extends RefCounted
## Automatic selection never turns unresolved ownership into an outdoor permit.
## Unsupported catalogues keep the complete legacy wait; forced tests still deny.
static func select(adapter:RefCounted,map_root:Node,map_ref:String,revision:String)->Dictionary:
	# A known unannotated native asset already denies the staged policy.
	# Do not build/hash every building just to discard that catalogue. This
	# shortcut can only select FULL waiting; authorizing staged/forced entry
	# still uses the ordinary authority registration and readiness checks.
	if _has_unannotated_asset(map_root):return {"mode":"full","reason":"unresolved_volumes"}
	var result:Dictionary=adapter.register_root(map_ref,revision,map_root)
	if not result.ok:return {"mode":"full","reason":str(result.reason)}
	var catalogue:Dictionary=adapter._maps[map_ref]
	if not catalogue.unknown.is_empty():return {"mode":"full","reason":"unresolved_volumes"}
	for building:Dictionary in catalogue.buildings.values():
		if not building.semantic_ready:return {"mode":"full","reason":"incomplete_building_semantics"}
	return {"mode":"staged","reason":"verified_complete_catalogue"}

static func _has_unannotated_asset(map_root:Node)->bool:
	if not is_instance_valid(map_root):return false
	if map_root.get_meta("runtime_record_subset",false) and not map_root.has_meta("author_reference_extras"):return false
	var deferred:=map_root.get_node_or_null("DeferredAssets")
	if deferred==null:return false
	var index:Dictionary=deferred.get("_reference_index")
	if index.is_empty():return false
	var complete:Dictionary=map_root.get_meta("author_reference_extras",map_root.get_meta("extras",{}))
	var records:Variant=complete.get("rmmo_records")
	if not records is Array:return false
	var annotated:Dictionary={}
	# Read only the ownership header. Membership.header() deep-copies all
	# nested author data; none of it is needed for this negative decision.
	for raw:Dictionary in records:
		if raw.has("model_building") or raw.get("rmmo_state",{}).has("model_building"):annotated[raw.uuid]=true
	for row:Dictionary in index.get("rows",[]):
		if row.get("bounds_known",false) and not str(row.get("asset_path","")).is_empty() and not annotated.has(row.uuid):return true
	return false
