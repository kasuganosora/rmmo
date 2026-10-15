extends SceneTree
## Task-local authoring measurement, never writes a map or changes native rules.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Fit=preload("res://scripts/world3d/road_terrain_fit.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const CLEARANCE=.08
var doc
var settings:Dictionary
var terrains:Array=[]
func data(n:String)->Variant:return JSON.parse_string(FileAccess.get_file_as_string(OUT+"/"+n))
func xy(p:Vector2)->Array:return [p.x,p.y]
func v2(p:Array)->Vector2:return Vector2(p[0],p[1])
func oriented(records:Array,origin:Vector3,yaw:float)->Array:
	var out:=records.duplicate(true);var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
	for r:Dictionary in out:
		r.position=B.arr(origin+basis*B.vec(r.position));r.rotation=B.arr((basis*Basis.from_euler(B.vec(r.rotation)*PI/180)).get_euler()*180/PI)
	return out
func grown(shapes:Array)->Array:
	var result:Array=[]
	for s:Dictionary in shapes:
		var copy:=s.duplicate(true);var expanded:=Geometry2D.offset_polygon(s.polygon,CLEARANCE,Geometry2D.JOIN_ROUND)
		assert(expanded.size()==1);copy.polygon=expanded[0];copy.polygon.append(copy.polygon[0]);copy.bounds=copy.bounds.grow(CLEARANCE);result.append(copy)
	return result
func road_shapes(records:Array)->Array:
	var out:Array=[]
	for r:Dictionary in records:
		out.append_array(Foot.record_shapes(r))
		var pose:=Transform3D(Basis.from_euler(B.vec(r.rotation)*PI/180),B.vec(r.position))
		for kerb:Dictionary in r.road_mesh.get("kerbs",[]):
			var pts:Array[Vector3]=[]
			for p:Array in kerb.a+kerb.b:pts.append(pose*B.vec(p))
			out.append(Foot.from_points(pts))
	return out
func strict_overlap(a:Array,b:Array)->bool:
	for left:Dictionary in a:
		for right:Dictionary in b:
			if Foot.overlaps(left,right,0.):return true
	return false
func measured_gap(a:Array,b:Array)->float:
	var gap:=INF
	for left:Dictionary in a:
		for right:Dictionary in b:
			if left.bounds.end.y<=right.bounds.position.y or right.bounds.end.y<=left.bounds.position.y:continue
			for pair:Array in [[left.polygon,right.polygon],[right.polygon,left.polygon]]:
				var p:PackedVector2Array=pair[0];var q:PackedVector2Array=pair[1]
				for point:Vector2 in p:
					for i in q.size()-1:gap=minf(gap,point.distance_to(Geometry2D.get_closest_point_to_segment(point,q[i],q[i+1])))
	return gap
func graph(points:Array)->Dictionary:
	var nodes:Array=[];var edges:Array=[]
	for i in points.size():
		var p:=v2(points[i]);nodes.append({"id":"access_n%d"%i,"position":[p.x,Props.ground(doc,Vector3(p.x,0,p.y)),p.y]})
		if i>0:edges.append({"id":"access_e%d"%i,"from":"access_n%d"%(i-1),"to":"access_n%d"%i,"kind":"ground","name":"measured_home_access","width_start":1.6,"width_end":1.6})
	return {"nodes":nodes,"edges":edges}
func plan_path(points:Array)->Dictionary:return Plan.build(graph(points),settings)
func flat_collision(records:Array,pieces:Array,y:float)->bool:
	# Broad XY search uses the exact native hull; only shapes within the final
	# road's conservative vertical band participate. Actual fitted shapes follow.
	for road:Dictionary in road_shapes(records):
		road.bounds.position.y=y-2.;road.bounds.size.y=5.6
		if strict_overlap(pieces,[road]):return true
	return false
func paths(h:Dictionary,offset:float)->Dictionary:
	var pts:Array=h.access_points.duplicate(true);var entrance:=v2(h.entrance_xz);var angle:=deg_to_rad(float(h.yaw));var outward:=Vector2(-sin(angle),-cos(angle))
	pts[0]=xy(entrance+outward*offset)
	var updated:Array=[]
	# This path runs sideways to the rear lane. Move the whole short landing
	# outwards, preserving a straight lateral connection to that existing lane.
	if h.id=="s10_back_home":
		var q:=v2(pts[1]);q+=outward*(offset-(q-entrance).dot(outward));pts[1]=xy(q);updated=[h.entrance_xz,pts[1]]
	if pts.size()<2:return {"ok":false,"error":"no independent home path"}
	var delta:=v2(pts[1])-v2(pts[0])
	if delta.length()<.3 or delta.dot(outward)<-.01:return {"ok":false,"error":"setback would pass the next turn"}
	return {"ok":true,"points":pts,"updated":updated}
func original_contacts(pieces:Array,roads:Array)->Array:
	var rows:Array=[]
	for road:Dictionary in roads:
		var shapes:=Foot.record_shapes(road)
		if not Foot.batches_overlap(pieces,shapes):continue
		var cuts:Array=[]
		for a:Dictionary in pieces:
			for b:Dictionary in shapes:
				if not Foot.overlaps(a,b):continue
				for cut:PackedVector2Array in Geometry2D.intersect_polygons(a.polygon,b.polygon):
					if cut.size()>2:cuts.append(Array(cut).map(func(p):return xy(p)))
		rows.append({"uuid":road.uuid,"intersection_polygons_xz":cuts})
	return rows
func _initialize()->void:
	doc=Doc.new();doc.apply_recovery(bytes_to_var(FileAccess.get_file_as_bytes(OUT+"/s12_after_roads.bin")))
	terrains=doc.records.filter(func(r):return r.has("terrain_mesh"))
	var recipe:Dictionary=data("housing_recipe.json");settings=recipe.road_settings
	var index:Dictionary={};var poses:Dictionary={}
	for t:Dictionary in data("house_templates.json").templates:index[t.id]=t
	for row:Dictionary in data("s12_native_preflight.json").houses:poses[row.id]=B.vec(row.position)
	var roads:Array=data("s12_generated_roads.json");var rows:Array=[];var failed:=0
	for h:Dictionary in recipe.houses:
		if h.id in ["s12_arch_home","s12_south_cottage"]:continue
		var t:Dictionary=index[h.template_id];assert(FileAccess.get_sha256(t.loaded_path)==t.sha256)
		var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(t.loaded_path))
		var origin:Vector3=poses[h.id];var pieces:=Foot.components(oriented(loaded.records,origin,h.yaw),Vector3.ZERO,Basis.IDENTITY);var safe:=grown(pieces)
		var old:=original_contacts(pieces,roads)
		var result:Dictionary={"id":h.id,"template_id":t.id,"template_sha256":t.sha256,"position":h.position,"yaw":h.yaw,"actual_origin":B.arr(origin),"clearance_m":CLEARANCE,"original_offset_m":.9,"original_conflicts":old,"ok":false}
		for step in 75:
			var offset:=snappedf(.9+step*.05,.05);var candidate:=paths(h,offset)
			if not candidate.ok:result.error=candidate.error;break
			var plan:=plan_path(candidate.points)
			if not plan.ok:result.error=plan;break
			if flat_collision(plan.records,safe,origin.y):continue
			var fitted:=Fit.fit(plan.records,terrains,float(settings.lift),128)
			if not fitted.ok:result.error=fitted;break
			var shapes:=road_shapes(fitted.records)
			if strict_overlap(safe,shapes):continue
			result.ok=true;result.offset_from_entrance_m=offset;result.access_points=candidate.points
			if not candidate.updated.is_empty():result.updated_connector_points=candidate.updated
			result.native_plan_chunks=plan.records.size();result.fitted_chunks=fitted.records.size();result.checked_continuous_kerb_width_m=settings.kerb_width
			result.measured_min_horizontal_clearance_m=measured_gap(pieces,shapes)
			result.native_footprint_clear=true;result.terrain_fit_passed=true;break
		if not result.ok:failed+=1
		rows.append(result);print("ACCESS ",JSON.stringify(result))
	var report:={"ok":failed==0,"failed":failed,"source_sha256":data("source_identity.json").sha256,"input_recipe_sha256":FileAccess.get_sha256(OUT+"/housing_recipe.json"),"native_snapshot_sha256":FileAccess.get_sha256(OUT+"/s12_after_roads.bin"),"scope":"12 home entry paths only. Full frozen native Footprint.components includes active-door/window sweeps. Native Plan round caps and continuous kerb; final TerrainFit and 8cm expanded complete house occupancy. No native protections changed; no map writes. Full regenerated graph remains required.","houses":rows}
	FileAccess.open(OUT+"/house_access_setbacks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(failed)
