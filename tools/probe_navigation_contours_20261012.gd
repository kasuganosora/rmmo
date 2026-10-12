extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
func _initialize()->void:run.call_deferred()
func topology(mesh:NavigationMesh)->Dictionary:
	var vertices:=mesh.get_vertices();var counts:Dictionary={};var zero:=0
	for i in vertices.size():vertices[i]=vertices[i].snappedf(.01)
	for i in mesh.get_polygon_count():
		var p:=mesh.get_polygon(i);var area:=0.;var origin:=vertices[p[0]]
		for j in p.size():
			var a:=vertices[p[j]];var b:=vertices[p[(j+1)%p.size()]]
			area+=(a.x-origin.x)*(b.z-origin.z)-(b.x-origin.x)*(a.z-origin.z)
			var edge:Array=[a,b];edge.sort();counts[edge]=counts.get(edge,0)+1
		if absf(area)<.00001:zero+=1
	var conflicts:=0
	for key in counts:
		if counts[key]>2:conflicts+=1
	return {"polygons":mesh.get_polygon_count(),"zero_area":zero,"edge_conflicts":conflicts}
func run()->void:
	var doc=Doc.open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	var clip:=AABB(Vector3(510.4,-10,-1.6),Vector3(131.2,40,131.2))
	var source:=NavigationMeshSourceGeometryData3D.new();var count:=0
	for r:Dictionary in doc.records:
		if not r.has("terrain_mesh"):continue
		var pose:=Terrain.transform(r)
		if not (pose*Terrain.bounds(r)).intersects(clip):continue
		print("NAV_SOURCE ",r.uuid," ",pose*Terrain.bounds(r))
		var mesh:=Terrain.mesh(r,null);source.add_faces(Cpu.capture(mesh).collision_faces(),pose);count+=1
	print("NAV_CONTOUR sources=",count)
	for settings in [[8.,1.],[6.,1.5],[6.,2.]]:
		var mesh:=NavigationMesh.new();mesh.cell_size=.1;mesh.cell_height=.1;mesh.edge_max_error=1.
		mesh.detail_sample_distance=settings[0];mesh.detail_sample_max_error=settings[1]
		mesh.agent_radius=.5;mesh.agent_height=2.1;mesh.agent_max_climb=.4;mesh.agent_max_slope=40.;mesh.filter_walkable_low_height_spans=true
		mesh.filter_baking_aabb=clip;mesh.border_size=1.6
		NavigationServer3D.bake_from_source_geometry_data_async(mesh,source)
		while NavigationServer3D.is_baking_navigation_mesh(mesh):await process_frame
		print("NAV_CONTOUR detail=",settings," ",JSON.stringify(topology(mesh)))
	quit()
