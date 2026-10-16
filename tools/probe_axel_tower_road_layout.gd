extends SceneTree
## Read-only native XZ layout screening. No scene, HTTP mutation or map save.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const City=preload("res://scripts/world3d/city_layout.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Roads=preload("res://scripts/world3d/road_plan.gd")
const Ports=preload("res://scripts/world3d/road_bridges.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Geo=preload("res://scripts/world_editor/selection_geometry.gd")
func _init()->void:call_deferred("run")
func flatten(shape:Dictionary)->Dictionary:
	var value:Dictionary=shape.duplicate();value.bounds.position.y=0.;value.bounds.size.y=100.;return value
func road_geometry(data:Dictionary)->Dictionary:
	var portals:=Ports.resolve(data)
	if not portals.ok:return portals
	return Roads.build(data.roads,Roads.defaults().merged(data.road_surface.settings,true),portals.portals)
func audit(built:Dictionary,roads:Array,graph:Dictionary)->Array:
	var road_shapes:Array=[]
	for r:Dictionary in roads:
		for shape:Dictionary in Foot.record_shapes(r):road_shapes.append({"id":r.uuid,"shape":flatten(shape)})
	var analysis:=City.analyze(graph);var results:Array=[]
	for route:Dictionary in built.access_routes:
		var prefix:="access_tower_%d_"%route.tower;var shapes:Array=[];var ids:={}
		for r:Dictionary in built.records:
			var part:String=r.fortification.part
			if not part.begins_with(prefix) or r.has("fixture"):continue
			if not part.ends_with("internal_stair") and not part.contains("_ground_floor_") and not part.contains("hinge_mount"):continue
			for shape:Dictionary in Foot.record_shapes(r):shapes.append({"part":part,"shape":flatten(shape)})
		var conflicts:Array=[]
		for item:Dictionary in road_shapes:
			for part:Dictionary in shapes:
				if Foot.overlaps(part.shape,item.shape):
					var key:String=item.id+":"+part.part
					if not ids.has(key):conflicts.append({"road_source":item.id,"part":part.part});ids[key]=true
		var closest:Dictionary={"distance_m":INF};var entry:=Vector2(route.entry[0],route.entry[2])
		for edge:Dictionary in graph.edges:
			if edge.kind!="ground":continue
			var points:Array=analysis.paths[edge.id]
			for i in points.size()-1:
				var a:=Vector2(points[i].x,points[i].z);var b:=Vector2(points[i+1].x,points[i+1].z);var delta:=b-a
				var at:=a.lerp(b,clampf((entry-a).dot(delta)/delta.length_squared(),0.,1.));var distance:=entry.distance_to(at)
				if distance<closest.distance_m:closest={"edge":edge.id,"name":edge.get("name",""),"from":edge.from,"to":edge.to,"width_start":edge.width_start,"width_end":edge.width_end,"nearest_xz":[at.x,at.y],"distance_m":distance}
		var center:=Vector2(route.room[0],route.room[2]);var inside:Vector2=(entry-center).normalized();var outer:Vector2=center+inside*(route.radius+1.3)
		results.append({"tower":route.tower,"room_xz":[center.x,center.y],"radius":route.radius,"entry_xz":[outer.x,outer.y],"inside_direction_xz":[inside.x,inside.y],"door_center_xz":[center.x+inside.x*(route.radius-.25),center.y+inside.y*(route.radius-.25)],"native_step_outer_extent":"No external step/ramp: flat paved tower floor ends at radius, room floor +0.03m; internal spiral OBB remains protected","nearest_road":closest,"conflicts":conflicts})
	return results
func run()->void:
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/fortification_content_recipe.json"));var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/source_metadata.json"))
	var settings:Dictionary=F.defaults().merged(recipe.fortification_request,true);settings.layout_version=1
	var fort:=Plan.new().build(settings)
	if not fort.ok:print(fort);quit(1);return
	var data:Dictionary=City.resolve(meta);var original:=road_geometry(data)
	if not original.ok:print(original);quit(1);return
	var baseline:=audit(fort,original.records,data.roads)
	var updated:Dictionary=data.duplicate(true);var requested:Dictionary={"axel_n_feebec9fc86d":[64.5,230.],"axel_n_c436b3f1abfd":[94.,282.]};var moved:Array=[]
	for n:Dictionary in updated.roads.nodes:
		if not requested.has(n.id):continue
		var old:Array=n.position.duplicate();n.position[0]=requested[n.id][0];n.position[2]=requested[n.id][1]
		moved.append({"id":n.id,"old":old,"proposed_xz":requested[n.id],"height_policy":"Resample after root native terrain batches; do not retain old Y blindly"})
	var next:=road_geometry(updated)
	if not next.ok:print(next);quit(1);return
	var after:=audit(fort,next.records,updated.roads);var affected:Array=[]
	for e:Dictionary in data.roads.edges:
		if requested.has(e.from) or requested.has(e.to):affected.append(e)
	var report:={"scope":"All 12 native towers against all native final ground-road polygons: planar conservative placement screening only, no fitted Y/native save/GPU claim","source_metadata_sha256":FileAccess.get_sha256(OUT+"/source_metadata.json"),"recipe_sha256":FileAccess.get_sha256(OUT+"/fortification_content_recipe.json"),"tower_count":fort.access_routes.size(),"source_road_count":data.roads.edges.size(),"baseline":baseline,"proposed":after,"proposed_nodes":moved,"affected_edges":affected,"unchanged_edge_records":City.token(data.roads.edges)==City.token(updated.roads.edges),"original_conflict_towers":baseline.filter(func(r):return not r.conflicts.is_empty()).map(func(r):return r.tower),"proposed_conflict_towers":after.filter(func(r):return not r.conflicts.is_empty()).map(func(r):return r.tower)}
	FileAccess.open(OUT+"/tower_road_layout_probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TOWER_ROAD_LAYOUT ",JSON.stringify({"count":report.tower_count,"before":report.original_conflict_towers,"after":report.proposed_conflict_towers,"moves":moved,"edges":affected}))
	for tower:Dictionary in after:print("TOWER ",JSON.stringify(tower))
	quit(0)
