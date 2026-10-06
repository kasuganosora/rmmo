extends "res://tools/arrange_town_reference_styles.gd"
## Local, additive content recipe. Uses native frozen-building/prefab placement and save.
const SCENE_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_reference_scene_20261006"
const SCENE_MAP="D:/code/rmmo_runtime/cache/world3d/bridge_reference_scene_20261006/map.gltf"
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
var props:Dictionary={}
var additions:Array=[]
var houses:Array=[]
var doc
var source
var nodes:Dictionary={}
var edges:Array=[]
var omitted:Array=[]
func clear_passages()->void:
	var obstacles:Array=[]
	for r:Dictionary in doc.records:
		if r.has("road_mesh") or r.has("building"):obstacles.append({"record":r,"bounds":Geometry.bounds([r])})
	for addition:Dictionary in additions.duplicate():
		if addition.source=="small_wall_lantern" or addition.source.ends_with("bunting") or addition.source=="reference_bank":continue
		var r:Dictionary=doc._find(addition.id);var bounds:=Geometry.bounds([r]);var shape:Array=Foot.record_shapes(r)
		for obstacle:Dictionary in obstacles:
			if not bounds.intersects(obstacle.bounds):continue
			if not Foot.batches_overlap(shape,Foot.record_shapes(obstacle.record)):continue
			omitted.append({"source":addition.source,"position":addition.position,"conflict":obstacle.record.uuid})
			doc.records=doc.records.filter(func(v):return v.uuid!=addition.id);additions.erase(addition)
			print("OMIT_OBSTRUCTING_PROP ",addition.source," ",obstacle.record.uuid);break
func _initialize()->void:
	OUT=SCENE_OUT;TARGET=SCENE_MAP;run.call_deferred()
func road_frame(index:int,t:float)->Dictionary:
	var e:Dictionary=edges[index];var a:Vector3=nodes[e.from];var b:Vector3=nodes[e.to]
	var c:Vector3=B.vec(e.controls[0]);var d:Vector3=B.vec(e.controls[1])
	var tangent:=a.bezier_derivative(c,d,b,t).normalized()
	return {"point":a.bezier_interpolate(c,d,b,t),"forward":tangent,"right":Vector3(-tangent.z,0,tangent.x)}
func prop(key:String,at:Vector3,yaw:float=0,scale_:Vector3=Vector3.ONE,label_:String="")->String:
	var entry:Dictionary=props[key];var placed:=Library.place(doc,entry,at)
	check(placed.ok,"prefab "+key)
	if not placed.ok:return ""
	for id:String in placed.ids:
		var r:Dictionary=doc._find(id);var local:=B.vec(r.position)-at
		r.position=B.arr(at+Basis(Vector3.UP,deg_to_rad(yaw))*(local*scale_));r.rotation=[0,yaw,0]
		r.size=B.arr(B.vec(r.size)*scale_);r.editor_group_name="东南桥彩旗街 · "+entry.label
		r.label=label_ if not label_.is_empty() else entry.label
		additions.append({"id":id,"source":key,"position":r.position,"rotation":r.rotation,"scale":r.size})
	doc._undo.resize(1)
	return placed.ids[0]
func seated(key:String,at:Vector3,yaw:float=0,scale_:Vector3=Vector3.ONE)->String:
	at.y=ground(doc,at);check(is_finite(at.y),"terrain support")
	return prop(key,at,yaw,scale_)
func house(id:String,index:int,t:float,side:int,setback:float)->void:
	var p:Dictionary=source.map_meta.building_instances[id].parameters
	for attempt in 10:
		var f:=road_frame(index,t+attempt*.018);var outward:Vector3=f.right*side
		var at:Vector3=f.point+outward*(5.+float(p.depth)/2+setback)
		var yaw:=rad_to_deg(atan2(outward.x,outward.z));var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
		var low:=INF;var high:=-INF
		for x in [-.5,0,.5]:
			for z in [-.5,0,.5]:
				var y:=ground(doc,at+basis*Vector3(x*p.width,0,z*p.depth));low=minf(low,y);high=maxf(high,y)
		if not is_finite(high) or high-low>.14:continue
		at.y=high
		var placed:=Library.place_buildings(doc,relocated(source,id,yaw),at,"东南桥彩旗街房屋")
		if not placed.ok:print("HOUSE_REJECT ",index," ",t," ",side," ",placed);continue
		var fresh:String=doc._find(placed.ids[0]).building.id
		houses.append({"id":fresh,"source":id,"position":B.arr(at),"yaw":yaw,"road_point":B.arr(f.point),"edge":index,"t":t+attempt*.018,"side":side,"floors":p.floors,"window_style":p.window_style,"use":p.template})
		doc._undo.resize(1);print("HOUSE_ADDED ",fresh," ",at);return
	check(false,"place house slot "+id+" / "+str(index)+" / "+str(side))
func festival(index:int,t:float,back:bool=false)->void:
	var f:=road_frame(index,t);var yaw:=rad_to_deg(atan2(-f.right.z,f.right.x))
	for side in [-1,1]:seated("town_festival_posts_POST_blue" if side<0 else "reference_POST_green" if back else "reference_POST_rose",f.point+f.right*5.85*side,yaw,Vector3(1.5,1.9,1.5))
	prop("reference_long_bunting",f.point+Vector3.UP*3.17,yaw)
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);DirAccess.make_dir_recursive_absolute(TARGET.get_base_dir())
	if "--publish" in OS.get_cmdline_user_args():
		var r:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/result.json"))
		var v:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/runtime_result.json"))
		check(r.failures==0 and v.failures==0 and v.candidate_sha256==r.candidate_sha256,"reviewed runtime candidate")
		check(FileAccess.get_sha256(FORMAL)==r.formal_sha256 and FileAccess.get_sha256(TARGET)==r.candidate_sha256,"unchanged source and tested candidate")
		if failures:quit(1);return
		var formal=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		formal.records=candidate.records;formal.map_meta=candidate.map_meta;formal._next=candidate._next
		check(formal.save(FORMAL)==OK,"native conflict-checked atomic publication")
		var reopened=Doc.open_file(FORMAL)
		check(equivalent(reopened.records,candidate.records) and equivalent(reopened.map_meta,candidate.map_meta),"formal save and reopen match")
		write_report("published.json",{"failures":failures,"formal":FORMAL,"sha256":FileAccess.get_sha256(FORMAL),"candidate_sha256":r.candidate_sha256,"houses":r.houses.size(),"props":r.props.size()});quit(1 if failures else 0);return
	var baseline:=FileAccess.get_sha256(FORMAL);doc=Doc.open_file(FORMAL);source=doc
	check(doc!=null and doc.map_meta.building_instances.size()==34,"current town source with 34 houses")
	if failures:quit(1);return
	var original:Array=doc.records.duplicate(true);var original_meta:Dictionary=doc.map_meta.duplicate(true)
	var publication:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/town_props_20261006/published.json"))
	for item:Dictionary in publication.items:props[item.id]=item.entry
	var art:="D:/code/rmmo_runtime/art_sources/bridge_reference_scene_20261006/"
	var assets:=Assets.new("D:/code/rmmo_runtime/cache/world3d/bridge_reference_scene_20261006/assets")
	for spec:Array in [["reference_long_bunting","bridge_single_span_nine_flags.glb","桥头九面长旗"],["reference_POST_green","festival_post_green.glb","绿色金丝带彩柱"],["reference_POST_rose","festival_post_rose.glb","玫红金丝带彩柱"]]:
		var imported:=assets.import_file(art+spec[1]);check(imported.ok,"import revised "+spec[0])
		if not imported.ok:quit(1);return
		var temp:=Doc.new();var id:String=temp.add_asset(imported.entry,Vector3.ZERO)
		if spec[0].ends_with("bunting"):temp._find(id).collision="none"
		var captured:=Library.capture(temp.records,assets,spec[2]);check(captured.ok,"package revised "+spec[0]);props[spec[0]]=captured.entry
	for n:Dictionary in doc.map_meta.editor_layout.roads.nodes:nodes[n.id]=B.vec(n.position)
	for id in ["e_8c02b3753c1cd333","e_ce8f7d760ac57ca4"]:
		edges.append(doc.map_meta.editor_layout.roads.edges.filter(func(e):return e.id==id)[0])
	doc.checkpoint_recovery()
	house("building_10e2848ee287d056ac56",0,.12,-1,2.0)
	house("building_9fe0774e57e3a1da3653",0,.14,1,2.7)
	house("building_cf4b040225194dae436a",0,.35,-1,1.4)
	house("building_d7f12ee3e3ef99a607db",0,.49,1,2.0)
	house("building_814bb1d9340b268d1353",0,.79,1,2.6)
	house("building_78a81ce12c69cb34348e",1,.20,-1,2.7)
	house("building_3dcf25fc1f0a02b31bf2",1,.22,1,2.0)
	house("building_220586e9028ed6139243",1,.46,-1,2.2)
	house("building_16427952a2beef846990",1,.48,1,2.8)
	if failures:write_report("failed.json",{"failures":failures,"houses":houses});quit(1);return
	festival(0,.10);festival(0,.26,true)
	for h:Dictionary in houses:
		var f:=road_frame(h.edge,h.t);var outward:Vector3=f.right*h.side
		var p:Dictionary=doc.map_meta.building_instances[h.id].parameters;var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw));var at:=B.vec(h.position)
		# Keep central entrance and its door swing free; decoration is at facade corners.
		for sign_ in [-1,1]:
			var corner:=at+basis*Vector3(sign_*(p.width/2-1.9),0,-p.depth/2-1.0)
			seated("town_planters_02_window_flowers" if sign_==-1 else "town_planters_05_brick_leaf_border",corner,h.yaw,Vector3(.8,1,1))
		prop("small_wall_lantern",at+basis*Vector3(1.8,2.35,-p.depth/2-.08),h.yaw)
	# Left riverbank and right wash yard are distinct, broken low enclosures.
	var f:=road_frame(0,.03);var along:Vector3=f.forward;var across:Vector3=f.right
	var wall_yaw:=rad_to_deg(atan2(-across.z,across.x))
	for side in [-1,1]:
		var yard:Vector3=f.point+(across*14+along*7 if side==1 else Vector3.ZERO)
		for i in 4:seated("bridge_street_kit_08_low_garden_wall",yard+across*side*(9.0+i*2.9),wall_yaw)
		seated("bridge_street_kit_09_garden_gate_pier",yard+across*side*7.3,wall_yaw)
		for i in 5:seated("bridge_street_kit_12_natural_boxwood_shrub",yard+across*side*(9.5+i*3.0)+along*1.6,wall_yaw+side*13,Vector3(1.15,1.15,1.15))
	seated("bridge_street_kit_10_laundry_line",f.point+across*28+along*12,wall_yaw)
	# Continuous grass-topped cliff covers the old slope without moving the water.
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9");var bb:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=B.vec(bridge.position)
	var bank_import:=assets.import_file(art+"grass_rock_bank.glb");check(bank_import.ok,"import continuous rock bank")
	if not bank_import.ok:quit(1);return
	var bank_id:String=doc.add_asset(bank_import.entry,Vector3(center.x,0,center.z));var bank:Dictionary=doc._find(bank_id)
	bank.rotation=[0,bridge.rotation[1],0];bank.label="东南桥 · 连续草顶岩岸";bank.collision="walk"
	additions.append({"id":bank_id,"source":"reference_bank","position":bank.position,"rotation":bank.rotation,"scale":bank.size})
	var bank_recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(art+"bank_recipe.json"));var rng:=RandomNumberGenerator.new();rng.seed=202610061
	for side:Dictionary in bank_recipe.banks:
		for sample:Array in side.cross_sections:
			if absf(sample[0])>31:continue
			for i in 2:
				var shrub:Vector3=Vector3(center.x,0,center.z)+bb*Vector3(sample[1]+rng.randf_range(.8,2.8),.12,sample[0]+rng.randf_range(-.6,.6))
				var scale_:float=rng.randf_range(.9,1.4)
				prop("bridge_street_kit_12_natural_boxwood_shrub",shrub,rng.randf_range(-180,180),Vector3.ONE*scale_)
	clear_passages()
	check(additions.filter(func(p):return p.source.contains("POST_")).size()==4,"both flag spans retain two supported posts clear of buildings")
	var bookmarks:Array=doc.map_meta.editor_layout.bookmarks
	bookmarks.append({"id":"bridge_festival_20261006","name":"东南桥 · 彩旗街景","camera":{"center":[323,2,175],"distance":65.,"pitch":-18.,"projection":"perspective","span":100.,"yaw":-138.}})
	check(equivalent(original,doc.records.slice(0,original.size())),"all pre-existing records unchanged")
	var meta:Dictionary=doc.map_meta.duplicate(true);meta.building_instances=original_meta.building_instances;meta.editor_layout.bookmarks=original_meta.editor_layout.bookmarks
	check(equivalent(meta,original_meta),"roads river reservations environment and existing metadata unchanged")
	check(B.valid_ownership(doc.map_meta,doc.records),"frozen floor roof door/window identities valid")
	var after:Array=doc.records.duplicate(true);var after_meta:Dictionary=doc.map_meta.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original) and equivalent(doc.map_meta,original_meta),"single undo restores complete source")
	check(doc.redo() and equivalent(doc.records,after) and equivalent(doc.map_meta,after_meta),"single redo restores authored district")
	if failures:quit(1);return
	check(doc.save(TARGET)==OK,"native candidate atomic save")
	var reopened=Doc.open_file(TARGET)
	check(reopened!=null and equivalent(reopened.records,after) and equivalent(reopened.map_meta,after_meta) and reopened.missing_assets().is_empty(),"reopen matches with all dependencies")
	write_report("result.json",{"failures":failures,"formal_sha256":baseline,"candidate_sha256":FileAccess.get_sha256(TARGET),"houses":houses,"props":additions,"omitted_obstructions":omitted,"bridge_id":bridge.uuid,"reference":"docs/references/town_bridge_street_20261005/01_bridge_to_festival_street.png","missing":["game-ready broad green canopy oak","fine bank grasses","distant pointed-roof tower"],"people_in_scope":false})
	print("BRIDGE_SCENE_STAGED failures=",failures);quit(1 if failures else 0)
