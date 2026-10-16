extends "res://tools/apply_axel_functional_buildings.gd"
## Read-only authoring proposal. No editor, HTTP mutation, GPU, or map save.
## Re-run against final market SHA before supplying --grass-moves to the author.
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Fit=preload("res://scripts/world3d/road_terrain_fit.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const Contact=preload("res://scripts/world_editor/terrain_prop_contact.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const GRASS_PUBLICATION="D:/code/rmmo_runtime/review_artifacts/reference_grass_clumps/published.json"
const WIND_MARGIN=.10
class Context extends Node3D:
	var _doc:RefCounted
	var _mcp:Variant=null
var tiles:Array=[]
var objects:Array=[]
var water_shapes:Array=[]
var building_shapes:Array=[]
var affected:Array=[]
var proposed_roads:Array=[]
var eligible:Dictionary={}
var grade_changes:Array=[]
var initial_terrain:Array=[]
var scoped_regions:Array[Rect2]=[]
var previous_proposal:Dictionary={}
var reserved_previous:Dictionary={}
var proposed_building_records:Array=[]

func terrain_cache(records:Array)->void:
	tiles.clear()
	for r:Dictionary in records:
		if not r.has("terrain_mesh"):continue
		var pose:=Terrain.transform(r);var box:AABB=pose*Terrain.bounds(r)
		tiles.append({"record":r,"pose":pose,"inverse":pose.affine_inverse(),"rect":Rect2(box.position.x,box.position.z,box.size.x,box.size.z).grow(.00001)})
func ground(at:Vector2)->float:
	for tile:Dictionary in tiles:
		if not tile.rect.has_point(at):continue
		var local:Vector3=tile.inverse*Vector3(at.x,0,at.y);var height:=Terrain.sample(tile.record,local)
		if is_finite(height):return (tile.pose*Vector3(local.x,height,local.z)).y
	return NAN
func rect_of(shape:Dictionary)->Rect2:
	var b:AABB=shape.bounds;return Rect2(b.position.x,b.position.z,b.size.x,b.size.z)
func padded(record:Dictionary)->Dictionary:
	var shape:=Foot.record_shape(record);var expanded:=Geometry2D.offset_polygon(shape.polygon,WIND_MARGIN,Geometry2D.JOIN_ROUND)
	if not expanded.is_empty():shape.polygon=expanded[0];shape.bounds=shape.bounds.grow(WIND_MARGIN)
	return shape
func overlaps(a:Dictionary,b:Dictionary,flat:bool=false)->bool:
	if not rect_of(a).intersects(rect_of(b),true):return false
	if not flat and not a.bounds.intersects(b.bounds):return false
	return not Geometry2D.intersect_polygons(a.polygon,b.polygon).is_empty()
func load_grass()->void:
	var publication:=read(GRASS_PUBLICATION)
	for item:Dictionary in publication.get("entries",[]):
		if item.id not in ["arch_A","arch_C"]:continue
		var loaded:=Prefabs.read(item.entry)
		check(loaded.get("ok",false) and loaded.get("records",[]).size()==1,"actual approved A/C grass prefab "+item.id)
		if failed:return
		var record:Dictionary=loaded.records[0]
		pin(record.asset_path,item.library_model_sha256);eligible[record.asset_path]=item.id
	check(eligible.size()==2,"only two approved grass assets eligible; no arbitrary prop moves")
func prepare_ground()->void:
	var requests:=grading();report.grading=requests
	for request:Dictionary in requests:
		var batch:=Batch.prepare(editor._doc.records,editor._doc._find(request.id),request)
		check(batch.get("ok",false),"pure native terrain stamp geometry")
		if not batch.get("ok",false):report.blocking_findings.append(batch);return
		for entry:Dictionary in batch.entries:
			grade_changes.append({"before":editor._doc._find(entry.record.uuid).duplicate(true),"result":entry})
			for i in editor._doc.records.size():
				if editor._doc.records[i].uuid==entry.record.uuid:editor._doc.records[i]=entry.record;break
	terrain_cache(editor._doc.records)
func compose_graph(request:Dictionary)->Dictionary:
	var graph:Dictionary=City.resolve(editor._doc.map_meta).roads.duplicate(true);var nodes:={};var edges:={}
	for n:Dictionary in graph.nodes:nodes[n.id]=n
	for e:Dictionary in graph.edges:edges[e.id]=e
	for id:String in request.get("remove_nodes",[]):nodes.erase(id)
	for id:String in request.get("remove_edges",[]):edges.erase(id)
	for n:Dictionary in request.nodes:nodes[n.id]=n
	for e:Dictionary in request.edges:edges[e.id]=e
	graph.nodes=nodes.values();graph.edges=edges.values();return graph
func relevant(r:Dictionary)->bool:
	var box:AABB=Geometry.bounds([r]);var rect:=Rect2(box.position.x,box.position.z,box.size.x,box.size.z)
	return scoped_regions.any(func(area):return area.intersects(rect,true))
func road_shapes(record:Dictionary)->Array:
	var shapes:=Foot.record_shapes(record);var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),City.vec(record.position))
	for kerb:Dictionary in record.road_mesh.get("kerbs",[]):
		var points:Array[Vector3]=[]
		for p:Array in kerb.a+kerb.b:points.append(pose*City.vec(p))
		shapes.append(Foot.from_points(points))
	return shapes
func prepare_roads()->void:
	var request:=road_request();report.road_request=request
	if failed:return
	var layout:=City.resolve(editor._doc.map_meta);layout.roads=compose_graph(request)
	var settings:Dictionary=layout.road_surface.settings;var joined:=preload("res://scripts/world3d/road_intersections.gd").split(layout.roads)
	check(joined.get("ok",false),"native final road intersection geometry")
	if failed:report.blocking_findings.append(joined);return
	layout.roads=joined.graph
	var portals:=preload("res://scripts/world3d/road_bridges.gd").resolve(layout)
	check(portals.get("ok",false),"existing native bridge bindings resolve")
	if failed:report.blocking_findings.append(portals);return
	var planned:=Plan.build(layout.roads,settings,portals.portals)
	check(planned.get("ok",false),"native complete new graph Plan and continuous kerb geometry")
	if failed:report.blocking_findings.append(planned);return
	var selected:Array=planned.records.filter(relevant)
	var fitted:=Fit.fit(selected,editor._doc.records.filter(func(r):return r.has("terrain_mesh")),settings.lift,128)
	check(fitted.get("ok",false),"native local final pavement/kerb follows actual graded terrain")
	if failed:report.blocking_findings.append(fitted);return
	proposed_roads=fitted.records
	for r:Dictionary in editor._doc.records:
		if r.has("road_mesh") and not relevant(r):proposed_roads.append(r)
	for r:Dictionary in proposed_roads:
		for shape:Dictionary in road_shapes(r):objects.append({"id":r.get("uuid",r.road_source),"kind":"road","shape":shape})
	report.road_geometry={"final_graph_token":City.token(layout.roads),"settings":settings,"local_chunks":fitted.records.size(),"actual_kerb_profiles_included":true,"all_scene_native_guard":"pending actual authoring; this read-only probe uses native Plan/Fit geometry"}
func add_buildings()->void:
	for key:String in KEYS:
		var source:Dictionary=sources[key];var site:Dictionary=source.site
		var record:={"uuid":"proposed_"+key,"kind":"asset","asset_path":source.asset_path,"position":site.position,"rotation":site.rotation,"size":[1,1,1],"bounds_position":source.entry.bounds_position,"bounds_size":source.entry.bounds_size}
		var full:=complete_source_shape(key,record);scoped_regions.append(rect_of(full).grow(18))
		proposed_building_records.append(record)
		# Match the final writer's whole-model Foot occupancy, in addition to
		# source component/sweep envelopes. Never fit grass into model gaps.
		for shape:Dictionary in Foot.record_shapes(record):building_shapes.append({"id":record.uuid,"kind":"new_building","shape":shape})
		building_shapes.append({"id":record.uuid,"kind":"new_building","shape":full})
		for shape:Dictionary in part_shapes(key,record):building_shapes.append({"id":record.uuid,"kind":"new_building","shape":shape})
		report["hinge_sweeps_"+key]=hinge_envelopes(key,record)
func prepare_obstacles()->void:
	objects.append_array(building_shapes)
	for r:Dictionary in editor._doc.records:
		if r.has("terrain_mesh") or r.has("road_mesh"):continue
		var is_water:bool=r.get("surface_id","")=="water" and r.has("channel_mesh")
		for shape:Dictionary in Foot.record_shapes(r):
			var item:={"id":r.uuid,"kind":"grass" if eligible.has(r.get("asset_path","")) else "existing","shape":shape}
			if is_water:water_shapes.append(item)
			else:objects.append(item)
	for purpose:String in ["building","vegetation"]:
		for shape:Dictionary in Zones.obstacles(editor._doc.map_meta,purpose):objects.append({"id":shape.zone_id,"kind":"reserved_zone","shape":shape})
func collision(record:Dictionary,skip:Array=[],only_new:bool=false)->Array:
	var shape:=padded(record);var result:Array=[]
	for row:Dictionary in objects:
		if row.id==record.uuid or row.id in skip:continue
		if only_new and row.kind not in ["road","new_building"]:continue
		if overlaps(shape,row.shape):
			var hit:={"id":row.id,"kind":row.kind}
			if not result.has(hit):result.append(hit)
	for row:Dictionary in water_shapes:
		if overlaps(shape,row.shape,true):result.append({"id":row.id,"kind":"water"})
	return result
func changed_support(record:Dictionary)->bool:
	var shape:=Foot.record_shape(record)
	for change:Dictionary in grade_changes:
		if not rect_of(shape).intersects(Rect2(change.before.position[0]-change.before.size[0]/2,change.before.position[2]-change.before.size[2]/2,change.before.size[0],change.before.size[2]),true):continue
		if not Contact.preserves(change.before,change.result,record):return true
	return false
func base_gaps(record:Dictionary)->Dictionary:
	var faces:Array=Contact.lower_faces(record).filter(func(f):return f.base)
	if faces.size()!=1:return {"ok":false}
	var face:Dictionary=faces[0];var polygon:=PackedVector2Array(face.polygon);var rect:=Rect2(polygon[0],Vector2.ZERO)
	for p:Vector2 in polygon:rect=rect.expand(p)
	var lo:=INF;var hi:=-INF;var covered:=0.
	for tile:Dictionary in tiles:
		if not rect.intersects(tile.rect,true):continue
		var r:Dictionary=tile.record;var t:Dictionary=r.terrain_mesh
		var a:Vector3=tile.inverse*Vector3(rect.position.x,0,rect.position.y);var b:Vector3=tile.inverse*Vector3(rect.end.x,0,rect.end.y)
		var x0:=clampi(floori((minf(a.x,b.x)/r.size[0]+.5)*t.columns),0,t.columns-1);var x1:=clampi(floori((maxf(a.x,b.x)/r.size[0]+.5)*t.columns),0,t.columns-1)
		var z0:=clampi(floori((minf(a.z,b.z)/r.size[2]+.5)*t.rows),0,t.rows-1);var z1:=clampi(floori((maxf(a.z,b.z)/r.size[2]+.5)*t.rows),0,t.rows-1)
		for z in range(z0,z1+1):
			for x in range(x0,x1+1):
				if not Terrain.solid(t,x,z):continue
				var corners:Array=Terrain.cell(r,x,z).map(func(p):return tile.pose*p)
				for indices:Array in [[0,1,2],[0,2,3]]:
					var p:Vector3=corners[indices[0]];var n:Vector3=(corners[indices[1]]-p).cross(corners[indices[2]]-p);var tri:=PackedVector2Array()
					for i:int in indices:tri.append(Vector2(corners[i].x,corners[i].z))
					for patch:PackedVector2Array in Geometry2D.intersect_polygons(polygon,tri):
						covered+=absf(Poly.area(Array(patch)))
						for at:Vector2 in patch:
							var gap:=Contact.height(p,n,at)-Contact.height(face.point,face.normal,at);lo=minf(lo,gap);hi=maxf(hi,gap)
	var area:=absf(Poly.area(Array(polygon)))
	return {"ok":is_finite(lo) and absf(area-covered)<maxf(.001,area*.00001),"minimum_soil_minus_base_m":lo,"maximum_soil_minus_base_m":hi,"coverage":covered,"required_coverage":area}
func same_dry_bank(a:Vector2,b:Vector2)->bool:
	for row:Dictionary in water_shapes:
		for i in row.shape.polygon.size()-1:
			if Geometry2D.segment_intersects_segment(a,b,row.shape.polygon[i],row.shape.polygon[i+1])!=null:return false
	return true
func relocate(record:Dictionary,pending:Array)->Dictionary:
	if reserved_previous.has(record.uuid):return reserved_previous[record.uuid]
	var origin:=City.vec(record.position);var initial:Dictionary=before.records.filter(func(r):return r.uuid==record.uuid)[0]
	terrain_cache(before.records);var old_ground:=ground(Vector2(origin.x,origin.z));var old_gaps:=base_gaps(initial)
	terrain_cache(editor._doc.records)
	var candidates:Array=[]
	for x in range(-32,33):
		for z in range(-32,33):
			var delta:=Vector2(x*.25,z*.25)
			if delta.length_squared()>.0001 and delta.length()<=8:candidates.append(delta)
	candidates.sort_custom(func(a,b):return a.length_squared()<b.length_squared() if a.length_squared()!=b.length_squared() else a.x<b.x)
	var tested:=0
	for delta:Vector2 in candidates:
		var at:=Vector2(origin.x,origin.z)+delta;var h:=ground(at)
		if not is_finite(h) or not same_dry_bank(Vector2(origin.x,origin.z),at):continue
		var trial:=record.duplicate(true);trial.position=[at.x,h+origin.y-old_ground,at.y]
		if not collision(trial,pending).is_empty():continue
		if changed_support(trial):continue
		var gaps:=base_gaps(trial);tested+=1
		if not gaps.ok or gaps.minimum_soil_minus_base_m<-.035 or gaps.maximum_soil_minus_base_m>maxf(.10,float(old_gaps.get("maximum_soil_minus_base_m",0))+.02):continue
		return {"ok":true,"record":trial,"before_base":old_gaps,"after_base":gaps,"offset_m":delta.length(),"grid_step_m":.25,"tested_ground_targets":tested,"old_ground":old_ground,"new_ground":h}
	return {"ok":false,"searched_radius_m":8,"tested_ground_targets":tested}
func run()->void:
	output=OUT+"/functional_building_grass_proposal.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):target=arg.trim_prefix("--map=")
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	if FileAccess.file_exists(output):
		var bytes:=FileAccess.get_file_as_bytes(output);var sha:=FileAccess.get_sha256(output)
		var archive:=OUT+"/functional_grass_history/"+sha+".json";DirAccess.make_dir_recursive_absolute(archive.get_base_dir())
		if not FileAccess.file_exists(archive):
			var archived:=FileAccess.open(archive,FileAccess.WRITE);archived.store_buffer(bytes);archived.close()
		check(FileAccess.get_sha256(archive)==sha,"previous proposal immutable archive")
		previous_proposal=read(archive);report.previous_proposal={"path":archive,"sha256":sha}
	prepare_inputs();load_grass()
	if stop():return
	var observed:=FileAccess.get_sha256(target)
	if expected_sha.is_empty():expected_sha=observed
	check(observed==expected_sha,"read-only proposal exact current candidate SHA")
	var doc=Doc.open_file(target);check(doc!=null,"native candidate read-only open")
	if stop():return
	before=doc.recovery_snapshot();editor=Context.new();editor._doc=doc
	report.input_sha256=expected_sha;report.map=target;report.phase="readonly_terrain_geometry";persist()
	terrain_cache(doc.records);add_buildings();prepare_ground()
	if stop():return
	report.phase="readonly_native_road_geometry";persist();prepare_roads()
	if stop():return
	prepare_obstacles();report.confirmed_conflicts=[];report.moves=[];report.safe_unchanged=[]
	for record:Dictionary in doc.records:
		if not eligible.has(record.get("asset_path","")):continue
		if not relevant(record):continue
		var hits:=collision(record,[],true);var grading_conflict:=changed_support(record)
		if hits.is_empty() and not grading_conflict:report.safe_unchanged.append(record.uuid);continue
		affected.append(record.uuid);report.confirmed_conflicts.append({"id":record.uuid,"position":record.position,"hits":hits,"native_terrain_contact_conflict":grading_conflict})
	report.previous_target_checks=[]
	if previous_proposal.get("input_sha256","")==expected_sha:
		for move:Dictionary in previous_proposal.get("moves",[]):
			if move.id not in affected:continue
			var old:Dictionary=doc._find(move.id)
			if City.token(old)!=move.before_token:continue
			var trial:=old.duplicate(true);trial.position=move.position.duplicate()
			var hits:=collision(trial,affected);var gaps:=base_gaps(trial)
			var keep:bool=hits.is_empty() and not changed_support(trial) and gaps.ok and gaps.minimum_soil_minus_base_m>=-.035 and gaps.maximum_soil_minus_base_m<=maxf(.10,float(move.ground.before_base.get("maximum_soil_minus_base_m",0))+.02)
			report.previous_target_checks.append({"id":move.id,"position":move.position,"retained":keep,"hits":hits,"gaps":gaps})
			if keep:
				var kept:Dictionary=move.ground.duplicate(true);kept.record=trial;kept.ok=true;kept.after_base=gaps;kept.reused_previous_target=true;reserved_previous[move.id]=kept
		for id:String in reserved_previous:
			objects=objects.filter(func(item):return item.id!=id)
			objects.append({"id":id,"kind":"grass","shape":padded(reserved_previous[id].record)})
	report.phase="readonly_nearest_same_bank_search";persist()
	for id:String in affected:
		var record:Dictionary=doc._find(id);var remaining:=affected.filter(func(item):return not report.moves.any(func(move):return move.id==item) and not reserved_previous.has(item))
		var result:=relocate(record,remaining)
		if not result.ok:fail_detail("No safe nearby same-bank grass target",{"id":id,"search":result});continue
		var target_record:Dictionary=result.record;var restored:=target_record.duplicate(true);restored.position=record.position
		check(City.token(restored)==City.token(record),"proposal preserves scale/yaw/asset/ownership "+id)
		objects=objects.filter(func(item):return item.id!=id)
		objects.append({"id":id,"kind":"grass","shape":padded(target_record)})
		report.moves.append({"id":id,"before_token":City.token(record),"before_record":record,"position":target_record.position,"after_token":City.token(target_record),"ground":result})
		persist()
	report.final_occupancy_checks=[]
	for move:Dictionary in report.moves:
		var moved:Dictionary=move.ground.record
		var hits:=collision(moved)
		var exact_buildings:Array=[]
		for building:Dictionary in proposed_building_records:
			if Foot.batches_overlap(Foot.record_shapes(moved),Foot.record_shapes(building)):exact_buildings.append(building.uuid)
		check(hits.is_empty() and exact_buildings.is_empty(),"final complete-model and full scene grass occupancy "+move.id)
		report.final_occupancy_checks.append({"id":move.id,"hits":hits,"final_writer_Foot_building_overlaps":exact_buildings,"passed":hits.is_empty() and exact_buildings.is_empty()})
	verify_live_building_inputs();check(FileAccess.get_sha256(target)==expected_sha,"candidate untouched and unchanged during proposal")
	report.read_only=true;report.proposed_road_records_token=City.token(proposed_roads)
	report.phase="readonly_grass_proposal_complete_native_apply_pending" if failed==0 else "readonly_grass_proposal_blocked"
	report.limits=["No map saved or editor guard bypassed. Final apply must use this exact candidate SHA and the full native operations.","Native Plan/Fit and actual continuous kerb geometry used; whole-scene RoadTools/terrain protection remains mandatory in authoring.","Search is nearest on 0.25m grid within 8m on the same dry bank, preserving source root offset, scale, yaw and all asset fields."]
	persist();print("FUNCTIONAL_GRASS_PROPOSAL ",JSON.stringify({"failures":failed,"affected":affected,"moves":report.moves.map(func(m):return {"id":m.id,"position":m.position,"distance":m.ground.offset_m})}));editor.free();quit(0 if failed==0 else 1)
