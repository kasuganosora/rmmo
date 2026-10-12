extends "res://tools/probe_navigation_contours_20261012.gd"
func run()->void:
	create_timer(500).timeout.connect(func():print("NAV_TILES_TIMEOUT");quit(2))
	var doc=Doc.open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	var terrain:Array=[]
	for r:Dictionary in doc.records:
		if r.has("terrain_mesh"):terrain.append({"uuid":r.uuid,"pose":Terrain.transform(r),"bounds":Terrain.transform(r)*Terrain.bounds(r),"record":r})
	var failures:=0
	for tile:Vector2i in [Vector2i(0,2),Vector2i(4,0),Vector2i(0,-3),Vector2i(-5,-4),Vector2i(1,2),Vector2i(1,4),Vector2i(-4,-4),Vector2i(5,1),Vector2i(5,0)]:
		var clip:=AABB(Vector3(tile.x*128.-1.6,-20,tile.y*128.-1.6),Vector3(131.2,60,131.2))
		var source:=NavigationMeshSourceGeometryData3D.new()
		for t:Dictionary in terrain:
			if not t.bounds.intersects(clip):continue
			if not t.has("faces"):t.faces=Cpu.capture(Terrain.mesh(t.record,null)).collision_faces()
			source.add_faces(t.faces,t.pose)
		var mesh:=NavigationMesh.new();mesh.cell_size=.1;mesh.cell_height=.1;mesh.edge_max_error=1.;mesh.detail_sample_max_error=preload("res://scripts/world3d/world_navigation.gd").DETAIL_HEIGHT_ERROR/mesh.cell_height
		mesh.agent_radius=.5;mesh.agent_height=2.1;mesh.agent_max_climb=.4;mesh.agent_max_slope=40.;mesh.filter_walkable_low_height_spans=true
		mesh.filter_baking_aabb=clip;mesh.border_size=1.6
		NavigationServer3D.bake_from_source_geometry_data_async(mesh,source)
		while NavigationServer3D.is_baking_navigation_mesh(mesh):await process_frame
		var result:=topology(mesh)
		var map:=NavigationServer3D.map_create();NavigationServer3D.map_set_use_async_iterations(map,false);NavigationServer3D.map_set_cell_size(map,.01);NavigationServer3D.map_set_cell_height(map,.01);NavigationServer3D.map_set_active(map,true)
		var region:=NavigationServer3D.region_create();NavigationServer3D.region_set_use_async_iterations(region,false);NavigationServer3D.region_set_map(region,map);NavigationServer3D.region_set_navigation_mesh(region,mesh)
		await physics_frame;NavigationServer3D.map_force_update(map)
		var a:=NavigationServer3D.map_get_closest_point(map,clip.get_center()+Vector3(-30,-10,-30));var b:=NavigationServer3D.map_get_closest_point(map,clip.get_center()+Vector3(30,-10,30))
		var path:=NavigationServer3D.map_get_path(map,a,b,true);result.route_points=path.size()
		if path.size()<2:failures+=1
		NavigationServer3D.free_rid(region);NavigationServer3D.free_rid(map)
		print("NAV_TERRAIN_TILE ",tile," ",JSON.stringify(result))
		if result.edge_conflicts>0 or result.zero_area>0:failures+=1
	var Nav=preload("res://scripts/world3d/world_navigation.gd")
	var vertices:=PackedVector3Array([Vector3.ZERO,Vector3(1,0,0),Vector3(2,0,0),Vector3(1,0,.01)])
	if Nav.projected_polygon_valid(PackedInt32Array([0,0,1]),vertices) or Nav.projected_polygon_valid(PackedInt32Array([0,1,2]),vertices) or not Nav.projected_polygon_valid(PackedInt32Array([0,1,3]),vertices):failures+=1
	print("NAV_TERRAIN_TILES failures=",failures);quit(failures)
