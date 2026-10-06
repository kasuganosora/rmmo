extends "res://tools/arrange_bridge_reference_scene.gd"
const FINAL_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_street_finish_20261006"
const FINAL_MAP="D:/code/rmmo_runtime/cache/world3d/bridge_street_finish_20261006/map.gltf"
func _initialize()->void:
	OUT=FINAL_OUT;TARGET=FINAL_MAP;run.call_deferred()
func festival(index:int,t:float,back:bool=false)->void:
	var left:=road_frame(index,.055 if not back else t);var right:=road_frame(index,.17 if not back else t)
	var a:Vector3=left.point-left.right*5.85;var b:Vector3=right.point+right.right*5.85
	var span:Vector3=b-a;var yaw:=rad_to_deg(atan2(-span.z,span.x))
	seated("town_festival_posts_POST_blue",a,yaw,Vector3(1.5,1.9,1.5))
	seated("reference_POST_green" if back else "town_festival_posts_POST_natural",b,yaw,Vector3(1.5,1.9,1.5))
	prop("reference_long_bunting",(a+b)*.5+Vector3.UP*3.17,yaw,Vector3(span.length()/11.3,1,1))
func house(id:String,index:int,t:float,side:int,setback:float)->void:
	var p:Dictionary=source.map_meta.building_instances[id].parameters
	var reason:Variant="terrain slope"
	for attempt in 12:
		var tt:float=t+attempt*.009
		if tt>.98:break
		var f:=road_frame(index,tt);var outward:Vector3=f.right*side
		var at:Vector3=f.point+outward*(5.+float(p.depth)/2+setback)
		var yaw:=rad_to_deg(atan2(outward.x,outward.z));var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
		var low:=INF;var high:=-INF
		for x in [-.5,0,.5]:
			for z in [-.5,0,.5]:
				var y:=ground(doc,at+basis*Vector3(x*p.width,0,z*p.depth));low=minf(low,y);high=maxf(high,y)
		if not is_finite(high) or high-low>.14:continue
		at.y=high
		var placed:=Library.place_buildings(doc,relocated(source,id,yaw),at,"东南桥 · 密集街面")
		if not placed.ok:reason=placed;continue
		var fresh:String=doc._find(placed.ids[0]).building.id
		houses.append({"id":fresh,"source":id,"position":B.arr(at),"yaw":yaw,"road_point":B.arr(f.point),"edge":index,"t":tt,"side":side,"floors":p.floors,"window_style":p.window_style,"rear":setback>10})
		doc._undo.resize(1);print("HOUSE_ADDED ",houses.size()," ",index," ",tt," ",side);return
	omitted.append({"type":"house","source":id,"edge":index,"t":t,"side":side})
	print("HOUSE_OMITTED ",index," ",t," ",side," ",reason)
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);DirAccess.make_dir_recursive_absolute(TARGET.get_base_dir())
	if "--frontage-clearance" in OS.get_cmdline_user_args():
		var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"))
		# Rebuild just these proposed decorations from the saved candidate so
		# iterative clearance reviews do not accumulate deletions.
		var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/result.json"))
		var old_records:Array=Doc.authoritative_extras(TARGET).extras.rmmo_records
		for item:Dictionary in previous.props:
			if item.source not in ["oak","town_planters_02_window_flowers"]:continue
			p.props=p.props.filter(func(v):return v.id!=item.id);p.props.append(item)
			p.records=p.records.filter(func(v):return v.uuid!=item.id);p.records.append(old_records.filter(func(v):return v.uuid==item.id)[0])
		doc=Doc.new();doc.records=p.records;doc.map_meta=p.metadata;doc._next=p.next
		for item:Dictionary in p.props:
			if item.source!="town_planters_02_window_flowers":continue
			var r:Dictionary=doc._find(item.id);var nearest:Dictionary={};var distance:=INF
			if item.has("house"):
				nearest=p.houses.filter(func(h):return h.id==item.house)[0];distance=0.
			for h:Dictionary in p.houses:
				if not nearest.is_empty() and distance==0.:break
				if h.rear:continue
				var params:Dictionary=p.metadata.building_instances[h.id].parameters
				var old:Vector3=B.vec(h.position)+Basis(Vector3.UP,deg_to_rad(h.yaw))*Vector3(-params.width*.32,0,-params.depth/2-1.55)
				if old.distance_to(B.vec(r.position))<distance:distance=old.distance_to(B.vec(r.position));nearest=h
			check(distance<.1,"identify original planter frontage")
			if distance>=.1:continue
			var params:Dictionary=p.metadata.building_instances[nearest.id].parameters
			var plan:Dictionary=B.generate(params);var entry:=B.vec(plan.entrance)
			var half:Vector3=B.vec(r.bounds_size)*B.vec(r.size)*.5
			var window_z:float=plan.rooms[0].center[2]
			check(window_z-half.x-entry.z>=1.5,"side planter clears full front approach")
			var at:Vector3=B.vec(nearest.position)+Basis(Vector3.UP,deg_to_rad(nearest.yaw))*Vector3(-params.width/2-half.z-.65,0,window_z)
			at.y=ground(doc,at);r.position=B.arr(at);r.rotation=[0,nearest.yaw+90,0];item.position=r.position;item.rotation=r.rotation;item.house=nearest.id
		# Native porches already provide the entrance steps. Loose stones do not
		# belong in that approach, even when the player can step over them.
		var remove:Array=p.props.filter(func(i):return i.source=="steps").map(func(i):return i.id)
		doc.records=doc.records.filter(func(r):return not r.uuid in remove)
		p.props=p.props.filter(func(i):return not i.id in remove)
		var other:Array=p.props.filter(func(i):return i.source!="town_planters_02_window_flowers")
		additions=p.props.filter(func(i):return i.source=="town_planters_02_window_flowers");omitted=p.omitted;clear_passages();p.props=other+additions;p.omitted=omitted
		p.records=doc.records;p.failures=failures;write_report("plan.json",p);quit(failures);return
	if "--natural-post" in OS.get_cmdline_user_args():
		var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"))
		var publication:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/town_props_20261006/published.json"))
		var entry:Dictionary=publication.items.filter(func(i):return i.id=="town_festival_posts_POST_natural")[0].entry
		var loaded:=Library.read(entry);check(loaded.ok,"published natural wood pillar")
		if not loaded.ok:quit(1);return
		for prop_:Dictionary in p.props:
			if prop_.source!="reference_POST_rose":continue
			var r:Dictionary=p.records.filter(func(v):return v.uuid==prop_.id)[0]
			check(equivalent(r.bounds_size,loaded.records[0].bounds_size),"same pillar geometry bounds")
			r.asset_path=loaded.records[0].asset_path;r.label=entry.label;r.editor_group_name="东南桥彩旗街 · "+entry.label
			prop_.source="town_festival_posts_POST_natural"
		p.failures=failures;write_report("plan.json",p);quit(failures);return
	if "--publish" in OS.get_cmdline_user_args():
		var r:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/result.json"));var v:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/runtime_result.json"))
		check(r.failures==0 and v.failures==0 and v.candidate_sha256==r.candidate_sha256,"reviewed final street")
		check(FileAccess.get_sha256(FORMAL)==r.formal_sha256 and FileAccess.get_sha256(TARGET)==r.candidate_sha256,"unchanged tested maps")
		if failures:quit(1);return
		var formal=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		formal.records=candidate.records;formal.map_meta=candidate.map_meta;formal._next=candidate._next
		check(formal.save(FORMAL)==OK,"atomic street publication")
		var reopened=Doc.open_file(FORMAL);check(reopened!=null and equivalent(reopened.records,formal.records) and equivalent(reopened.map_meta,formal.map_meta),"formal street reopens exactly")
		write_report("published.json",{"failures":failures,"sha256":FileAccess.get_sha256(FORMAL),"houses":r.houses.size(),"props":r.props.size()});quit(failures);return
	if "--save-plan" in OS.get_cmdline_user_args():
		var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"));check(p.failures==0 and FileAccess.get_sha256(FORMAL)==p.formal_sha256,"approved plan source unchanged")
		if failures:quit(1);return
		doc=Doc.open_file(FORMAL);doc.records=p.records;doc.map_meta=p.metadata;doc._next=int(p.next)
		check(doc.save(TARGET)==OK,"native candidate save");var reopen=Doc.open_file(TARGET)
		check(reopen!=null and equivalent(reopen.records,doc.records) and equivalent(reopen.map_meta,doc.map_meta) and reopen.missing_assets().is_empty(),"candidate save reopen with dependencies")
		p.erase("records");p.erase("metadata");p.failures=failures;p.candidate_sha256=FileAccess.get_sha256(TARGET);write_report("result.json",p);quit(failures);return
	var baseline:=FileAccess.get_sha256(FORMAL);var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras
	doc=Doc.new();doc.records=extras.rmmo_records;doc.map_meta=extras.duplicate(true);doc.map_meta.erase("rmmo_records")
	# Freeze the palette source before adding houses, retaining the accepted warm roof.
	source=Doc.new();source.records=doc.records.duplicate(true);source.map_meta=doc.map_meta.duplicate(true)
	doc._next=200000
	var original:Array=doc.records.duplicate(true);var original_meta:Dictionary=doc.map_meta.duplicate(true)
	var publication:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/town_props_20261006/published.json"))
	for item:Dictionary in publication.items:props[item.id]=item.entry
	var library:=Assets.new("D:/code/rmmo_runtime/packs/default/assets")
	for row:Dictionary in library.entries:
		if row.label=="写实阔叶橡树·宽冠粗干":props.oak=row
		if row.label=="写实路缘边石·直线A·3米":props.curb=row
		if row.label=="写实踏步石·A":props.steps=row
	for key in ["oak","curb","steps"]:check(props.has(key),"new published component "+key)
	var assets:=Assets.new(TARGET.get_base_dir()+"/assets")
	var art:="D:/code/rmmo_runtime/art_sources/bridge_reference_scene_20261006/"
	for spec:Array in [["reference_long_bunting","bridge_single_span_nine_flags.glb","桥头九面长旗"],["reference_POST_green","festival_post_green.glb","绿色金丝带彩柱"],["reference_POST_rose","festival_post_rose.glb","玫红金丝带彩柱"]]:
		var existing:Array=assets.entries.filter(func(e):return e.get("label","")==spec[2] and e.has("prefab_path"))
		if not existing.is_empty():props[spec[0]]=existing[0];continue
		var imported:=assets.import_file(art+spec[1]);check(imported.ok,"existing revised flag model")
		if not imported.ok:quit(1);return
		var temp:=Doc.new();var id:String=temp.add_asset(imported.entry,Vector3.ZERO)
		if spec[0].ends_with("bunting"):temp._find(id).collision="none"
		var captured:=Library.capture(temp.records,assets,spec[2]);check(captured.ok,"flag prefab");props[spec[0]]=captured.entry
	for n:Dictionary in doc.map_meta.editor_layout.roads.nodes:nodes[n.id]=B.vec(n.position)
	for id in ["e_8c02b3753c1cd333","e_ce8f7d760ac57ca4","e_3e6fd355431564f8"]:edges.append(doc.map_meta.editor_layout.roads.edges.filter(func(e):return e.id==id)[0])
	doc.checkpoint_recovery()
	var samples:Array=["building_cf4b040225194dae436a","building_10e2848ee287d056ac56","building_942f562c95ac95892a18","building_022e329edecce73ebbbc","building_d7f12ee3e3ef99a607db","building_3dcf25fc1f0a02b31bf2","building_814bb1d9340b268d1353"]
	for side in [-1,1]:
		for edge in 2:
			var slots:Array=[.13,.33,.53,.73,.92] if edge==0 else [.11,.29,.47,.65,.83]
			for i in slots.size():
				if side==1 and edge==0 and i==0:continue
				var sample:String=samples[2] if side==1 and edge==0 and i==1 else samples[(i+edge*3+(2 if side==1 else 0))%samples.size()]
				house(sample,edge,slots[i],side,2.2)
		for i in 3:house(samples[(i*2+1)%samples.size()],1,.2+i*.28,side,22.0)
		for i in 3:house(samples[(i+2)%samples.size()],2,.52+i*.15,side,2.2)
	check(houses.size()>=18,"dense frontage with rear row")
	festival(0,.17);festival(0,.43,true)
	for h:Dictionary in houses:
		var p:Dictionary=doc.map_meta.building_instances[h.id].parameters;var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw));var at:=B.vec(h.position)
		prop("small_wall_lantern",at+basis*Vector3(1.8,2.35,-p.depth/2-.08),h.yaw)
		if h.rear:continue
		var plan:Dictionary=B.generate(p)
		seated("town_planters_02_window_flowers",at+basis*Vector3(-p.width/2-1.016,0,plan.rooms[0].center[2]),h.yaw+90,Vector3(.7,.85,.7))
	# Place curbs in short runs; entrances and junctions stay open.
	for edge in 2:
		for side in [-1,1]:
			for i in 18:
				var t:float=.08+i*.047
				if houses.any(func(h):return not h.rear and h.edge==edge and h.side==side and absf(h.t-t)<.038):continue
				var f:=road_frame(edge,t);var at:Vector3=f.point+f.right*5.22*side;at.y=ground(doc,at)-.065
				prop("curb",at,rad_to_deg(atan2(-f.forward.z,f.forward.x)))
	# First finish obstructions for ground props, then add deliberately overhanging canopy.
	clear_passages()
	# A doorway needs a broad, continuous route to the street, not just a
	# non-intersecting door leaf. Cut whole curb modules at every entrance.
	for h:Dictionary in houses:
		var params:Dictionary=doc.map_meta.building_instances[h.id].parameters
		var entry:=B.vec(B.generate(params).entrance)
		var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(h.yaw)),B.vec(h.position))
		for item:Dictionary in additions.duplicate():
			if item.source!="curb":continue
			var r:Dictionary=doc._find(item.id);var bounds:=Geometry.bounds([r]);var local:=pose.affine_inverse()*bounds
			var approach:=AABB(Vector3(entry.x-1.8,-1,entry.z-3),Vector3(3.6,3,4.2))
			if not local.intersects(approach):continue
			doc.records=doc.records.filter(func(v):return v.uuid!=item.id);additions.erase(item)
			omitted.append({"source":"curb","reason":"door approach","house":h.id})
	check(additions.filter(func(p):return p.source.contains("POST_")).size()==4,"four unobstructing supports for two flag spans")
	var f:=road_frame(0,.01);var yaw:=rad_to_deg(atan2(-f.right.z,f.right.x))
	seated("oak",f.point+f.right*18+f.forward*10,18,Vector3.ONE*1.2)
	seated("oak",road_frame(1,.45).point-road_frame(1,.45).right*34,-37,Vector3.ONE*.95)
	for side in [-1,1]:
		for i in 3:seated("bridge_street_kit_08_low_garden_wall",f.point+f.right*side*(10+i*3.05)+f.forward*(7 if side==1 else -1.5),yaw)
	seated("bridge_street_kit_10_laundry_line",f.point+f.right*25+f.forward*9,yaw)
	seated("bridge_street_kit_12_natural_boxwood_shrub",f.point-f.right*18+f.forward*2,35)
	check(equivalent(original,doc.records.slice(0,original.size())),"all existing terrain grass roof and buildings preserved")
	check(B.valid_ownership(doc.map_meta,doc.records),"floor roof and fixture identities preserved")
	var final:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original) and equivalent(doc.map_meta,original_meta),"single content undo")
	check(doc.redo() and equivalent(doc.records,final) and equivalent(doc.map_meta,meta),"single content redo")
	write_report("plan.json",{"failures":failures,"formal_sha256":baseline,"records":doc.records,"metadata":doc.map_meta,"next":doc._next,"houses":houses,"props":additions,"omitted":omitted,"bridge_id":"stone_e_0be972769041dbc9"})
	print("FINISH_PLAN houses=",houses.size()," props=",additions.size()," failures=",failures);quit(failures)
