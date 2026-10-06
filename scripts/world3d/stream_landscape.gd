extends RefCounted
## Rendering dependencies only. Physics continues to use each source's bounds.
static func ground(spec:Dictionary)->bool:
	var r:Dictionary=spec.get("ground_batch_record",{})
	if r.has("building") or r.has("fortification") or r.has("bridge_mesh"):return false
	return r.has("terrain_mesh") or (r.get("kind")=="box" and r.get("surface_id")=="ground" and not r.has("road_mesh") and float(r.get("size",[1,3,1])[1])<=2)

static func landscape(spec:Dictionary)->bool:
	var r:Dictionary=spec.get("ground_batch_record",{})
	return ground(spec) or r.has("road_mesh") or r.has("channel_mesh") or r.has("bridge_mesh") or r.has("fortification")

static func bind(library:Array,groups:Dictionary)->Array:
	var land:Array=[];var supports:Array=[]
	for spec:Dictionary in library:
		if not landscape(spec):continue
		spec.render_bounds={"chunk":spec.chunk_min,"chunk_min":spec.chunk_min,"chunk_max":spec.chunk_max}
		spec.render_dependents=[];land.append(spec)
		if ground(spec):supports.append(spec)
	for members:Array in groups.values():
		var bounds:Dictionary=members[0].render_bounds.duplicate()
		var attached:Array=[]
		for tile:Dictionary in supports:
			if tile.chunk_min.x>bounds.chunk_max.x or tile.chunk_max.x<bounds.chunk_min.x or tile.chunk_min.y>bounds.chunk_max.y or tile.chunk_max.y<bounds.chunk_min.y:continue
			attached.append(tile)
		# Do not grow the query while gathering: that would flood-fill the map.
		for tile:Dictionary in attached:
			bounds.chunk_min=bounds.chunk_min.min(tile.chunk_min);bounds.chunk_max=bounds.chunk_max.max(tile.chunk_max)
		for member:Dictionary in members:member.render_bounds=bounds;member.render_supports=attached
		for tile:Dictionary in attached:tile.render_dependents.append(bounds)
	return land
