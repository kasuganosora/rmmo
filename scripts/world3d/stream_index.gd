extends RefCounted
## Worker-owned immutable spatial data. No SceneTree or renderer calls.
const Landscape=preload("res://scripts/world3d/stream_landscape.gd")
static func build(library:Array)->Dictionary:
	var result:Dictionary={}
	var index:Dictionary={};var by_id:Dictionary={};var known:Dictionary={};var lamp_roots:Dictionary={}
	for spec:Dictionary in library:
		by_id[spec.uuid]=spec;known[spec.uuid]=true
		# Previously saved flat glTF already tags the crystal but not its sibling parts.
		# Recover that explicit fixture's asset namespace without rewriting user maps.
		if spec.get("extras",{}).get("rmmo_streetlamp_crystal",false) and str(spec.uuid).contains("__"):
			lamp_roots[str(spec.uuid).get_slice("__",0)]=true
		for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
			for x in range(spec.chunk_min.x,spec.chunk_max.x+1):
				var key:=Vector2i(x,z)
				if not index.has(key):index[key]=[]
				index[key].append(spec.uuid)
	result.stream_index=index;result.stream_by_id=by_id;result.stream_known=known
	var groups:Dictionary={}
	var props:Dictionary={};var collisions:Dictionary={}
	for spec:Dictionary in library:
		var id:String=spec.get("ground_batch_record",{}).get("building",{}).get("id","")
		# Keep each whole streetlamp with its supporting landscape at town view distance.
		# Physics still uses the original near-field bounds and collision index.
		var lamp_id:String=spec.get("extras",{}).get("rmmo_streetlamp_instance","")
		var asset_id:=str(spec.uuid).get_slice("__",0)
		if lamp_id.is_empty() and lamp_roots.has(asset_id):lamp_id=asset_id
		if id.is_empty() and not lamp_id.is_empty():id="streetlamp:"+lamp_id
		var solid:bool=spec.get("extras",{}).get("rmmo_collision","")!="none"
		if id.is_empty() or solid:
			for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
				for x in range(spec.chunk_min.x,spec.chunk_max.x+1):
					var key:=Vector2i(x,z)
					if id.is_empty() and not Landscape.landscape(spec):
						if not props.has(key):props[key]=[]
						props[key].append(spec)
					if solid:
						if not collisions.has(key):collisions[key]=[]
						collisions[key].append(spec)
		if id.is_empty():continue
		if not groups.has(id):groups[id]=[]
		groups[id].append(spec)
	for id:String in groups:
		var low:=Vector2i(2147483647,2147483647);var high:=-low
		for spec:Dictionary in groups[id]:low=low.min(spec.chunk_min);high=high.max(spec.chunk_max)
		for spec:Dictionary in groups[id]:
			spec.render_building=id;spec.render_bounds={"chunk":low,"chunk_min":low,"chunk_max":high}
	result.stream_landscape=Landscape.bind(library,groups)
	result.stream_building_groups=groups
	result.stream_prop_index=props;result.stream_collision_index=collisions
	result.stream_building_count=library.size()
	return result
