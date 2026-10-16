extends "res://tools/test_world3d_mcp.gd"
const Data=preload("res://scripts/world3d/city_layout.gd")
const Fort=preload("res://scripts/world_editor/fortification_tools.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Access=preload("res://scripts/world3d/fortification_access.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var directory:String
var proof:Dictionary={"negative_cases":{}}
func water()->Dictionary:
	return {"uuid":"river_liquid","kind":"box","surface_id":"water","collision":"none","position":[0,2.99,0],"rotation":[0,0,0],"size":[12,.02,30],"color":[.13,.27,.31],"channel_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[0,2.99,0]}}
func setup()->RefCounted:
	var doc:=Doc.new()
	doc.add_box("grass",Vector3(-18,3.75,0),Vector3(24,.5,40))
	doc.add_box("grass",Vector3(18,3.75,0),Vector3(24,.5,40))
	var bed:String=doc.add_box("river_bed",Vector3(0,-.25,0),Vector3(12,.5,40));doc._find(bed).uuid="bed"
	doc.records.append(water());return doc
func recipe()->Dictionary:
	return {"id":"water_surface_test","points":[[-18,0],[18,0]],"base_height":4.,"height":7.5,"thickness":3.5,"foundation":1.5,"style":"plain","corner_towers":false,"battlements":false,"wall_access":false,"arrow_slits":false,"tower_layout":"manual","gates":[{"id":"water_opening","kind":"water","segment":0,"t":.5,"width":12.,"height":5.,"water_depth":4.,"grille":true,"open":0.}]}
func reject_unchanged(args:Dictionary,label_:String)->void:
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var rejected:=await call_tool("generate_fortification",args,false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==history,label_+" failure is atomic")
	proof.negative_cases[label_]=rejected
func restore(snapshot:Dictionary)->void:
	editor._doc.apply_recovery(snapshot);editor._city.refresh()
func unit_boundaries(settings:Dictionary)->void:
	var full:Dictionary=F.defaults().merged(settings,true);var built:=Plan.new().build(full)
	check(built.ok,"small native watergate geometry builds")
	if not built.ok:return
	var opening:Dictionary={"gate":settings.gates[0],"polygon":Access.rectangle(Vector2.ZERO,Vector2.RIGHT,-6.,6.,3.6)}
	var parts:Array=built.records.filter(func(r):return str(r.fortification.part).begins_with("water_pier_") or str(r.fortification.part).begins_with("water_grille_") or str(r.fortification.part).begins_with("water_hinge_"))
	check(not parts.is_empty() and parts.all(func(r):return not Fort.water_contact(r,[opening]).is_empty()),"piers, outer grilles and endpoint hinges fit water contact envelope")
	for amount:float in [.4,1.]:
		var changed:Array=parts.duplicate(true)
		for r:Dictionary in changed:
			if r.has("fixture"):r.fixture.open=amount
		check(changed.all(func(r):return not Fort.water_contact(r,[opening]).is_empty()),"contact matching uses closed attachment independent of gate open="+str(amount))
	var turned:Array=parts.duplicate(true);var turn:=Basis(Vector3.UP,deg_to_rad(37.));var rotated:Dictionary=opening.duplicate(true)
	rotated.polygon=PackedVector2Array()
	for p:Vector2 in opening.polygon:rotated.polygon.append(p.rotated(deg_to_rad(-37.)))
	for r:Dictionary in turned:
		r.position=Data.xyz(turn*Data.vec(r.position));r.rotation[1]+=37.
	check(turned.all(func(r):return not Fort.water_contact(r,[rotated]).is_empty()),"rotated opening keeps outer hardware and jamb matching")
	var example:Dictionary=parts[0].duplicate(true);example.position[0]+=30.
	check(Fort.water_contact(example,[opening]).is_empty(),"matching name outside the actual opening is rejected")
	example=parts[0].duplicate(true);example.fortification.part="water_pier_unrelated_0"
	check(Fort.water_contact(example,[opening]).is_empty(),"unrelated watergate part is rejected")
	example=parts[0].duplicate(true);example.fortification.part="wall_0"
	check(Fort.water_contact(example,[opening]).is_empty(),"ordinary curtain has no liquid overlap exemption")
	for invalid:Dictionary in [{"collision":"block"},{"surface_id":"river_bed"},{"channel_clearance":.1},{"size":[12,1.,30]},{"rotation":[10,0,0]}]:
		check(not Fort.water_surface(water().merged(invalid,true)),"water source semantic guard "+str(invalid))
	var no_channel:Dictionary=water();no_channel.erase("channel_mesh")
	check(not Fort.water_surface(no_channel),"ordinary water-painted box is not liquid geometry")
	for level:float in [-.2,4.2]:
		var outside:Dictionary=water();outside.position[1]=level
		check(Foot.record_shapes(outside).all(func(s):return not Fort.water_contact_height(opening,s,4.)),"actual liquid polygon lies outside local gate depth "+str(level))
	var local:Dictionary=opening.duplicate(true);local.gate.base_height=8.;var raised:Dictionary=water();raised.position[1]=6.99
	check(Foot.record_shapes(raised).all(func(s):return Fort.water_contact_height(local,s,0.) and not Fort.water_contact_height(opening,s,4.)),"independent watergate bank datum is used")
func run()->void:
	create_timer(420).timeout.connect(func():check(false,"water contact timeout");finish())
	rpc_timeout_ms=180000;directory=Paths.cache_directory("water_surface_http_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var initial:=setup();check(initial.save(path)==OK,"isolated water contact fixture saves")
	var settings:=recipe();unit_boundaries(settings)
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32620
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"current 3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="preview_fortification") and definitions.any(func(t):return t.name=="generate_fortification"),"existing 3D watergate tools discovered without schema change")
	var original:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var preview:=await call_tool("preview_fortification",settings)
	check(equivalent(original,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"liquid-aware preview has no side effects")
	if not preview.ok:finish();return
	check(editor._fortifications.summary(settings).ok,"UI and MCP share the same liquid-aware planner")
	for mutation:Dictionary in [{"collision":"block"},{"channel_clearance":1.},{"surface_id":"block"}]:
		editor._doc._find("river_liquid").merge(mutation,true);await reject_unchanged(settings,str(mutation));restore(original)
	var solid:String=editor._doc.add_box("block",Vector3(0,3,0),Vector3(.5,1,.5))
	await reject_unchanged(settings,"solid object at submerged pier");restore(original)
	var outside:Dictionary=water();outside.uuid="liquid_outside_gate";outside.position=[10,2.99,0];outside.size=[2,.02,8];editor._doc.records.append(outside)
	await reject_unchanged(settings,"ordinary wall still conflicts with liquid outside opening");restore(original)
	var short:Dictionary=settings.duplicate(true);short.gates[0].water_depth=2.
	await reject_unchanged(short,"short pier cannot use water as riverbed support");restore(original)
	var data:Dictionary=Data.resolve(editor._doc.map_meta);data.roads={"nodes":[{"id":"a","position":[0,3,-12]},{"id":"b","position":[0,3,12]}],"edges":[{"id":"protected_road","from":"a","to":"b","kind":"ground","width_start":2.,"width_end":2.}]};editor._doc.map_meta.editor_layout=data;editor._city.refresh()
	await reject_unchanged(settings,"road clearance through pier stays protected");restore(original)
	var ready:=await call_tool("preview_fortification",settings)
	history=editor._doc._undo.size()
	var made:=await call_tool("generate_fortification",settings.merged({"plan_token":ready.plan_token}))
	if not made.ok:finish();return
	check(editor._doc._undo.size()==history+1,"watergate generation is one transaction")
	var after:Dictionary=editor._doc.recovery_snapshot();await call_tool("undo");check(equivalent(original.records,editor._doc.records) and equivalent(original.map_meta,editor._doc.map_meta),"undo restores exact original banks bed and water")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores all native components")
	for amount:float in [.4,1.]:
		await call_tool("set_fortification_gate",{"id":settings.id,"gate_id":"water_opening","open":amount})
		check(editor._fortifications.regions()[0].settings.gates[0].open==amount,"native gate operation over water remains editable")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"watergate and unmodified river save and reopen")
	check(equivalent(original.records.filter(func(r):return r.uuid=="river_liquid")[0],editor._doc._find("river_liquid")),"water record identity and geometry remain unchanged")
	proof.map=path;proof.map_sha256=FileAccess.get_sha256(path);finish()
func finish()->void:
	proof.failures=failed;proof.status="passed" if failed==0 else "failed";proof.scope="isolated native fixture, real current 3D HTTP; no formal/candidate write or GPU review"
	FileAccess.open(OUT+"/watergate_surface_contact_http.json",FileAccess.WRITE).store_string(JSON.stringify(proof,"\t"))
	if is_instance_valid(editor):editor._mcp.stop();editor.queue_free()
	await settle();print("WATER_SURFACE_HTTP_FINISHED failures=",failed);quit(failed)
