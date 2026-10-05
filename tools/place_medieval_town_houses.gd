extends SceneTree
## First authored district: reuse reviewed immutable geometry, never regenerate it.
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const SAMPLE="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_houses"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_houses/map.gltf"
const EXPECTED="321ea3c6de68357d5b41ab45e54f4b20d2924a1c265f37bbb8e6bd314fa60ba8"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func equivalent(a:Variant,b:Variant)->bool:
	if (a is float or a is int) and (b is float or b is int):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equivalent(a[i],b[i]):return false
		return true
	return a==b
func write_report(name_:String,data:Dictionary)->void:
	var file:=FileAccess.open(OUT.path_join(name_),FileAccess.WRITE);file.store_string(JSON.stringify(data,"\t"));file.close()
func ground(doc,point:Vector3)->float:
	for r:Dictionary in doc.records:
		if not r.has("terrain_mesh"):continue
		var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*point
		var y:=Terrain.sample(r,local)
		if is_finite(y):return (pose*Vector3(local.x,y,local.z)).y
	return NAN
func reserved_zones()->Array:
	var result:Array=[]
	# User's five red rectangles, normalized independently by annotated image axes.
	for item in [["northwest_landmark",210,158,279,211],["northeast_landmark",669,149,725,210],["east_landmark",697,281,743,336],["central_market",396,421,468,489],["west_landmark",129,483,178,530]]:
		var x0:float=(float(item[1])/885-.5)*1400;var z0:float=(float(item[2])/890-.5)*1400
		var x1:float=(float(item[3])/885-.5)*1400;var z1:float=(float(item[4])/890-.5)*1400
		result.append({"id":"user_"+item[0],"name":"用户标记保留地 · "+item[0],"polygon":[[x0,z0],[x1,z0],[x1,z1],[x0,z1]],"min_y":-20,"max_y":100,"purpose":"no_build"})
	return result
func relocated(sample,id:String,yaw:float)->Dictionary:
	var value:Dictionary=sample.map_meta.building_instances[id].duplicate(true)
	var origin:=B.vec(value.position);var original:=Basis(Vector3.UP,deg_to_rad(value.yaw));var rotation:=Basis(Vector3.UP,deg_to_rad(yaw))*original.inverse()
	var rows:Array=[]
	for source:Dictionary in sample.records:
		if source.get("building",{}).get("id")!=id:continue
		var r:=source.duplicate(true);r.position=B.arr(rotation*(B.vec(r.position)-origin));r.rotation=B.arr((rotation*Basis.from_euler(B.vec(r.rotation)*PI/180)).get_euler()*180/PI);r.building.floor_y-=origin.y;rows.append(r)
	value.position=[0,0,0];value.yaw=yaw
	return {"records":rows,"building_instances":{id:value}}
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);DirAccess.make_dir_recursive_absolute(CANDIDATE.get_base_dir())
	check(FileAccess.get_sha256(SOURCE)==EXPECTED,"formal town has not changed")
	if failures:quit(1);return
	if "--audit" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("result.json")))
		var candidate=Doc.open_file(CANDIDATE);var source=Doc.open_file(SOURCE);var sample=Doc.open_file(SAMPLE)
		check(candidate!=null and source!=null and sample!=null,"native reopen for independent content audit")
		if failures:quit(1);return
		check(report.houses.size()==24 and report.houses.filter(func(h):return h.use=="shop").size()==16,"sixteen shops and eight adjacent homes")
		var expected:Array=source.records.duplicate(true)
		for row:Dictionary in report.houses:
			var loaded:=relocated(sample,row.source,row.yaw);var value:Dictionary=candidate.map_meta.building_instances[row.id]
			check(equivalent(value.parameters,sample.map_meta.building_instances[row.source].parameters) and value.baked,"approved fixed recipe "+row.id)
			for r:Dictionary in loaded.records:
				var actual:Dictionary=candidate._find(value.parts[r.building.part]);r.uuid=actual.uuid;r.building.id=row.id;r.building.floor_y+=row.position[1]
				r.position=B.arr(B.vec(r.position)+B.vec(row.position));r.editor_group=row.id;r.editor_group_name="大道商铺" if row.use=="shop" else "邻街住宅";expected.append(r)
		check(equivalent(expected,candidate.records),"all original and transformed prefab data survive native serialization")
		var expected_meta:Dictionary=source.map_meta.duplicate(true);expected_meta.editor_layout.zones.append_array(reserved_zones());expected_meta.environment.interior_cutaway=false;expected_meta.building_instances=candidate.map_meta.building_instances
		check(equivalent(expected_meta,candidate.map_meta),"only house ownership, five reservations and cutaway setting changed")
		check(B.valid_ownership(candidate.map_meta,candidate.records),"ownership and signatures valid")
		if failures==0:
			report.failures=0;report.serialization_audit="Reconstructed source prefabs match every saved field with native float tolerance";report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);write_report("result.json",report)
		quit(1 if failures else 0);return
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("result.json")))
		var runtime:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("runtime_result.json")))
		check(report.failures==0 and runtime.failures==0 and report.candidate_sha256==FileAccess.get_sha256(CANDIDATE) and runtime.candidate_sha256==report.candidate_sha256,"reviewed candidate matches successful runtime")
		if failures:quit(1);return
		var formal=Doc.open_file(SOURCE);var candidate=Doc.open_file(CANDIDATE)
		formal.records=candidate.records;formal.map_meta=candidate.map_meta;formal._next=candidate._next
		check(formal.save(SOURCE)==OK,"native atomic publication with original conflict baseline")
		var reopened=Doc.open_file(SOURCE);check(reopened!=null and equivalent(reopened.records,candidate.records) and equivalent(reopened.map_meta,candidate.map_meta),"published records and metadata reopen exactly")
		write_report("published.json",{"failures":failures,"sha256":FileAccess.get_sha256(SOURCE),"houses":report.houses.size()});quit(1 if failures else 0);return
	var doc=Doc.open_file(SOURCE);var sample=Doc.open_file(SAMPLE)
	check(doc!=null and sample!=null,"open town and reviewed prefab templates")
	if failures:quit(1);return
	var original:Array=doc.records.duplicate(true);var old_meta:Dictionary=doc.map_meta.duplicate(true)
	doc.checkpoint_recovery();doc.map_meta.editor_layout.zones.append_array(reserved_zones())
	var graph:Dictionary=doc.map_meta.editor_layout.roads;var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=B.vec(node.position)
	var houses:Array=[];var skipped:Array=[]
	var shop_ids=["building_31e7c806e3e52b90c263","building_27662198050339808c4c"]
	var home_ids=["building_c3bb2a43b1ee341381d1","building_5ea09ce1adf61a3a9027"]
	# West avenue between actual road junctions; adjoining residential side streets.
	for section in [{"edges":[3,4,2,1],"target":16,"use":"shop","ids":shop_ids},{"edges":[150,165,175,180,190,151,166,176,181,191],"target":8,"use":"house","ids":home_ids}]:
		var placed:=0
		for edge_index in section.edges:
			var edge:Dictionary=graph.edges[edge_index];var start:Vector3=nodes[edge.from];var end:Vector3=nodes[edge.to]
			var c0:Vector3=B.vec(edge.controls[0]) if edge.has("controls") else start.lerp(end,1./3)
			var c1:Vector3=B.vec(edge.controls[1]) if edge.has("controls") else start.lerp(end,2./3)
			for t in [.24,.46,.68,.84]:
				for side in [-1,1]:
					if placed>=section.target:break
					var at:=start.bezier_interpolate(c0,c1,end,t);var tangent:=start.bezier_derivative(c0,c1,end,t).normalized();var outward:Vector3=Vector3(-tangent.z,0,tangent.x)*side
					var id:String=section.ids[placed%section.ids.size()];var p:Dictionary=sample.map_meta.building_instances[id].parameters
					var yaw:=rad_to_deg(atan2(outward.x,outward.z));var point:Vector3=at+outward*(float(edge.width_start)/2+float(p.depth)/2+6.5)
					var basis:=Basis(Vector3.UP,deg_to_rad(yaw));var low:=INF;var high:=-INF
					for x in [-.5,0,.5]:
						for z in [-.5,0,.5]:
							var h:=ground(doc,point+basis*Vector3(x*p.width,0,z*p.depth));low=minf(low,h);high=maxf(high,h)
					if not is_finite(high) or high-low>.12:skipped.append({"edge":edge.id,"t":t,"reason":"sloped or missing supporting ground"});continue
					point.y=high
					var loaded:=relocated(sample,id,yaw)
					var result:=Library.place_buildings(doc,loaded,point,"大道商铺" if section.use=="shop" else "邻街住宅")
					if not result.ok:
						skipped.append({"edge":edge.id,"t":t,"side":side,"reason":result.error,"conflicts":result.get("conflicts",[])})
						print("SKIPPED ",point," ",result);continue
					var fresh:String=doc._find(result.ids[0]).building.id
					# This authored district is one operation; retain its original
					# recovery state, not 24 full copies of the existing city.
					doc._undo.resize(1)
					houses.append({"id":fresh,"source":id,"use":section.use,"edge":edge.id,"position":B.arr(point),"yaw":yaw,"road_point":B.arr(at),"ground_variation":high-low,"components":result.ids.size()});placed+=1
					print("PLACED ",section.use," ",placed," ",point)
			if placed>=section.target:break
		check(placed==section.target,"placed %d / %d %s"%[placed,section.target,section.use])
	check(original.all(func(r):return doc._find(r.uuid)==r),"all original terrain roads bridges and defenses unchanged")
	check(B.valid_meta(doc.map_meta) and B.valid_ownership(doc.map_meta,doc.records),"complete fixed building ownership")
	var expected:Array=doc.records.duplicate(true);var expected_meta:Dictionary=doc.map_meta.duplicate(true)
	doc.undo();check(doc.records==original and doc.map_meta==old_meta,"one undo removes the complete district and reservations")
	doc.redo();check(doc.records==expected and doc.map_meta==expected_meta,"district redo exact")
	# Match the user's already approved third-person behavior in the new district.
	doc.map_meta.environment.interior_cutaway=false
	check(doc.save(CANDIDATE)==OK,"native candidate save")
	var reopened=Doc.open_file(CANDIDATE);check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"candidate save/reopen exact")
	check(FileAccess.get_sha256(SOURCE)==EXPECTED,"formal map unchanged during staging")
	write_report("result.json",{"failures":failures,"source_sha256":EXPECTED,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"houses":houses,"skipped":skipped,"old_records":original.size(),"records":doc.records.size(),"zones":reserved_zones(),"source_meta_keys":old_meta.keys()})
	print("TOWN_HOUSES_STAGED failures=",failures);quit(1 if failures else 0)

