extends RefCounted
## Exact StreamIndex/Neighborhood ownership schema, not a recursive Resource
## scanner. Snapshot shallow owner layers; never mutate live or borrowed data.
const Neighborhood=preload("res://scripts/world3d/collision_neighborhood_index.gd")
static func owners(map_root:Node)->Array:
	if not map_root.has_meta("stream_prop_index") and not map_root.has_meta("stream_collision_index") and not map_root.has_meta("stream_collision_neighborhood"):return []
	# The existing private queue pops from the end. Release outer indexes first,
	# then buckets, then candidates, and finally independent source specs. A
	# large bucket must not be the last owner of all of its resources at once.
	var by_id:Dictionary=map_root.get_meta("stream_by_id",{})
	if by_id.is_empty():return []
	var values:Array=by_id.values()
	var buckets:Array=[];var roots:Array=[by_id]
	for field:StringName in [&"stream_library",&"stream_landscape"]:
		if map_root.has_meta(field):roots.append(map_root.get_meta(field))
	for field:StringName in [&"stream_prop_index",&"stream_collision_index",&"stream_building_groups"]:
		if not map_root.has_meta(field):continue
		var index:Dictionary=map_root.get_meta(field)
		buckets.append_array(index.values());roots.append(index)
	var nearby:Variant=map_root.get_meta("stream_collision_neighborhood") if map_root.has_meta("stream_collision_neighborhood") else null
	if nearby is Neighborhood:
		values.append_array(nearby.members.values())
		for cells:Dictionary in nearby.levels.values():buckets.append_array(cells.values())
		buckets.append_array(nearby.ranges.values());roots.append(nearby)
	# Mutable/public sources can use the coarse query fallback even when the
	# narrow neighborhood exists. Its candidates have separate ownership.
	var cache:Dictionary=map_root.get_meta("stream_collision_candidate_cache",{})
	for row:Dictionary in cache.get("ranges",{}).values():
		values.append_array(row.items);buckets.append(row.items)
	roots.append(cache)
	values.append_array(buckets);values.append_array(roots)
	return values
