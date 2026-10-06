extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
var BASE="D:/code/rmmo_runtime/cache/world3d/medieval_town_houses/map.gltf"
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
var STYLES="D:/code/rmmo_runtime/cache/world3d/town_styles_20261005/map.gltf"
var OUT="D:/code/rmmo_runtime/review_artifacts/town_arrangement_20261005"
var TARGET="D:/code/rmmo_runtime/cache/world3d/town_arrangement_20261005/map.gltf"
var BASE_HASH="d9690b53aba36e0b4277055581b199098b2375bbc7254e54380e6dca01e4e043"
var FORMAL_HASH="321ea3c6de68357d5b41ab45e54f4b20d2924a1c265f37bbb8e6bd314fa60ba8"
const Rhythm=preload("res://tools/town_frontage_rhythm.gd")
var rhythm:=false
var failures:=0
func _initialize()->void:
	rhythm="--rhythm" in OS.get_cmdline_user_args()
	if rhythm:
		BASE=FORMAL;FORMAL_HASH="e5c61e05234c5347b94422cfcac38ab2bcb4b6c89b29de159dcfea07dff283cd";BASE_HASH=FORMAL_HASH
		OUT="D:/code/rmmo_runtime/review_artifacts/town_rhythm_20261005";TARGET="D:/code/rmmo_runtime/cache/world3d/town_rhythm_20261005/map.gltf"
		STYLES="D:/code/rmmo_runtime/cache/world3d/town_window_library_20261005/map.gltf"
	call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
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
func ground(doc,point:Vector3)->float:
	for r:Dictionary in doc.records:
		if not r.has("terrain_mesh"):continue
		var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*point;var y:=Terrain.sample(r,local)
		if is_finite(y):return (pose*Vector3(local.x,y,local.z)).y
	return NAN
func relocated(sample,id:String,yaw:float)->Dictionary:
	var value:Dictionary=sample.map_meta.building_instances[id].duplicate(true)
	var origin:=B.vec(value.position);var rotation:=Basis(Vector3.UP,deg_to_rad(yaw-value.yaw));var rows:Array=[]
	for source:Dictionary in sample.records:
		if source.get("building",{}).get("id")!=id:continue
		var r:=source.duplicate(true);r.position=B.arr(rotation*(B.vec(r.position)-origin));r.rotation=B.arr((rotation*Basis.from_euler(B.vec(r.rotation)*PI/180)).get_euler()*180/PI);r.building.floor_y-=origin.y;rows.append(r)
	value.position=[0,0,0];value.yaw=yaw
	return {"records":rows,"building_instances":{id:value}}
func write_report(name_:String,value:Dictionary)->void:
	var f:=FileAccess.open(OUT.path_join(name_),FileAccess.WRITE);f.store_string(JSON.stringify(value,"\t"));f.close()
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	check(FileAccess.get_sha256(FORMAL)==FORMAL_HASH and FileAccess.get_sha256(BASE)==BASE_HASH,"formal and staged baselines unchanged")
	if failures:quit(1);return
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("result.json")))
		var runtime:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("runtime_result.json")))
		check(runtime.get("houses",0)==24 and not runtime.has("only_house"),"complete 24-house runtime review")
		check(report.failures==0 and runtime.failures==0 and report.candidate_sha256==FileAccess.get_sha256(TARGET) and runtime.candidate_sha256==report.candidate_sha256,"reviewed candidate and physical runtime agree")
		if failures:quit(1);return
		var formal=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		formal.records=candidate.records;formal.map_meta=candidate.map_meta;formal._next=candidate._next
		check(formal.save(FORMAL)==OK,"native conflict-checked atomic publication")
		var reopened=Doc.open_file(FORMAL);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records) and equivalent(reopened.records,candidate.records) and equivalent(reopened.map_meta,candidate.map_meta),"published records metadata and ownership reopen exactly")
		write_report("published.json",{"failures":failures,"sha256":FileAccess.get_sha256(FORMAL),"houses":report.houses.size(),"candidate_sha256":report.candidate_sha256});quit(1 if failures else 0);return
	var doc=Doc.open_file(BASE);var sample=Doc.open_file(STYLES)
	check(doc!=null and sample!=null,"open compact town and textured style library")
	if failures:quit(1);return
	var unchanged:Array=doc.records.filter(func(r):return not r.has("building"));var old_zones:Variant=doc.map_meta.editor_layout.zones.duplicate(true)
	doc.records=unchanged.duplicate(true);doc.map_meta.building_instances={};doc.checkpoint_recovery()
	var graph:Dictionary=doc.map_meta.editor_layout.roads;var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=B.vec(node.position)
	var presets:=B.town_presets();var houses:Array=[];var skipped:Array=[]
	for section:Dictionary in [{"edges":[3,4,2,1],"target":16,"use":"shop","styles":[0,1,2,3,4]},{"edges":[150,165,175,180,190,151,166,176,181,191],"target":8,"use":"house","styles":[5,6,7]}]:
		var placed:=0
		var sequence:Array=Rhythm.sequence(section.use,20261005 if section.use=="shop" else 20261006) if rhythm else []
		if rhythm and sequence.size()!=section.target:check(false,"valid constrained frontage sequence");quit(1);return
		for edge_index:int in section.edges:
			var edge:Dictionary=graph.edges[edge_index];var start:Vector3=nodes[edge.from];var end:Vector3=nodes[edge.to]
			var c0:Vector3=B.vec(edge.controls[0]) if edge.has("controls") else start.lerp(end,1./3);var c1:Vector3=B.vec(edge.controls[1]) if edge.has("controls") else start.lerp(end,2./3)
			# Arc-length stations keep frontage spacing consistent on curved roads.
			var points:Array[Vector3]=[];var distances:Array[float]=[0.0]
			for i in 101:
				points.append(start.bezier_interpolate(c0,c1,end,i/100.0))
				if i>0:distances.append(distances.back()+points[i].distance_to(points[i-1]))
			for side:int in [-1,1]:
				var station:float=13.0+(5.5 if side==1 else 0.0);var ordinal:=0
				while station<float(distances.back())-12.0 and placed<section.target and (not rhythm or ordinal<8):
					var choice:int=section.styles[(ordinal+(2 if side==1 else 0)+edge_index)%section.styles.size()]
					var preset:Dictionary=sequence[placed] if rhythm else presets[choice];var p:Dictionary=preset.parameters;var id:String="style_"+preset.id
					var k:=1
					while distances[k]<station:k+=1
					var t:float=(k-1+inverse_lerp(distances[k-1],distances[k],station))/100.0
					var at:=start.bezier_interpolate(c0,c1,end,t);var tangent:=start.bezier_derivative(c0,c1,end,t).normalized();var outward:=Vector3(-tangent.z,0,tangent.x)*side
					var setback:float=3.6+[0.0,.45,.15,.7][ordinal%4] if section.use=="shop" else 4.0+[0.0,1.2,.6][ordinal%3]
					if rhythm:setback=preset.setback
					var road_width:float=lerpf(float(edge.width_start),float(edge.get("width_end",edge.width_start)),t)
					var yaw:=rad_to_deg(atan2(outward.x,outward.z));var point:Vector3=at+outward*(road_width/2+float(p.depth)/2+setback)
					var basis:=Basis(Vector3.UP,deg_to_rad(yaw));var low:=INF;var high:=-INF
					for x in [-.5,0,.5]:
						for z in [-.5,0,.5]:
							var h:=ground(doc,point+basis*Vector3(x*p.width,0,z*p.depth));low=minf(low,h);high=maxf(high,h)
					if not is_finite(high) or high-low>.12:station+=3;continue
					point.y=high
					var result:=Library.place_buildings(doc,relocated(sample,id,yaw),point,preset.name)
					if not result.ok:
						skipped.append({"edge":edge.id,"station":station,"style":preset.id,"reason":result.error,"conflicts":result.get("conflicts",[])})
						if ordinal==0 and station<23:print("REJECTED ",preset.id," ",result)
						station+=3;continue
					var fresh:String=doc._find(result.ids[0]).building.id
					houses.append({"id":fresh,"source":preset.id,"style":preset.get("family_id",preset.id),"window_style":p.get("window_style","casement"),"use":section.use,"edge":edge.id,"side":side,"station":station,"floors":p.floors,"position":B.arr(point),"yaw":yaw,"road_point":B.arr(at),"setback":setback,"components":result.ids.size()})
					print("PLACED ",placed," ",preset.id," ",point);placed+=1;ordinal+=1;doc._undo.resize(1)
					station+=float(p.width)+(float(preset.gap) if rhythm else 3.0+(1.0 if ordinal%3==0 else 0.0))
			if placed>=section.target:break
		check(placed==section.target,"complete authored "+section.use+" count="+str(placed))
	check(unchanged==doc.records.filter(func(r):return not r.has("building")),"terrain roads bridges defenses unchanged from frozen candidate")
	check(old_zones==doc.map_meta.editor_layout.zones,"five reserved landmarks unchanged")
	check(B.valid_ownership(doc.map_meta,doc.records),"fixed instance identities and signatures")
	var rhythm_review:=Rhythm.audit(houses)
	if rhythm:check(rhythm_review.valid and rhythm_review.floors=={"1":6,"2":14,"3":4},"height quotas and actual frontage run constraints")
	if failures:write_report("failed.json",{"failures":failures,"houses":houses,"skipped":skipped});quit(1);return
	check(doc.save(TARGET)==OK,"native candidate save")
	var reopened=Doc.open_file(TARGET);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"candidate native reopen")
	write_report("result.json",{"failures":failures,"houses":houses,"rhythm":rhythm_review,"skipped":skipped,"candidate_sha256":FileAccess.get_sha256(TARGET),"formal_sha256":FORMAL_HASH,"base_sha256":BASE_HASH,"style_sha256":FileAccess.get_sha256(STYLES),"records":doc.records.size()})
	print("TOWN_ARRANGEMENT failures=",failures);quit(1 if failures else 0)
