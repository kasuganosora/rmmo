extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Ports=preload("res://scripts/world3d/road_bridges.gd")
const Adaptive=preload("res://scripts/world3d/road_terrain_fit.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const PATH="D:/code/rmmo_runtime/cache/world3d/axel_town_roads_20261014/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/bridge_road_conflicts.json"
func clip3(poly:Array,normal:Vector3,constant:float)->Array:
	var out:Array=[]
	for i in poly.size():
		var a:Vector3=poly[i];var b:Vector3=poly[(i+1)%poly.size()];var da:=normal.dot(a)+constant;var db:=normal.dot(b)+constant
		if da>=0:out.append(a)
		if (da>=0)!=(db>=0):out.append(a.lerp(b,da/(da-db)))
	return out
func actual_contacts(bridge:Dictionary,roads:Array)->Dictionary:
	var data:=preload("res://scripts/world3d/house_prefab.gd").decode(bridge.house_prefab)
	if data.is_empty():return {"error":"frozen collision unavailable"}
	var source:Dictionary=data.meshes[data.entries[0][1][1]]
	var pose:=Transform3D(Basis.from_euler(City.vec(bridge.rotation)*PI/180.).scaled(City.vec(bridge.size)),City.vec(bridge.position))
	var patches:Array=[]
	for road:Dictionary in roads:
		for raw in Surface.local_polygons(road):
			var top:Array=Array(raw).map(func(p):return p+City.vec(road.position));var planes:Array=[];var bounds:=AABB(top[0],Vector3.ZERO)
			for i in top.size():
				var p:Vector3=top[i];var q:Vector3=top[(i+1)%top.size()];var n:=Vector3(-(q.z-p.z),0,q.x-p.x).normalized()
				planes.append([n,-n.dot(p)-.005]);bounds=bounds.expand(p-Vector3.UP*road.size[1]).expand(p+Vector3.UP*road.road_clearance)
			var plane:=Plane(top[0],top[1],top[2]);var n:Vector3=plane.normal;var d:float=plane.d
			if n.y<0:n=-n;d=-d
			planes.append([n,-d+(road.size[1]-.005)*n.y]);planes.append([-n,d+(road.road_clearance-.005)*n.y])
			patches.append({"planes":planes,"bounds":bounds,"road":road.road_source})
	var hits:Array=[];var triangles:=0
	for slot in source.surfaces.size():
		var surface:Array=source.surfaces[slot];var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX] if surface[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():indices.append(i)
		for i in range(0,indices.size(),3):
			triangles+=1
			var triangle:Array=[pose*vertices[indices[i]],pose*vertices[indices[i+1]],pose*vertices[indices[i+2]]]
			var bounds:=AABB(triangle[0],Vector3.ZERO).expand(triangle[1]).expand(triangle[2]).grow(.0001)
			for patch:Dictionary in patches:
				if not bounds.intersects(patch.bounds):continue
				var cut:Array=triangle
				for plane:Array in patch.planes:
					cut=clip3(cut,plane[0],plane[1])
					if cut.size()<3:break
				if cut.size()<3:continue
				var area:=0.
				for j in range(1,cut.size()-1):area+=(cut[j]-cut[0]).cross(cut[j+1]-cut[0]).length()*.5
				if area<.0000001:continue
				hits.append({"road":patch.road,"surface":slot,"triangle":triangle.map(City.xyz),"clipped":cut.map(City.xyz),"area":area})
				if hits.size()>=8:return {"tested_triangles":triangles,"contacts":hits,"truncated":true}
	return {"tested_triangles":triangles,"contacts":hits,"truncated":false}
func _initialize():call_deferred("run")
func run():
	var doc=Doc.open_file(PATH)
	if doc==null:push_error("native candidate unreadable");quit(1);return
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/recipe.json"))
	var data:=City.resolve(doc.map_meta);var settings:=Plan.defaults().merged(recipe.road_surface_settings,true)
	var plane_only:bool="--bridge2-plan" in OS.get_cmdline_user_args()
	if plane_only:
		settings.kerb_enabled=false # XZ-only diagnostic; production settings stay untouched.
		var graph:Dictionary=recipe.graph.duplicate(true)
		for edge:Dictionary in graph.edges:
			for old:Dictionary in data.roads.edges:
				if edge.id==old.id and old.has("stone_bridge"):edge.stone_bridge=old.stone_bridge.duplicate(true)
		data.roads=graph
	var portals:=Ports.resolve(data)
	if not portals.ok:print(portals);quit(1);return
	var plan:=Plan.build(data.roads,settings,portals.portals)
	if not plan.ok:print(plan);quit(1);return
	var fitted:Dictionary
	if plane_only:
		for road:Dictionary in plan.records:road.position[1]+=doc._find("axel_bridge_2").position[1]
		fitted={"ok":true,"records":plan.records,"chunks":plan.chunks}
	else:fitted=Adaptive.fit(plan.records,doc.records.filter(func(r):return r.has("terrain_mesh")),settings.lift,128)
	if not fitted.ok:
		var failure:=FileAccess.open(OUT.get_base_dir().path_join("road_projection_failure.json"),FileAccess.WRITE)
		failure.store_string(JSON.stringify(fitted,"\t"));failure.close()
		print(fitted);quit(1);return
	var report:Dictionary={"path":PATH,"map_sha256":FileAccess.get_sha256(PATH),"road_chunks":fitted.chunks,"bridges":[],"scope":"new graph XZ clearance at bridge-head height only; terrain fit not reviewed" if plane_only else "actual saved candidate terrain and bridges"}
	for bridge:Dictionary in doc.records.filter(func(r):return r.has("bridge_mesh")):
		if plane_only and bridge.uuid!="axel_bridge_2":continue
		var shape:=Foot.record_shape(bridge);var pose:=Transform3D(Basis.from_euler(City.vec(bridge.rotation)*PI/180.).scaled(City.vec(bridge.size)),City.vec(bridge.position))
		var info:Dictionary={"id":bridge.uuid,"recipe":bridge.bridge_mesh,"position":bridge.position,"bounds_position":bridge.bounds_position,"bounds_size":bridge.bounds_size,"road_conflicts":[]}
		for road:Dictionary in fitted.records:
			var road_shapes:=Foot.record_shapes(road)
			if not Foot.batches_overlap(road_shapes,[shape]):continue
			var hits:Array=[];var polygons:=Surface.local_polygons(road)
			for index in road_shapes.size():
				if not Foot.overlaps(road_shapes[index],shape):continue
				var world:Array=Array(polygons[index]).map(func(p):return p+City.vec(road.position))
				var local:Array=world.map(func(p):return City.xyz(pose.affine_inverse()*p))
				var clipped:=Plan.intersection(world.map(func(p):return Vector2(p.x,p.z)),Array(shape.polygon).slice(0,-1))
				hits.append({"index":index,"world_top":world.map(City.xyz),"bridge_local_top":local,"overlap_area":Poly.area(clipped)})
			info.road_conflicts.append({"source":road.road_source,"position":road.position,"size":road.size,"patches":hits})
		var ids:Array=info.road_conflicts.map(func(r):return r.source)
		info.actual_collision=actual_contacts(bridge,fitted.records.filter(func(r):return r.road_source in ids))
		var cache:Dictionary={}
		info.editor_narrow_conflicts=fitted.records.filter(func(r):return r.road_source in ids and preload("res://scripts/world3d/road_bridge_approach.gd").intersects(r,bridge,Foot.record_shapes(r),shape,cache)).map(func(r):return r.road_source)
		report.bridges.append(info);print("BRIDGE_CONFLICT ",bridge.uuid," chunks=",info.road_conflicts.size()," actual=",JSON.stringify(info.actual_collision))
	var out:String=OUT.replace(".json","_bridge2_new_plan.json") if plane_only else OUT
	var output:=FileAccess.open(out,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	print("BRIDGE_CONFLICT_REPORT ",out);quit()
