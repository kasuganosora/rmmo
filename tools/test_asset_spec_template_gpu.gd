extends SceneTree
const Template=preload("res://scripts/world3d/asset_spec_template.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Cursor=preload("res://scripts/world3d/instance_spec_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
var checks:=0
var failures:=0
var timings:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func same(a:Variant,b:Variant)->bool:
	# Native getters return a typed null Object; dictionary-only projections use
	# NIL. Both mean no material, including to the renderer and cache key code.
	if a==null or b==null:return a==null and b==null
	if typeof(a)!=typeof(b):return false
	if a is Transform3D or a is Vector3 or a is AABB:return a.is_equal_approx(b)
	if a is float:return is_equal_approx(a,b)
	if a is Dictionary:
		if a.size()!=b.size():return false
		for k in a:
			if not b.has(k) or not same(a[k],b[k]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	return a==b
static func prepared(packed:PackedScene)->void:
	var state:=packed.get_state();var seen:Dictionary={}
	for i in state.get_node_count():
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i,j)!=&"mesh":continue
			var mesh:Mesh=state.get_node_property_value(i,j)
			if seen.has(mesh):continue
			seen[mesh]=true
			if mesh.has_meta(Native.META):Native._bind_geometry(mesh)
			else:Cpu.capture(mesh)
	packed.set_meta("compiled_asset_validated",true);packed.set_meta("white_native_geometry",true)
	packed.set_meta(Template.META,Template.compile(packed))
func compare(packed:PackedScene,name_:String,record:Dictionary)->void:
	check(Template.supports(packed,record),name_+": descriptor supports the record")
	if not Template.supports(packed,record):return
	var start:=Time.get_ticks_usec();var doc:=Doc.new()
	var holder:Node3D=doc._asset(record,{"template":packed})
	var old:=Cursor.new();old.begin(holder,false,123*65536);old.advance(0)
	var old_us:=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec();var projection:=Template.new();projection.begin(packed,record,123*65536);projection.advance(0)
	var new_us:=Time.get_ticks_usec()-start
	var equal:=same(old.specs,projection.specs)
	if not equal:
		for i in mini(old.specs.size(),projection.specs.size()):
			if not same(old.specs[i],projection.specs[i]):
				for k in old.specs[i]:
					if not projection.specs[i].has(k) or not same(old.specs[i][k],projection.specs[i].get(k)):print("MISMATCH ",i," ",k," old=",old.specs[i][k]," new=",projection.specs[i].get(k))
				break
	check(equal,name_+": all specs match geometry owners, bounds, hierarchy, fixtures, lights, batch and floor/roof metadata")
	timings.append({"name":name_,"parts":old.specs.size(),"graph_us":old_us,"projection_us":new_us,"temporary_nodes":packed.get_state().get_node_count()+1,"new_nodes":0})
	var sliced:=Template.new();sliced.begin(packed,record,123*65536)
	while not sliced.advance(100):await process_frame
	check(same(sliced.specs,projection.specs),name_+": sliced output and ordering match uninterrupted pure preparation")
	var thread:=Thread.new();var worker:=Template.new();worker.begin(packed,record,123*65536)
	thread.start(func():worker.advance(0))
	while thread.is_alive():await process_frame
	thread.wait_to_finish()
	check(same(worker.specs,projection.specs),name_+": worker projection is identical without shared mutations")
	var independent:=true
	for i:int in projection.specs.size():
		var spec:Dictionary=projection.specs[i]
		var other:Dictionary=worker.specs[i]
		independent=independent and not is_same(spec.surface_overrides,other.surface_overrides)
		var count:int=other.surface_overrides.size();spec.surface_overrides.append(null)
		independent=independent and other.surface_overrides.size()==count
		if spec.extras.has("fixture") and spec.has("ground_batch_record"):
			var batch_fixture:Dictionary=spec.ground_batch_record.fixture
			var before:=batch_fixture.duplicate(true);var other_before:Dictionary=other.extras.fixture.duplicate(true)
			independent=independent and not is_same(spec.extras.fixture,batch_fixture)
			spec.extras.fixture.open=.123;spec.extras.fixture.pivot[0]+=7
			independent=independent and same(before,batch_fixture) and same(other_before,other.extras.fixture)
	check(independent,name_+": runtime overrides and nested fixture writes cannot alter batch or sibling owners")
	var fresh:=Template.new();fresh.begin(packed,record,123*65536);fresh.advance(0)
	check(same(fresh.specs,worker.specs),name_+": runtime mutations cannot change the immutable model description")
	var cancelled:=Template.new();cancelled.begin(packed,record,0);cancelled.advance(1);cancelled.dispose()
	check(cancelled.template.is_empty() and cancelled.specs.is_empty() and cancelled.adapted.is_empty(),name_+": cancellation drops private work and owners")
func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var base:="D:/code/rmmo_runtime/cache/world3d/white_native_assets_v1"
	# Existing immutable native products include the actual 2,151-part building,
	# generic houses, nested owners, architectural hinges and light sockets.
	for key:String in ["3ecafd6e86b1daa421b6bd21a20cb102deed3e7ced4c14c47f44b680c9c32576","317189e5320043ab7bdae2597e0a93255df7eecc6460a20d59e0857b3fd9c4b7","92b7f4f1000dae6b2782cac36ce3cebbb1a1a4552cafd8bc92bcc3985913cb45","0107bcadbbd444c47d0b5086e0ae6af2beef20fd3f175d54adcddd5ccaf1de8c"]:
		var info:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base.path_join(key+".json")))
		var packed:=ResourceLoader.load(base.path_join(info.payload_sha+".scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		prepared(packed)
		for mode:String in ["","none","walk"]:
			var record:Dictionary={"uuid":"test_"+mode,"kind":"asset","position":[112,1,-72],"rotation":[13,34,-7],"size":[1.2,.8,.9],"collision":mode}
			await compare(packed,key.left(8)+mode,record)
		var record:Dictionary={"uuid":"test_states","kind":"asset","position":[-12,0,19],"rotation":[0,92,0],"size":[.8,1.3,1.2],"model_component_states":{},"model_building_states":{}}
		var description:Dictionary=packed.get_meta(Template.META)
		for row:Dictionary in description.get("rows",[]):
			if row.extra.get("rmmo_hinge") is Dictionary:
				record.model_component_states[row.owner_path+":"+row.extra.rmmo_hinge.id]=.73
				record.model_building_states[row.extra.rmmo_hinge.id]=.73
			if row.mesh!=null and row.hinge_owner>=0:
				var owner:Dictionary=description.rows[row.hinge_owner]
				if owner.extra.has("door_hinge"):
					record.model_component_states[row.owner_path+":architecture:"+owner.path]=.73
		await compare(packed,key.left(8)+"states",record)
		for field:String in ["wind_response","parametric_tree","tree_settings","banner","vegetation_batch"]:
			var unsupported:=record.duplicate(true);unsupported[field]={}
			check(not Template.supports(packed,unsupported),field+": preserves graph fallback")
	print("ASSET_SPEC_TEMPLATE ",JSON.stringify({"checks":checks,"failures":failures,"timings":timings}))
	quit(1 if failures else 0)
