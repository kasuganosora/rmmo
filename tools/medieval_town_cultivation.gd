extends RefCounted
const GRASS="pack:default:terrain/mossy_grass_vcjmej0s/material"
const DIRECTIONS={"northwest_field":-10.,"north_field":-12.,"west_field":20.,"north_river_field":-15.,"northeast_field":8.,"far_northeast_field":-20.,"east_field":15.,"southeast_field":0.,"southwest_field":-12.,"southwest_outer_field":25.,"south_field":-10.,"southeast_outer_field":8.}
static func area(polygon: PackedVector2Array) -> float:
	var result:=0.
	for i in polygon.size(): result+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(result*.5)
static func field_regions(doc) -> Array:
	var roads: Array=[]
	for record in doc.records:
		if not record.has("road_mesh"): continue
		for shape in preload("res://scripts/world_editor/building_footprint.gd").record_shapes(record):
			for inflated in Geometry2D.offset_polygon(shape.polygon,1.): roads.append(inflated)
	var out: Array=[]
	for args in preload("res://tools/medieval_town_ground_materials.gd").region_requests(doc):
		if not DIRECTIONS.has(args.id): continue
		var polygon:=PackedVector2Array()
		for p in args.polygon: polygon.append(Vector2(p[0],p[1]))
		for road in roads:
			if not preload("res://scripts/world3d/terrain_regions.gd").bounds(polygon).intersects(preload("res://scripts/world3d/terrain_regions.gd").bounds(road)): continue
			var pieces:=Geometry2D.clip_polygons(polygon,road)
			if pieces.is_empty(): continue
			if pieces.any(func(p):return Geometry2D.is_polygon_clockwise(p)!=Geometry2D.is_polygon_clockwise(pieces[0])):
				# A road wholly inside the field produces a polygon with a hole.
				# Open it into two parcels at the road, then retain the largest
				# cultivable side; discarded slivers stay uncultivated.
				var cut_y: float=preload("res://scripts/world3d/terrain_regions.gd").bounds(road).get_center().y
				var split: Array[PackedVector2Array]=[]
				for pair in [[-100000.,cut_y],[cut_y,100000.]]:
					var half:=PackedVector2Array([Vector2(-100000,pair[0]),Vector2(100000,pair[0]),Vector2(100000,pair[1]),Vector2(-100000,pair[1])])
					for part in Geometry2D.intersect_polygons(polygon,half): split.append_array(Geometry2D.clip_polygons(part,road))
				if not split.is_empty(): pieces=split
			# Keep the main arable parcel, leaving road-edge slivers uncultivated.
			pieces.sort_custom(func(a,b):return area(a)>area(b)); polygon=pieces[0]
		# Boolean clipping introduces almost coincident boundary points at road
		# chunk seams. Remove sub-decimetre edges before authoring the polygon.
		var changed:=true
		while changed and polygon.size()>3:
			changed=false
			for i in polygon.size():
				var a: Vector2=polygon[(i+polygon.size()-1)%polygon.size()]; var b: Vector2=polygon[i]; var c: Vector2=polygon[(i+1)%polygon.size()]
				if a.distance_to(b)<.2 or b.distance_to(Geometry2D.get_closest_point_to_segment(b,a,c))<.08:
					polygon.remove_at(i); changed=true; break
		args.polygon=[]
		for p in polygon: args.polygon.append([p.x,p.y])
		for record in doc.records:
			if record.get("terrain_regions",{}).get("regions",[]).any(func(p):return p.id==args.id):
				out.append(args.merged({"terrain_ids":[record.uuid]},true))
	return out
static func requests(records: Array) -> Array:
	var out: Array=[]
	for id in DIRECTIONS:
		var ids: Array=[]
		for r in records:
			if r.get("terrain_regions",{}).get("regions",[]).any(func(p):return p.id==id): ids.append(r.uuid)
		if not ids.is_empty(): out.append({"id":id,"terrain_ids":ids,"spacing":3.2 if id=="northwest_field" else 2.2,"height":.18,"angle":DIRECTIONS[id],"margin":3.,"setback":7.})
	return out
