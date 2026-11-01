extends RefCounted
## Subscribe before covered entry starts publishing. Late setup otherwise
## rescans the accumulated library instead of using each live prepared packet.
static func ensure(host:Node,map_root:Node)->bool:
	var deferred:=map_root.get_node_or_null("DeferredAssets")
	if deferred==null or deferred._reference_index.is_empty():return false
	if map_root.get_node_or_null("AssetResidency")!=null:return true
	var prepared:RefCounted=map_root.get_meta("initial_residency_preparation") if map_root.has_meta("initial_residency_preparation") else null
	if prepared!=null:
		map_root.remove_meta("initial_residency_preparation")
		var accepted:bool=prepared.claim(map_root,deferred)
		var append_state:Dictionary=map_root.get_meta("stream_append_state",{})
		if append_state.get("initial_residency_token")==prepared.token:append_state.erase("initial_residency_token")
		if not accepted:prepared=null
	var adoption_complete:bool=int(map_root.get_meta("stream_children",-1))==map_root.get_child_count(true)
	var ordinary:=preload("res://scripts/world3d/asset_residency.gd").new()
	ordinary.configure(host,map_root,deferred,prepared);map_root.add_child(ordinary)
	# Ordinary ownership must exist before native building ownership takes over.
	var native:=preload("res://scripts/world3d/native_residency.gd").new()
	native.configure(host,map_root,deferred,prepared);map_root.add_child(native)
	if adoption_complete:map_root.set_meta("stream_children",map_root.get_child_count(true))
	return true
