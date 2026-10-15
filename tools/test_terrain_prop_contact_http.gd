extends "res://tools/test_world3d_mcp.gd"
const Contact=preload("res://scripts/world_editor/terrain_prop_contact.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const GRASS="D:/code/rmmo_runtime/packs/default/assets/2abd3fe0f222d1e7cf69fa26eb5a6f05e21aca2cf041beb7301bd1847bd16c15.glb"

func ground(id:String,x:float,columns:int=8)->Dictionary:
	var heights:Array=[];heights.resize((columns+1)*9);heights.fill(.0008420944)
	var holes:Array=[];holes.resize(columns*8);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[x,0.,0.],"rotation":[0,0,0],"size":[8.,1.,8.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":columns,"rows":8,"floor":-8.,"heights":heights,"holes":holes}}
func grass()->Dictionary:
	return {"uuid":"grass","kind":"asset","asset_path":GRASS,"position":[0.,-.012,0.],"rotation":[.02634677,37.,-.01269593],"size":[1.,1.,1.],"bounds_position":[-.6126859188,0.,-.4965668917],"bounds_size":[1.136713386,.3813814521,.9668563604],"collision":"none"}
func flatten(y:float)->Dictionary:
	return {"id":"west","mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":4.,"plot_depth":4.,"blend_margin":1.,"target_height":y,"strength":1.,"cross_tiles":true}
func rejected(args:Dictionary,label:String)->void:
	var before:Dictionary=editor._doc.recovery_snapshot();var undo:int=editor._doc._undo.size()
	var response:=await call_tool("sculpt_terrain",args,false)
	check(response.get("conflicts",[]).has("grass"),label+" identifies the protected prop")
	check(equivalent(before,editor._doc.recovery_snapshot()) and undo==editor._doc._undo.size(),label+" has no document/history side effects")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory:=Paths.cache_directory("terrain_prop_contact_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc=Doc.new();doc.records=[ground("west",-4.),ground("east",4.,16),grass()]
	check(FileAccess.file_exists(GRASS) and doc.save(path)==OK,"real authored grass fixture and mixed-resolution seam saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32180
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real contact HTTP listens on loopback")
	var discovery:=await rpc("tools/list");check(discovery.get("result",{}).get("tools",[]).any(func(t):return t.name=="sculpt_terrain"),"current 3D sculpt tool discovered")
	var baseline:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var response:=await call_tool("sculpt_terrain",flatten(0.))
	var after:Dictionary=editor._doc.recovery_snapshot()
	check(response.get("changed_ids",[]).has("west") and response.get("changed_ids",[]).has("east"),"12 mm embedded roots tolerate 0.842 mm lowering across both terrain tiles")
	check(equivalent(baseline.records[2],after.records[2]) and editor._doc._undo.size()==history+1,"prop pose is unchanged and both tiles use one transaction")
	await call_tool("undo");check(equivalent(baseline.records,editor._doc.records),"undo restores both terrain surfaces and original root contact")
	await call_tool("redo");check(equivalent(after.records,editor._doc.records),"redo restores exact contact-preserving result")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(after.records,editor._doc.records),"native save and reopen preserve grass and terrain")
	for state in ["visible","locked","hidden"]:
		editor._doc.apply_recovery(baseline)
		var prop:Dictionary=editor._doc._find("grass")
		if state=="locked":prop.editor_locked=true
		if state=="hidden":prop.editor_hidden=true
		await call_tool("sculpt_terrain",flatten(0.))
		await rejected(flatten(-.04),state+" real root support loss")
		await rejected(flatten(.03),state+" deeper root burial")
		await rejected({"id":"west","mode":"hole","points":[[0.,0.]],"radius":1.5,"cross_tiles":true},state+" hole under roots")
	# World-transformed source bounds, not an axis-aligned bottom or center probe.
	editor._doc.apply_recovery(baseline)
	var prop:Dictionary=editor._doc._find("grass");prop.size=[1.7,.8,1.4];prop.rotation=[.044,119.,-.0127]
	await call_tool("sculpt_terrain",flatten(0.));await rejected(flatten(-.04),"scaled rotated authored bounds")
	editor._doc.apply_recovery(baseline)
	prop=editor._doc._find("grass");prop.erase("asset_path");prop.erase("bounds_position");prop.erase("bounds_size");prop.kind="box";prop.surface_id="wood";prop.color=[.4,.3,.2];prop.size=[2.,1.,2.];prop.rotation=[0.,29.,20.]
	var basis:=Basis.from_euler(Geometry.vector(prop,"rotation")*PI/180);var low:=INF
	for point:Vector3 in Geometry.corners(prop):low=minf(low,point.y)
	prop.position[1]-=low # Only the low toe touches; the center is above ground.
	var toe:=Vector3.ZERO;low=INF
	for point:Vector3 in Geometry.corners(prop):
		if point.y<low:low=point.y;toe=point
	check(float(prop.position[1])-toe.y>.2,"inclined fixture touches away from its elevated center")
	await rejected({"id":"west","mode":"flatten","points":[[toe.x,toe.z]],"radius":1.6,"hardness":1.,"strength":1.,"target_height":-.04,"cross_tiles":true},"inclined toe contact away from object center")
	# Repeated small strokes cannot bypass the absolute contact threshold.
	editor._doc.apply_recovery(baseline);prop=editor._doc._find("grass");prop.rotation=[0.,37.,0.];prop.position[1]=0.
	await call_tool("sculpt_terrain",flatten(-.004));await rejected(flatten(-.008),"cumulative millimetre support removal")
	# Reserved/complex geometry does not opt into ordinary-prop refinement.
	var complex:=grass();complex.terrain_grade=[.1,0.]
	check(Contact.lower_faces(complex).is_empty(),"graded/generator shapes retain conservative structural protection")
	complex=grass();complex.rotation=[90.,37.,0.]
	check(Contact.lower_faces(complex).is_empty(),"side-lying bounds with numerically near-vertical authored base remain conservative")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_PROP_CONTACT_HTTP ",directory," failures=",failed);quit(1 if failed else 0)
