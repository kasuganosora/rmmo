extends SceneTree
## Real old/new sharing, property policy, renderer lifetime and library integration.
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
const Fast=preload("res://scripts/world3d/model_texture_runtime.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var failures:Array[String]=[]
var checks:=0
var report:=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL "+label)
func texture(kind:String="")->Texture2D:
	var pixels:=Image.create(2,2,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.4,.6,1))
	var value:=ImageTexture.create_from_image(pixels);value.set_meta(Cache.PIXEL_KEY,Cache.pixel_key(pixels))
	if kind=="bad":value.set_meta(Cache.PIXEL_KEY,"invalid")
	if kind=="local":value.resource_local_to_scene=true
	if kind=="author":value.set_meta("author","retain")
	return value
func graph()->Dictionary:
	var scene:=Node3D.new();var source:=texture();var seed:=texture()
	var bad:=texture("bad");var local:=texture("local");var author:=texture("author")
	var mats:Array[StandardMaterial3D]=[]
	for i:int in 120:
		var mat:=StandardMaterial3D.new();mat.albedo_texture=source
		mat.normal_enabled=true;mat.normal_texture=source
		mat.shading_mode=i%3;mat.set_flag(BaseMaterial3D.FLAG_SUBSURFACE_MODE_SKIN,i%2==0)
		mat.roughness=float(i%10)/10.;mat.set_meta("shared",source);mat.set_meta("bad",bad)
		mat.set_meta("local",local);mat.set_meta("author",author);mat.set_meta("scalar",i)
		mats.append(mat)
	for i:int in range(0,120,2):mats[i].next_pass=mats[i+1]
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP]);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,mats[0])
	for i:int in 2000:
		var node:=MeshInstance3D.new();node.mesh=mesh;node.set_surface_override_material(0,mats[i%120]);scene.add_child(node);node.owner=scene
		if i%3==0:node.material_override=mats[(i+1)%120]
		if i%5==0:node.material_overlay=mats[(i+2)%120]
	return {"scene":scene,"source":source,"seed":seed,"bad":bad,"local":local,"author":author,"mats":mats}
func state(g:Dictionary)->Array:
	var result:Array=[]
	for mat:StandardMaterial3D in g.mats:
		var row:Dictionary={}
		for info:Dictionary in mat.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			var value:Variant=mat.get(info.name)
			if value is Texture2D:
				var identity:="unknown"
				for key:String in ["source","seed","bad","local","author"]:
					if value==g[key]:identity=key
				row[info.name]=identity
			elif value is Material:row[info.name]="material"
			else:row[info.name]=value
		result.append(row)
	return result
func release(g:Dictionary)->void:
	var refs:Array=[]
	for key:String in ["source","seed","bad","local","author"]:refs.append(weakref(g[key]))
	Drainer.dispose_scene(g.scene);g.clear();Cache._textures.clear();Drainer.synchronize_transfer()
	for ref:WeakRef in refs:check(ref.get_ref()==null,"no texture retained after graph release")
func compare_run(fast:bool)->Dictionary:
	var g:=graph();Cache._textures.clear();Cache._remember(g.seed.get_meta(Cache.PIXEL_KEY),g.seed)
	var began:=Time.get_ticks_usec()
	if fast:Fast.apply(g.scene)
	else:Cache.apply(g.scene)
	var elapsed:=Time.get_ticks_usec()-began;var snapshot:=state(g);release(g)
	return {"elapsed_us":elapsed,"state":snapshot}
func expected_names(mat:StandardMaterial3D)->Array[StringName]:
	var result:Array[StringName]=[]
	for info:Dictionary in mat.get_property_list():
		if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
		if int(info.type)==TYPE_OBJECT or int(info.type)==TYPE_NIL or str(info.name).begins_with("metadata/"):result.append(info.name)
	return result
func policy_cases()->void:
	Fast._native_properties.clear()
	for shading:int in 3:
		for skin:bool in [false,true]:
			var mat:=StandardMaterial3D.new();mat.shading_mode=shading;mat.set_flag(BaseMaterial3D.FLAG_SUBSURFACE_MODE_SKIN,skin)
			mat.set_meta("different_each_instance_%d"%shading,texture());mat.set_meta("scalar",17)
			check(Fast._properties(mat)==expected_names(mat),"initial policy/order equals engine property list")
			for feature:int in BaseMaterial3D.FEATURE_MAX:
				mat.set_feature(feature,true)
				check(Fast._properties(mat)==expected_names(mat),"enabled feature retains exact storage properties")
				mat.set_feature(feature,false)
			for flag:int in BaseMaterial3D.FLAG_MAX:
				var previous:=mat.get_flag(flag);mat.set_flag(flag,not previous)
				check(Fast._properties(mat)==expected_names(mat),"flag retains exact storage properties")
				mat.set_flag(flag,previous)
			for mode:int in BaseMaterial3D.TRANSPARENCY_MAX:
				mat.transparency=mode
				check(Fast._properties(mat)==expected_names(mat),"transparency retains exact storage properties")
	check(Fast._native_properties.size()==6,"six native texture storage policies, no per-material cache growth")
	var scripted:=GDScript.new()
	scripted.source_code="extends StandardMaterial3D\nvar held:Texture2D\nvar reads:int=0\nfunc _get_property_list()->Array[Dictionary]:\n\treturn [{\"name\":\"dynamic_value\",\"type\":TYPE_INT,\"usage\":PROPERTY_USAGE_STORAGE},{\"name\":\"variant_value\",\"type\":TYPE_NIL,\"usage\":PROPERTY_USAGE_STORAGE}]\nfunc _get(name:StringName)->Variant:\n\tif name in [&\"dynamic_value\",&\"variant_value\"]:reads+=1;return held\n\treturn null\nfunc _set(name:StringName,value:Variant)->bool:\n\tif name in [&\"dynamic_value\",&\"variant_value\"]:held=value;return true\n\treturn false\n"
	check(scripted.reload()==OK,"custom material script parses")
	var mat:StandardMaterial3D=scripted.new();var original:=texture();mat.set("held",original)
	var expected:Array[StringName]=[]
	for info:Dictionary in mat.get_property_list():
		if int(info.usage)&PROPERTY_USAGE_STORAGE:expected.append(info.name)
	check(Fast._properties(mat)==expected,"scripted material preserves all storage getters and Variant properties")
func instrumented()->GDScript:
	var source:=FileAccess.get_file_as_string("res://scripts/world3d/model_texture_runtime.gd")
	source=source.replace("extends RefCounted","extends RefCounted\nstatic var lists:int=0\nstatic var gets:int=0\nstatic var prior:WeakRef\nstatic var pinned:bool=false\nstatic var syncs:int=0")
	source=source.replace("for info:Dictionary in material.get_property_list():","lists+=1\n\t\tfor info:Dictionary in material.get_property_list():")
	source=source.replace("var value:Variant=material.get(name)","gets+=1\n\t\t\tvar value:Variant=material.get(name)")
	source=source.replace("if changed:preload", "if changed:\n\t\tsyncs+=1\n\t\tif prior!=null:pinned=prior.get_ref()!=null\n\t\tpreload")
	var script:=GDScript.new();script.source_code=source;check(script.reload()==OK,"instrumented actual runtime source parses");return script
func old_work(scene:Node)->Dictionary:
	var old_gets:=0;var materials:=Cache._materials(scene)
	for mat:StandardMaterial3D in materials:
		for info:Dictionary in mat.get_property_list():
			if int(info.usage)&PROPERTY_USAGE_STORAGE:old_gets+=1
	return {"lists":materials.size(),"gets":old_gets}
func work_and_lifetime()->Dictionary:
	var script:=instrumented();var g:=graph();Cache._textures.clear();Cache._remember(g.seed.get_meta(Cache.PIXEL_KEY),g.seed)
	var old:=old_work(g.scene)
	# The graph and materials must not be extra owners of originals during sync.
	var original:WeakRef=weakref(g.source);g.erase("source")
	# Disabled normal slots remain owners, as in production. Use a second simple
	# scene below to prove final-reference lifetime rather than this mixed graph.
	script.call("apply",g.scene)
	var result:Dictionary={"old_lists":old.lists,"old_gets":old.gets,"new_lists":script.get("lists"),"new_gets":script.get("gets")}
	check(result.new_lists==6 and result.new_gets<old.gets/3,"actual helper reduces lists and gets")
	Drainer.dispose_scene(g.scene);g.clear();Cache._textures.clear();Drainer.synchronize_transfer()
	check(original.get_ref()==null,"mixed graph originals released after teardown")
	g=graph();var mesh:Mesh=g.scene.get_child(0).mesh;var single:=Node3D.new();var part:=MeshInstance3D.new();part.mesh=mesh;single.add_child(part)
	var material:=StandardMaterial3D.new();material.albedo_texture=texture();var seed:=texture();original=weakref(material.albedo_texture)
	mesh.surface_set_material(0,material);Drainer.dispose_scene(g.scene);g.clear()
	Cache._textures.clear();Cache._remember(seed.get_meta(Cache.PIXEL_KEY),seed)
	script.set("prior",original);script.set("syncs",0);script.call("apply",single)
	check(script.get("syncs")==1 and script.get("pinned") and original.get_ref()==null and material.albedo_texture==seed,"last original retained through exactly one synchronization then released")
	var before:int=script.get("gets");single.set_meta("rmmo_model_texture_table_v1","split");script.call("apply",single)
	check(script.get("gets")==before,"split products perform zero property gets")
	Drainer.dispose_scene(single);mesh=null;material=null;seed=null;script.set("prior",null);Cache._textures.clear();Drainer.synchronize_transfer()
	return result
func library_case()->void:
	var g:=graph();var packed:=PackedScene.new();check(packed.pack(g.scene)==OK,"native library fixture packs")
	packed.set_meta("compiled_asset_validated",true);Fast._native_properties.clear();Cache._textures.clear()
	var instance:=Library._instantiate(packed)
	check(instance!=null and packed.get_meta("compiled_grass_rebound",false) and instance.get_meta("_compiled_resource_owner")==packed,"actual library first instance preserves owner and rebound flag")
	check(Fast._native_properties.size()==6,"actual library uses optimized runtime sharing")
	var second:=Library._instantiate(packed);check(second!=null and second.get_meta("_compiled_resource_owner")==packed,"subsequent library instance retains owner")
	Drainer.dispose_scene(instance);Drainer.dispose_scene(second);packed=null;release(g)
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	if report.is_empty() or FileAccess.file_exists(report):printerr("new --report path required");quit(2);return
	policy_cases();var pairs:Array=[]
	for iteration:int in 3:
		Fast._native_properties.clear();var a:=compare_run(false);var b:=compare_run(true)
		check(a.state==b.state,"all stored material state and sharing equal, pair %d"%iteration)
		pairs.append({"old_us":a.elapsed_us,"new_us":b.elapsed_us})
	var work:=work_and_lifetime();library_case()
	var data:Dictionary={"checks":checks,"failures":failures,"pairs":pairs,"work":work,"renderer":DisplayServer.get_name(),"scope":"component only; not full-map timing or FPS"}
	var file:=FileAccess.open(report,FileAccess.WRITE);file.store_string(JSON.stringify(data,"\t"));file.close()
	print("TEXTURE_RUNTIME_RESULT "+JSON.stringify(data));quit(0 if failures.is_empty() else 1)
