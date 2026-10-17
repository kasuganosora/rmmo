extends SceneTree
const Data=preload("res://scripts/world3d/city_layout.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Constraints=preload("res://scripts/world_editor/block_constraints.gd")
const Water=preload("res://scripts/world3d/waterway_plan.gd")
const W=preload("res://scripts/world3d/waterway_data.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
var checks:Array=[]
var failures:=0
func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label});if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var flat:=Doc.new();flat.add_box("ground",Vector3(-2.005,-.5,0),Vector3(3.99,1,8));flat.add_box("ground",Vector3(2.005,-.5,0),Vector3(3.99,1,8))
	check(not Constraints.flat_ground(flat,[[-3,-3],[3,-3],[3,3],[-3,3]],0.),"complete-area ground check catches narrow gap between corner samples")
	flat.add_box("ground",Vector3(0,-.5,0),Vector3(.03,1,8))
	check(Constraints.flat_ground(flat,[[-3,-3],[3,-3],[3,3],[-3,3]],0.),"adjacent native ground pieces jointly cover the region")
	check(not Constraints.flat_ground(flat,[[-3,-3],[3,-3],[3,3],[-3,3]],1.),"lower ground is not accepted as support at a higher elevation")
	var doc:=Doc.new();var id:String=doc.add_box("ground",Vector3(0,-.5,0),Vector3(200,1,200));var source:Dictionary=doc._find(id).duplicate(true)
	var s:=W.defaults().merged({"id":"bend","points":[[-30,-10],[0,-10],[25,10]],"ground_ids":[id],"width":6.,"bank_width":2.},true)
	var native:=Water.new().build(s,[source]);check(native.ok,"native bent waterway fixture builds")
	if native.ok:
		var parts:Array=[]
		for r:Dictionary in native.records:parts.append({"id":r.uuid,"role":native.roles[r.uuid],"signature":Data.token(r)})
		var layout:=Data.defaults();layout.waterways=[{"version":1,"settings":s,"sources":[source],"parts":parts}]
		doc.map_meta.editor_layout=layout;doc.records=native.records
		var before:=var_to_bytes(doc.recovery_snapshot());var result:=Constraints.collect(doc)
		check(result.ok and result.reservations.size()==1,"native river creates one complete bank envelope")
		check(var_to_bytes(doc.recovery_snapshot())==before,"collect does not mutate document or signatures")
		check(not Constraints.conflict([[-20,-14],[-18,-14],[-18,-13],[-20,-13]],0,10,result.reservations).is_empty(),"dry bank inside carving envelope is reserved too")
		check(Constraints.conflict([[-20,-20],[-18,-20],[-18,-18],[-20,-18]],0,10,result.reservations).is_empty(),"nearby dry site outside bank envelope stays available")
		for r:Dictionary in doc.records:r.editor_hidden=true
		check(Constraints.collect(doc).reservations==result.reservations,"hidden source river still protects its banks")
	var legacy_settings:=W.defaults().merged({"id":"old_bridge","points":[[-40,0],[40,0]],"ground_ids":[id],"width":6.,"bank_width":2.,"bridges":[{"id":"old","segment":0,"t":.5,"width":4.,"approach":3.,"rail_height":1.}]},true)
	var legacy:=Water.new().build(legacy_settings,[source]);check(legacy.ok,"native legacy bridge fixture builds")
	if legacy.ok:
		doc=Doc.new();doc.records=legacy.records;doc.map_meta.editor_layout=Data.defaults()
		doc.map_meta.editor_layout.waterways=[{"version":1,"settings":legacy_settings,"sources":[source],"parts":legacy.records.map(func(r):return {"id":r.uuid,"role":legacy.roles[r.uuid],"signature":Data.token(r)})}]
		var masks:=Constraints.collect(doc)
		check(masks.ok and masks.reservations.filter(func(r):return r.kind=="bridge_access").size()==2,"unchanged legacy deck reserves both bridgeheads")
		for r:Dictionary in doc.records:
			if r.get("surface_id")=="bridge_deck":r.position[0]+=10.
		check(not Constraints.collect(doc).ok,"moved legacy deck cannot silently reuse stale recipe endpoints")
	doc=Doc.new()
	var bridge:=preload("res://scripts/world_editor/bridge_tools.gd").make_record({"id":"bridge","start":[-10,0,0],"end":[10,0,0],"width":4.,"camber":0.},preload("res://scripts/world3d/bridge_data.gd").preset("stone_segmental"))
	check(preload("res://scripts/world3d/bridge_data.gd").valid(bridge),"bridge uses valid native recipe and transform")
	doc.records=[bridge]
	var result:=Constraints.collect(doc)
	check(result.ok and result.reservations.size()==2,"unbound physical bridge reserves both heads")
	check(not Constraints.conflict([[-19,-1],[-17,-1],[-17,1],[-19,1]],0,2,result.reservations).is_empty(),"bridgehead corridor extends ten metres beyond actual deck")
	check(Constraints.conflict([[-19,5],[-17,5],[-17,7],[-19,7]],0,2,result.reservations).is_empty(),"bridgehead corridor does not block unrelated flank")
	check(Constraints.conflict([[-19,-1],[-17,-1],[-17,1],[-19,1]],5,10,result.reservations).is_empty(),"vertically separate site is not rejected by low bridgehead")
	bridge.rotation=[0,90,0];bridge.position=[30,4,20];bridge.editor_hidden=true;bridge.editor_locked=true
	result=Constraints.collect(doc)
	check(not Constraints.conflict([[29,36],[31,36],[31,38],[29,38]],4,7,result.reservations).is_empty(),"rotated translated hidden bridge uses current world pose")
	var fort:=F.defaults().merged({"id":"wall","points":[[-20,0],[20,0]],"height":8.,"thickness":3.5,"corner_towers":false,"gates":[{"id":"gate","segment":0,"t":.5,"width":8.,"height":5.,"open":0.}]},true)
	var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build(fort)
	check(plan.ok,"native land gate fixture builds")
	if plan.ok:
		doc=Doc.new();doc.records=plan.records;var layout:=Data.defaults();layout.fortifications=[{"version":1,"settings":fort,"parts":plan.records.map(func(r):return {"id":r.uuid,"signature":Data.token(r)})}];doc.map_meta.editor_layout=layout
		result=Constraints.collect(doc)
		check(result.ok and result.reservations.size()==1,"actual gate hinges define one corridor")
		if result.ok:
			check(not Constraints.conflict([[-2,7],[2,7],[2,9],[-2,9]],0,6,result.reservations).is_empty(),"gate approach is protected beyond wall body")
			check(not Constraints.conflict([[-2,-9],[2,-9],[2,-7],[-2,-7]],0,6,result.reservations).is_empty(),"both sides of gate remain available for passage")
			check(Constraints.conflict([[9,7],[11,7],[11,9],[9,9]],0,6,result.reservations).is_empty(),"gate reservation does not invent tower-spacing ban")
			var before:Array=result.reservations.duplicate(true)
			for r:Dictionary in doc.records:
				if r.has("fixture"):r.fixture.open=1.
			check(Constraints.collect(doc).reservations==before,"gate open state cannot remove approach reservation")
			var frozen_manifest:Dictionary=layout.fortifications[0].duplicate(true)
			var frozen:=preload("res://scripts/world_editor/fortification_tools.gd").freeze(doc.records,frozen_manifest)
			check(frozen.ok,"native gate can be frozen through the production pipeline")
			if frozen.ok:
				var baked:=Doc.new();baked.records=frozen.records;baked.map_meta.editor_layout=Data.defaults();baked.map_meta.editor_layout.fortifications=[frozen_manifest]
				var baked_masks:=Constraints.collect(baked)
				check(baked_masks.ok and baked_masks.reservations.size()==1,"frozen gate keeps actual hinge-based approach semantics")
				if baked_masks.ok:check(baked_masks.reservations[0].polygon==before[0].polygon,"freezing gate does not alter reserved ground passage")
			doc.records=doc.records.filter(func(r):return not r.has("fixture") or r.fixture.angle>0.)
			check(not Constraints.collect(doc).ok,"missing actual gate leaf fails safely, no recipe guessed passage")
	var output:="D:/code/rmmo_runtime/review_artifacts/block_planning_20261017/reservations.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));file.close()
	print("BLOCK_RESERVATIONS checks=%d failures=%d"%[checks.size(),failures]);quit(0 if failures==0 else 1)
