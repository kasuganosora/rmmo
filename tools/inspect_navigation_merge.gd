extends SceneTree
## Read-only diagnostic of an existing mesh, without rebaking or editing a map.
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--cache="):path=arg.trim_prefix("--cache=")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:quit(1);return
	var digest:=file.get_buffer(32);var bytes:=file.get_buffer(file.get_length()-32)
	if preload("res://scripts/world3d/map_metadata_cache.gd").checksum(bytes)!=digest:quit(1);return
	var data:Dictionary=bytes_to_var(bytes);var mesh:=NavigationMesh.new();mesh.cell_size=.1;mesh.cell_height=.1
	mesh.set_vertices(data.vertices)
	var flat_zero:=0
	for polygon:PackedInt32Array in data.polygons:
		var area:=0.0;var origin:Vector3=data.vertices[polygon[0]]
		for i in polygon.size():
			var a:Vector3=data.vertices[polygon[i]]-origin;var b:Vector3=data.vertices[polygon[(i+1)%polygon.size()]]-origin
			area+=a.x*b.z-b.x*a.z
		if absf(area)<.00001:flat_zero+=1
		if "--filter-zero-area" in OS.get_cmdline_user_args() and absf(area)<.00001:continue
		mesh.add_polygon(polygon)
	print("ZERO_PROJECTED_AREA ",flat_zero)
	var edge_counts:Dictionary={};var zero_edges:=0;var short_polygons:=0;var duplicates:=0;var seen:Dictionary={};var repeated_vertices:=0;var examples:Array=[]
	for polygon:PackedInt32Array in data.polygons:
		var distinct:Array=[]
		for index in polygon:
			var p:Vector3=data.vertices[index]
			if not distinct.has(p):distinct.append(p)
		if distinct.size()<3:short_polygons+=1
		if distinct.size()<polygon.size():
			repeated_vertices+=1
			if examples.size()<3:examples.append(Array(polygon).map(func(index):return str(data.vertices[index])))
		var canonical:Array=distinct.map(func(p):return str(p));canonical.sort();var signature:=str(canonical)
		if seen.has(signature):duplicates+=1
		seen[signature]=true
		for i in polygon.size():
			var a:Vector3=data.vertices[polygon[i]];var b:Vector3=data.vertices[polygon[(i+1)%polygon.size()]]
			if a==b:zero_edges+=1;continue
			var edge:Array=[str(a),str(b)];edge.sort();var key:=str(edge)
			edge_counts[key]=edge_counts.get(key,0)+1
	var overlaps:Array=[]
	for edge in edge_counts:
		if edge_counts[edge]>2:overlaps.append({"edge":edge,"count":edge_counts[edge]})
	print("TOPOLOGY ",JSON.stringify({"zero_edges":zero_edges,"short_polygons":short_polygons,"duplicate_polygons":duplicates,"repeated_vertices":repeated_vertices,"repeated_examples":examples,"overlapping_edges":overlaps.size(),"examples":overlaps.slice(0,3)}))
	if "--topology-only" in OS.get_cmdline_user_args():quit();return
	for scale in [1.0,.1,.01]:
		print("MERGE_SCALE_BEGIN ",scale)
		var map:=NavigationServer3D.map_create();NavigationServer3D.map_set_use_async_iterations(map,false)
		NavigationServer3D.map_set_cell_size(map,.1);NavigationServer3D.map_set_cell_height(map,.1)
		NavigationServer3D.map_set_merge_rasterizer_cell_scale(map,scale);NavigationServer3D.map_set_active(map,true)
		var region:=NavigationServer3D.region_create();NavigationServer3D.region_set_use_async_iterations(region,false)
		NavigationServer3D.region_set_map(region,map);NavigationServer3D.region_set_navigation_mesh(region,mesh)
		for i in 3:await physics_frame
		NavigationServer3D.map_force_update(map)
		var route:=NavigationServer3D.map_get_path(map,Vector3(-300,0,-47),Vector3(-200,0,-20),true)
		print("MERGE_SCALE_END ",scale," polygons=",mesh.get_polygon_count()," route_points=",route.size())
		NavigationServer3D.free_rid(region);NavigationServer3D.free_rid(map)
	quit()
