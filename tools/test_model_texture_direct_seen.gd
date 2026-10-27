extends SceneTree
## Diagnostic fixture: same real ModelTextureCache helpers, private graph only.
## Two separately allocated graphs compare baseline and proposed seen-first.
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
const Direct=preload("res://scripts/world3d/model_texture_direct_seen.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const STUDY="D:/code/rmmo_runtime/review_artifacts/model_texture_seen_20261028_01"
var report_path:=""
var errors:Array[String]=[]
func _initialize()->void:call_deferred("run")
func expect(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("SEEN_FIXTURE_ERROR "+label)
func image(color:Color)->Image:
	var value:=Image.create(2,2,false,Image.FORMAT_RGBA8);value.fill(color);return value
func textured(color:Color,kind:String)->Texture2D:
	var pixels:=image(color);var result:=ImageTexture.create_from_image(pixels)
	result.set_meta(Cache.PIXEL_KEY,Cache.pixel_key(pixels))
	if kind=="invalid":result.set_meta(Cache.PIXEL_KEY,"invalid")
	if kind=="extra_meta":result.set_meta("author_identity","must-survive")
	if kind=="local":result.resource_local_to_scene=true
	return result
func fixture()->Dictionary:
	var scene:=Node3D.new();var source:=textured(Color(.2,.4,.6,1),"valid");var seed:=textured(Color(.2,.4,.6,1),"valid")
	var bad:=textured(Color(.3,.2,.1,1),"invalid");var extra:=textured(Color(.6,.5,.1,1),"extra_meta");var local:=textured(Color(.1,.8,.2,1),"local")
	var materials:Array[StandardMaterial3D]=[]
	for i:int in 120:
		var mat:=StandardMaterial3D.new();mat.albedo_texture=source;mat.normal_enabled=true;mat.normal_texture=source
		mat.roughness=float(i%10)/10.;mat.set_meta("shared_texture",source);mat.set_meta("invalid_texture",bad);mat.set_meta("author_texture",extra);mat.set_meta("local_texture",local)
		materials.append(mat)
	for i:int in range(0,120,2):materials[i].next_pass=materials[i+1]
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,materials[0])
	for i:int in 2000:
		var part:=MeshInstance3D.new();part.name="part_%d"%i;part.mesh=mesh;part.set_surface_override_material(0,materials[i%materials.size()])
		if i%3==0:part.material_override=materials[(i+1)%materials.size()]
		if i%5==0:part.material_overlay=materials[(i+2)%materials.size()]
		scene.add_child(part)
	return {"scene":scene,"mesh":mesh,"materials":materials,"source":source,"seed":seed,"bad":bad,"extra":extra,"local":local}
func apply_trial(scene:Node,fast:bool)->Dictionary:
	var stats:Dictionary={"materials":0,"properties":0,"storage_gets":0,"nontexture_gets":0,"known_nonobject_gets":0,"plain_calls":0,"key_calls":0,"seen_hits":0,"remember_calls":0,"sets":0,"sync_calls":0}
	var started:=Time.get_ticks_usec();var materials:Array=Cache._materials(scene);stats.gather_us=Time.get_ticks_usec()-started
	var seen:Dictionary={};var retired:Array[Texture2D]=[];started=Time.get_ticks_usec()
	for material:StandardMaterial3D in materials:
		stats.materials+=1
		for info:Dictionary in material.get_property_list():
			stats.properties+=1
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			stats.storage_gets+=1
			if int(info.type) not in [TYPE_OBJECT,TYPE_NIL]:stats.known_nonobject_gets+=1
			var value:Variant=material.get(info.name)
			if not value is Texture2D:stats.nontexture_gets+=1;continue
			var id:int=value.get_instance_id()
			if fast and seen.has(id):stats.seen_hits+=1
			else:
				stats.plain_calls+=1
				if not Cache._plain_texture(value):continue
				stats.key_calls+=1
				var key:Variant=value.get_meta(Cache.PIXEL_KEY,"")
				if not Cache._valid_key(key):continue
				if not seen.has(id):
					stats.remember_calls+=1;var shared:=Cache._remember(key,value)
					seen[id]={"original":value,"shared":shared}
			var shared:Texture2D=seen[id].shared
			if shared!=value:retired.append(value);stats.sets+=1;material.set(info.name,shared)
	stats.scan_us=Time.get_ticks_usec()-started
	var sync_started:=Time.get_ticks_usec()
	if not retired.is_empty():stats.sync_calls+=1;Drainer.synchronize_transfer()
	stats.sync_us=Time.get_ticks_usec()-sync_started;seen.clear();retired.clear()
	return stats
func snapshot(graph:Dictionary)->Array:
	var out:Array=[]
	for mat:StandardMaterial3D in graph.materials:
		out.append({"albedo_seed":mat.albedo_texture==graph.seed,"normal_seed":mat.normal_texture==graph.seed,"meta_seed":mat.get_meta("shared_texture")==graph.seed,
			"bad_unchanged":mat.get_meta("invalid_texture")==graph.bad,"extra_unchanged":mat.get_meta("author_texture")==graph.extra,
			"local_unchanged":mat.get_meta("local_texture")==graph.local,"next_pass":mat.next_pass!=null,"roughness":mat.roughness})
	return out
func release_graph(graph:Dictionary)->Dictionary:
	var refs:Dictionary={"scene":weakref(graph.scene),"mesh":weakref(graph.mesh),"source":weakref(graph.source),"seed":weakref(graph.seed),"bad":weakref(graph.bad),"extra":weakref(graph.extra),"local":weakref(graph.local),"material":weakref(graph.materials[0])}
	Drainer.dispose_scene(graph.scene);graph.clear();Cache._textures.clear();Drainer.synchronize_transfer();return refs
func execute(mode:int)->Dictionary:
	var graph:=fixture();Cache._textures.clear()
	var key:String=graph.seed.get_meta(Cache.PIXEL_KEY);Cache._remember(key,graph.seed)
	var stats:Dictionary={}
	if mode==2:Cache.apply(graph.scene)
	elif mode==3:Direct.apply(graph.scene)
	else:stats=apply_trial(graph.scene,mode==1)
	var state:=snapshot(graph)
	var refs:=release_graph(graph)
	return {"stats":stats,"snapshot":state,"weakrefs":refs}
func run()->void:
	if DisplayServer.get_name()=="headless":printerr("private GPU desktop required");quit(2);return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=").replace("\\","/").simplify_path()
	if not report_path.begins_with(STUDY+"/") or FileAccess.file_exists(report_path):printerr("new private report path required");quit(2);return
	var baseline:=execute(0);var candidate:=execute(1);var production:=execute(2);var direct:=execute(3)
	expect(baseline.snapshot==candidate.snapshot and baseline.snapshot==production.snapshot and baseline.snapshot==direct.snapshot,"material fields and metadata differ from real production apply/direct helper")
	for row:Dictionary in baseline.snapshot:
		expect(row.albedo_seed and row.normal_seed and row.meta_seed and row.bad_unchanged and row.extra_unchanged and row.local_unchanged,"expected texture and metadata semantics")
	expect(baseline.stats.materials==120 and candidate.stats.materials==120,"material dedup/nextpass coverage")
	expect(candidate.stats.plain_calls<baseline.stats.plain_calls and candidate.stats.key_calls<baseline.stats.key_calls,"seen-first reduces repeated identity checks")
	expect(candidate.stats.remember_calls==baseline.stats.remember_calls and candidate.stats.sets==baseline.stats.sets and candidate.stats.sync_calls==baseline.stats.sync_calls,"intern/set/synchronization work and order unchanged")
	for key:String in baseline.weakrefs:
		expect(baseline.weakrefs[key].get_ref()==null and candidate.weakrefs[key].get_ref()==null and production.weakrefs[key].get_ref()==null and direct.weakrefs[key].get_ref()==null,"resource retained after cancellation-style disposal: "+key)
	baseline.erase("weakrefs");candidate.erase("weakrefs");production.erase("weakrefs");direct.erase("weakrefs")
	var result={"baseline":baseline.stats,"candidate":candidate.stats,"errors":errors,"scope":"synthetic graph: original production apply and direct helper plus separately instrumented baseline/candidate; timing includes counters and is not production or map performance; disposal is after synchronous apply, not Deferred scheduling"}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:printerr("report write failed");quit(2);return
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("SEEN_FIXTURE_RESULT errors=",errors.size()," baseline=",JSON.stringify(baseline.stats)," candidate=",JSON.stringify(candidate.stats));quit(1 if not errors.is_empty() else 0)
