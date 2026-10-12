extends RefCounted
## Main-thread shader submission under a visible loading cover. Directory scans
## yield, but one engine Shader/Material call is explicitly indivisible. A queue
## belongs to one covered transaction and never requests additional assets.
const Response=preload("res://scripts/world3d/wind_response.gd")
const Materials=preload("res://scripts/world3d/wind_material.gd")
var _libraries:Array=[]
var _library_cursor:=0
var _spec_cursor:=0
var _slot_cursor:=0
var _spec:Dictionary={}
var _seen:Dictionary={}
var _seen_invalid:Dictionary={}
var _cancelled:=false
var _started:=Time.get_ticks_usec()
var _report:Dictionary={"receivers":0,"materials":0,"skipped":0,"reused":0,"make_ms":0.0,"max_make_ms":0.0,"scan_ms":0.0,"cpu_ms":0.0,"steps":0,"cold_variants":0,"variants":[]}

func enqueue(library:Array)->void:
	assert(Thread.is_main_thread())
	if _cancelled:return
	# Shallow snapshots retain only resources already owned by this cover. Later
	# publications may be enqueued again; shader keys deduplicate their warmup.
	_libraries.append(library.duplicate())

func has_pending()->bool:
	return not _cancelled and (_library_cursor<_libraries.size() or not _spec.is_empty())

func snapshot()->Dictionary:
	# This span includes other loading work and frame waits between our steps.
	# cpu_ms/make_ms describe our work; elapsed_ms remains a compatibility alias.
	var span:=(Time.get_ticks_usec()-_started)/1000.0
	return _report.duplicate(true).merged({"pending":has_pending(),"cancelled":_cancelled,"elapsed_ms":span,"preparation_span_ms":span,"mode":"covered_variants","blocking":true})

func cancel()->void:
	_cancelled=true;_libraries.clear();_spec={};_seen.clear();_seen_invalid.clear()

func step_covered(covered:bool,budget_usec:int=2000,max_variants:int=1)->Dictionary:
	assert(Thread.is_main_thread())
	if not covered or _cancelled or budget_usec<=0 or max_variants<=0:return snapshot()
	var started:=Time.get_ticks_usec()
	var prepared:=0
	_report.steps+=1
	while has_pending():
		var mark:=Time.get_ticks_usec()
		if _spec.is_empty():
			var library:Array=_libraries[_library_cursor]
			if _spec_cursor>=library.size():
				_libraries[_library_cursor]=[];_library_cursor+=1;_spec_cursor=0
				continue
			var candidate:Dictionary=library[_spec_cursor];_spec_cursor+=1
			var authored:Variant=candidate.get("extras",{}).get("rmmo_wind")
			if authored is Dictionary and authored.get("profile","off")!="off" and Response.Schema.validate(authored,Response.schema()).is_empty() and candidate.get("mesh")!=null:
				_spec=candidate;_slot_cursor=0;_report.receivers+=1
			_report.scan_ms+=(Time.get_ticks_usec()-mark)/1000.0
			if _spec.is_empty():
				if budget_usec>0 and Time.get_ticks_usec()-started>=budget_usec:break
				continue
			mark=Time.get_ticks_usec()
		var mesh:Mesh=_spec.mesh
		if _slot_cursor>=mesh.get_surface_count():_spec={};continue
		var source:Material=_spec.get("material_override")
		var overrides:Array=_spec.get("surface_overrides",[])
		if source==null and _slot_cursor<overrides.size():source=overrides[_slot_cursor]
		if source==null:source=mesh.surface_get_material(_slot_cursor)
		_slot_cursor+=1
		var error:=Response.material_error(source)
		var key:=""
		if error.is_empty():key=Materials.variant_key(source)
		else:
			var id:=source.get_instance_id() if source!=null else 0
			if not _seen_invalid.has(id):_seen_invalid[id]=true;_report.skipped+=1
		_report.scan_ms+=(Time.get_ticks_usec()-mark)/1000.0
		if not key.is_empty() and not _seen.has(key):
			_seen[key]=true;_report.materials+=1
			if Materials.variant_is_prepared(key):_report.reused+=1
			else:
				var timing:Dictionary={}
				var config:Dictionary=Response.defaults().merged(_spec.extras.rmmo_wind,true)
				# Warm first material/uniform use too: a Shader object alone does not
				# prove that the engine has completed this cold preparation.
				Materials.make(source,config,mesh.get_aabb(),timing)
				_report.make_ms+=timing.total_ms
				_report.max_make_ms=maxf(_report.max_make_ms,timing.total_ms)
				_report.cold_variants+=1;_report.variants.append(timing);prepared+=1
		if prepared>=maxi(1,max_variants) or (budget_usec>0 and Time.get_ticks_usec()-started>=budget_usec):break
	_report.cpu_ms+=(Time.get_ticks_usec()-started)/1000.0
	return snapshot()

func finish_covered(tree:SceneTree)->Dictionary:
	while has_pending():
		step_covered(true)
		if has_pending():await tree.process_frame
	return snapshot()

static func prepare(library:Array,tree:SceneTree)->Dictionary:
	var queue:=new()
	queue.enqueue(library)
	return await queue.finish_covered(tree)
