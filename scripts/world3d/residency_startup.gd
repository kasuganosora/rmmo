extends RefCounted
## Subscribe before covered entry starts publishing. Late setup otherwise
## rescans the accumulated library instead of using each live prepared packet.
static func ensure(host:Node,map_root:Node)->bool:
	var deferred:=map_root.get_node_or_null("DeferredAssets")
	if deferred==null or deferred._reference_index.is_empty():return false
	if map_root.get_node_or_null("AssetResidency")!=null:return true
	var adoption_complete:bool=int(map_root.get_meta("stream_children",-1))==map_root.get_child_count(true)
	var ordinary:=preload("res://scripts/world3d/asset_residency.gd").new()
	ordinary.configure(host,map_root,deferred);map_root.add_child(ordinary)
	# Ordinary ownership must exist before native building ownership takes over.
	var native:=preload("res://scripts/world3d/native_residency.gd").new()
	native.configure(host,map_root,deferred);map_root.add_child(native)
	if adoption_complete:map_root.set_meta("stream_children",map_root.get_child_count(true))
	return true
