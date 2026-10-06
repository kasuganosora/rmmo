extends "res://tools/arrange_town_reference_styles.gd"
## Content authoring only: clone current approved, baked houses through native placement.
const LampAuthor=preload("res://tools/place_town_streetlamps.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const NEW_OUT="D:/code/rmmo_runtime/review_artifacts/town_second_street_20261005"
const NEW_MAP="D:/code/rmmo_runtime/cache/world3d/town_second_street_20261005/map.gltf"
func _initialize()->void:
	OUT=NEW_OUT;TARGET=NEW_MAP;call_deferred("run")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);DirAccess.make_dir_recursive_absolute(TARGET.get_base_dir())
	if "--publish" in OS.get_cmdline_user_args():
		var r:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/result.json"))
		var v:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/runtime_result.json"))
		check(r.failures==0 and v.failures==0 and v.houses==10 and v.candidate_sha256==r.candidate_sha256,"complete new street runtime acceptance")
		check(FileAccess.get_sha256(FORMAL)==r.formal_sha256 and FileAccess.get_sha256(TARGET)==r.candidate_sha256,"unchanged baseline and tested candidate")
		if failures:quit(1);return
		var formal=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		formal.records=candidate.records;formal.map_meta=candidate.map_meta;formal._next=candidate._next
		check(formal.save(FORMAL)==OK,"native atomic street publication")
		var reopened=Doc.open_file(FORMAL)
		check(equivalent(reopened.records,candidate.records) and equivalent(reopened.map_meta,candidate.map_meta) and B.valid_ownership(reopened.map_meta,reopened.records),"formal reopen matches approved street")
		write_report("published.json",{"failures":failures,"houses_added":10,"lamps_added":r.lamps.size(),"formal":FileAccess.get_sha256(FORMAL),"candidate":r.candidate_sha256});quit(1 if failures else 0);return
	var baseline:=FileAccess.get_sha256(FORMAL);var doc=Doc.open_file(FORMAL)
	check(doc!=null and doc.map_meta.building_instances.size()==24,"current 24-house approved source")
	if failures:quit(1);return
	var original:Array=doc.records.duplicate(true);var original_meta:Dictionary=doc.map_meta.duplicate(true)
	var graph:Dictionary=doc.map_meta.editor_layout.roads;var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=B.vec(node.position)
	var edge:Dictionary=graph.edges[180]
	check(edge.id=="e_4338c9d4ef05fd40","existing western side street from reference road graph")
	var start:Vector3=nodes[edge.from];var end:Vector3=nodes[edge.to]
	var c0:Vector3=B.vec(edge.controls[0]) if edge.has("controls") else start.lerp(end,1./3)
	var c1:Vector3=B.vec(edge.controls[1]) if edge.has("controls") else start.lerp(end,2./3)
	var points:Array[Vector3]=[];var distances:Array[float]=[0.0]
	for i in 101:
		points.append(start.bezier_interpolate(c0,c1,end,i/100.0))
		if i>0:distances.append(distances.back()+points[i].distance_to(points[i-1]))
	var houses:Array=[];var skipped:Array=[];var used:Dictionary={}
	var rng:=RandomNumberGenerator.new();rng.seed=2026100519
	doc.checkpoint_recovery()
	for side:int in [-1,1]:
		# The east frontage ends at existing houses; keep its junction open.
		var levels:Array=[2,1,3,2,2,1] if side==-1 else [2,1,2,2]
		var station:=14.0 if side==-1 else 19.0;var previous_window:="";var previous_source:=""
		for ordinal in levels.size():
			var choices:Array=[]
			for id:String in original_meta.building_instances:
				var h:Dictionary=original_meta.building_instances[id];var p:Dictionary=h.parameters
				if int(p.floors)!=levels[ordinal] or p.template!="house":continue
				choices.append({"id":id,"cost":float(used.get(id,0))*2+rng.randf()+(10 if id==previous_source else 0)+(4 if p.window_style==previous_window else 0)})
			choices.sort_custom(func(a,b):return a.cost<b.cost)
			var placed:=false
			while station<float(distances.back())-17 and not placed:
				var k:=1
				while distances[k]<station:k+=1
				var t:float=(k-1+inverse_lerp(distances[k-1],distances[k],station))/100.0
				var at:=start.bezier_interpolate(c0,c1,end,t);var tangent:=start.bezier_derivative(c0,c1,end,t).normalized()
				var outward:=Vector3(-tangent.z,0,tangent.x)*side;var yaw:=rad_to_deg(atan2(outward.x,outward.z))
				var setback:=snappedf(rng.randf_range(3.8,5.8),.05)
				for choice:Dictionary in choices:
					var source:String=choice.id;var p:Dictionary=original_meta.building_instances[source].parameters
					var point:Vector3=at+outward*(lerpf(edge.width_start,edge.get("width_end",edge.width_start),t)/2+float(p.depth)/2+setback)
					var basis:=Basis(Vector3.UP,deg_to_rad(yaw));var low:=INF;var high:=-INF
					for x in [-.5,0,.5]:
						for z in [-.5,0,.5]:
							var height:=ground(doc,point+basis*Vector3(x*p.width,0,z*p.depth));low=minf(low,height);high=maxf(high,height)
					if not is_finite(high) or high-low>.12:continue
					point.y=high
					var result:=Library.place_buildings(doc,relocated(doc,source,yaw),point,"西侧支街住宅")
					if not result.ok:skipped.append({"station":station,"side":side,"source":source,"reason":result});continue
					var fresh:String=doc._find(result.ids[0]).building.id
					houses.append({"id":fresh,"source":source,"use":"house","edge":edge.id,"side":side,"station":station,"floors":int(p.floors),"window_style":p.window_style,"position":B.arr(point),"yaw":yaw,"road_point":B.arr(at),"setback":setback,"components":result.ids.size()})
					used[source]=int(used.get(source,0))+1;previous_source=source;previous_window=p.window_style
					station+=float(p.width)+rng.randf_range(2.7,4.7);doc._undo.resize(1);placed=true
					print("NEW_HOUSE ",houses.size()," ",point," floors=",p.floors);break
				if not placed:station+=2.5
			check(placed,"reference frontage slot "+str(side)+":"+str(ordinal))
	var rhythm_review:=Rhythm.audit(houses)
	check(houses.size()==10 and rhythm_review.valid and rhythm_review.floors=={"1":3,"2":6,"3":1},"ten houses with constrained non-mirrored height rhythm")
	if failures:write_report("failed.json",{"houses":houses,"skipped":skipped});quit(1);return
	var segments:Array=[]
	for r:Dictionary in original:
		if not r.has("road_mesh"):continue
		var transform:=Transform3D(Basis.from_euler(B.vec(r.rotation)*PI/180),B.vec(r.position))
		for polygon:Array in Road.local_polygons(r):
			for i in polygon.size():
				var a:Vector3=transform*polygon[i];var b:Vector3=transform*polygon[(i+1)%polygon.size()]
				segments.append([Vector2(a.x,a.z),Vector2(b.x,b.z)])
	var loaded:=Library.read({"prefab_path":LampAuthor.PREFAB});var lamps:Array=[]
	var existing_lamps:Array=original.filter(func(r):return r.get("kind")=="asset" and str(r.get("label","")).contains("路灯"))
	for row:Dictionary in houses:
		var h:Dictionary=doc.map_meta.building_instances[row.id];var curb:Dictionary=LampAuthor.roadside(segments,h)
		check(not curb.is_empty() and curb.facade_clearance>1.5,"roadside lamp keeps house frontage clear")
		if curb.is_empty():continue
		var at:Vector3=curb.point;at.y=ground(doc,at)
		if (existing_lamps+lamps).any(func(l):return B.vec(l.position).distance_to(at)<8.5):continue
		var placed:=Library.place(doc,{"prefab_path":LampAuthor.PREFAB,"label":"西侧支街路灯"},at-B.vec(loaded.records[0].position))
		check(placed.ok,"native lamp prefab placement");if not placed.ok:continue
		var record:Dictionary=doc._find(placed.ids[0]);record.rotation=[0,curb.yaw,0];record.label="西侧支街路灯 %02d"%(lamps.size()+1)
		lamps.append({"id":record.uuid,"house":row.id,"position":record.position,"yaw":curb.yaw,"road_edge":B.arr(curb.edge),"width":h.parameters.width,"depth":h.parameters.depth});doc._undo.resize(1)
	check(lamps.size()>=7,"street lamps spaced along both road edges")
	check(equivalent(original,doc.records.slice(0,original.size())),"all pre-existing map records unchanged")
	var expected_meta:Dictionary=doc.map_meta.duplicate(true);expected_meta.building_instances=original_meta.building_instances
	check(equivalent(expected_meta,original_meta),"roads river five reservations and environment unchanged")
	check(B.valid_ownership(doc.map_meta,doc.records),"frozen buildings preserve floor and active-part ownership")
	var after:Array=doc.records.duplicate(true);var after_meta:Dictionary=doc.map_meta.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original) and equivalent(doc.map_meta,original_meta),"single undo restores original city")
	check(doc.redo() and equivalent(doc.records,after) and equivalent(doc.map_meta,after_meta),"redo restores complete new street")
	if failures:quit(1);return
	check(doc.save(TARGET)==OK,"native candidate save")
	var reopened=Doc.open_file(TARGET)
	check(equivalent(reopened.records,after) and equivalent(reopened.map_meta,after_meta),"candidate reopen")
	write_report("result.json",{"failures":failures,"formal_sha256":baseline,"candidate_sha256":FileAccess.get_sha256(TARGET),"houses":houses,"lamps":lamps,"rhythm":rhythm_review,"skipped":skipped})
	print("NEW_STREET_STAGED failures=",failures);quit(1 if failures else 0)
