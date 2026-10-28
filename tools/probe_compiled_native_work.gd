extends SceneTree
## Isolated, headless diagnostic for the full-material native cache readers.
## Fixture is synthetic, and no production cache, source or map is modified.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Reader=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const ARTIFACT_ROOT="D:/code/rmmo_runtime/review_artifacts"
var failures:Array[String]=[]
var report:Dictionary={"checks":[],"contract":"Synthetic node-only full native product; headless, not textured rendering or real-map performance. Trace adds overhead; direct component timings overlap reader work and are not additive. Only events explicitly instrumented by production are observed; structural counts are code-derived, not instrumented."}

class GamePreparation extends "res://scripts/world3d/model_parse_preparation.gd":
	var raw_calls:=0
	func _guarded_fallback(path:String,parser:Callable,eligible:bool)->Dictionary:
		raw_calls+=1
		return super._guarded_fallback(path,parser,eligible)

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	report.checks.append({"name":label,"ok":ok})
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func put(path:String,bytes:PackedByteArray)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	assert(file!=null)
	file.store_buffer(bytes);file.close()

func put_json(path:String,value:Variant)->void:put(path,JSON.stringify(value).to_utf8_buffer())

func test_root()->String:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-root="):
			var path:String=arg.trim_prefix("--fixture-root=").replace("\\","/").simplify_path().trim_suffix("/")
			var base:=ARTIFACT_ROOT.to_lower()+"/"
			if path.is_absolute_path() and path.to_lower().begins_with(base) and not DirAccess.dir_exists_absolute(path) and not FileAccess.file_exists(path) and preload("res://scripts/world3d/map_paths.gd").allowed(path,ARTIFACT_ROOT):return path
	return ""

func fake_estimate(_path:String)->Dictionary:return {"estimated_bytes":128*1024*1024,"exclusive":false,"known":true}

func game_run(path:String,root_path:String)->Dictionary:
	var preparation:=GamePreparation.new();preparation.require_native_products=true
	preparation.memory_estimator=fake_estimate
	var result:Dictionary=preparation.run([path],Callable(),1,Callable(),root_path)
	result.raw_calls=preparation.raw_calls
	return result

func run()->void:
	var folder:=test_root()
	if folder.is_empty():
		push_error("--fixture-root must be a new directory inside review_artifacts")
		quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	var source_data:PackedByteArray="synthetic authoring source, not GLB".to_utf8_buffer()
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(source_data);var source_sha:=hash.finish().hex_encode()
	var source:=folder.path_join("assets").path_join(source_sha+".glb")
	put(source,source_data)
	var scene:=Node3D.new();scene.name="Fixture"
	var bytes:=PackedByteArray();bytes.resize(8*1024*1024)
	scene.set_meta("synthetic_payload",bytes)
	for index in 96:
		var node:=Node3D.new();node.name="N%d"%index;scene.add_child(node);node.owner=scene
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack node-only fixture")
	scene.free()
	var temp:=folder.path_join("fixture.scn")
	check(ResourceSaver.save(packed,temp,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"write native fixture")
	var payload_sha:=FileAccess.get_sha256(temp)
	var product:=Compiled.directory(folder).path_join(payload_sha+".scn")
	DirAccess.make_dir_recursive_absolute(product.get_base_dir())
	check(DirAccess.rename_absolute(temp,product)==OK,"publish fixture payload")
	var file:=FileAccess.open(product,FileAccess.READ);var product_bytes:=file.get_length();file.close()
	var generator:=Compiled.generator()
	report.fixture={"root":folder,"source_path":source,"source_sha256":source_sha,"source_kind":"synthetic non-GLB logical-key placeholder","product":product,"product_sha256":payload_sha,"product_bytes":product_bytes,"mesh_nodes":0,"node_count":97,"payload_kind":"uncompressed 8 MiB zero-filled node metadata","engine":Engine.get_version_info(),"script_sha256":FileAccess.get_sha256("res://tools/probe_compiled_native_work.gd"),"appdata":OS.get_environment("APPDATA"),"localappdata":OS.get_environment("LOCALAPPDATA"),"temp":OS.get_environment("TEMP"),"tmp":OS.get_environment("TMP"),"tmpdir":OS.get_environment("TMPDIR")}
	var manifest:={"version":Compiled.VERSION,"generator":generator,"source_sha":source_sha,"payload_sha":payload_sha,"bytes":product_bytes}
	put_json(Compiled.index_path(source,folder),manifest)
	var stats:=Footprint.empty_stats();stats.nodes=97;stats.native_uncompressed_bytes=product_bytes
	var estimate:=Footprint.estimate_stats(stats)
	var descriptor:={"version":Footprint.VERSION,"footprint_generator":Footprint.generator(),"source_path":source,"source_sha":source_sha,"payload_sha":payload_sha,"generator":generator,"bytes":product_bytes,"source_bytes":source_data.size(),"stats":stats,"estimated_bytes":estimate.estimated_bytes,"resident_bytes":estimate.resident_bytes}
	var body:=JSON.stringify(descriptor)
	put_json(Footprint.descriptor_path(source,folder),{"version":Footprint.VERSION,"body":body,"sha256":body.sha256_text()})
	var candidate:=Footprint.candidate(source,folder,source_sha)
	check(not candidate.is_empty(),"actual footprint candidate resolves")
	if candidate.is_empty():finish(folder);return
	var began:=Time.get_ticks_usec();var generator_result:=Compiled.generator();var generator_us:=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();var digest:=FileAccess.get_sha256(product);var sha_us:=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();var dependencies:=ResourceLoader.get_dependencies(product);var deps_us:=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();var schema:=Compiled._valid_packed(packed);var schema_us:=Time.get_ticks_usec()-began
	check(generator_result==generator and digest==payload_sha and dependencies.is_empty() and schema,"separate cost probes preserve fixture identity")
	Trace.minimum_event_us=0;Trace.start()
	var repeats:=8;var cache_total:=0;var candidate_total:=0
	for index in repeats:
		began=Time.get_ticks_usec();var cache:=Compiled.read(source,"",folder,false,true);cache_total+=Time.get_ticks_usec()-began
		check(cache.hit,"trusted cache read %d"%index);cache.clear()
		began=Time.get_ticks_usec();var result:=Reader.read(source,candidate,folder,Callable(),true);candidate_total+=Time.get_ticks_usec()-began
		check(result.get("error",FAILED)==OK,"trusted candidate read %d"%index);result.clear()
	var trace:=Trace.stop();var payload_events:Array=[]
	for event:Dictionary in trace.events:
		if event.label=="compiled.payload_sha" and event.details.get("path")==source:payload_events.append(event.duration_us)
	check(trace.dropped==0 and payload_events.size()==repeats*2,"each observed reader repeats payload hash")
	report.work={"repetitions_per_reader":repeats,"payload_bytes":product_bytes,"payload_hash_calls_observed":payload_events.size(),"payload_hash_bytes_observed":product_bytes*payload_events.size(),"payload_hash_total_us_observed":payload_events.reduce(func(a,b):return a+b,0),"cache_reader_total_us_instrumented":cache_total,"candidate_reader_total_us_instrumented":candidate_total,"one_shot_component_us":{"generator":generator_us,"payload_sha":sha_us,"dependencies":deps_us,"schema":schema_us},"structural_per_successful_read":{"generator_script_hashes":9,"payload_sha":1,"dependencies":1,"valid_packed":1},"limits":"Structural counts exclude footprint candidate discovery; one-shot costs are standalone warm-cache proxy measurements, not timed spans inside the reads."}
	var editor:=preload("res://scripts/world_editor/load_job.gd")._parse_native_asset(source,folder,candidate)
	check(editor.get("error",FAILED)==OK and editor.get("compiled",false),"actual editor loader consumes complete native fixture")
	editor.clear()
	var strict:=Compiled.read(source,"",folder,false,false)
	check(strict.hit,"explicit strict read accepts unchanged source");strict.clear()
	var changed:=source_data.duplicate();changed[0]^=1;put(source,changed)
	strict=Compiled.read(source,"",folder,false,false)
	check(not strict.hit and strict.reason=="source_changed_during_read","explicit strict read rejects same-length source change")
	strict.clear()
	put(source,source_data)
	var hidden_source:=source+".held"
	check(DirAccess.rename_absolute(source,hidden_source)==OK,"temporarily hide isolated authoring source")
	editor=preload("res://scripts/world_editor/load_job.gd")._parse_native_asset(source,folder,candidate)
	check(editor.get("error",FAILED)==OK and editor.get("compiled",false),"actual editor loader accepts native product without authoring source")
	editor.clear();check(DirAccess.rename_absolute(hidden_source,source)==OK,"restore isolated authoring source")
	var game:=game_run(source,folder)
	check(game.error==OK and game.raw_calls==0 and game.native_cache_hits==1,"required-native coordinator loads candidate without raw parser")
	game.clear()
	var hidden:=product+".held";check(DirAccess.rename_absolute(product,hidden)==OK,"temporarily hide isolated native product")
	game=game_run(source,folder)
	check(game.error!=OK and game.raw_calls==0 and game.entries.size()==1 and game.entries[0].get("native_product_required",false),"required-native coordinator reports missing product without GLB fallback")
	game.clear();check(DirAccess.rename_absolute(hidden,product)==OK,"restore isolated native product")
	finish(folder)

func finish(folder:String)->void:
	report.failures=failures
	put_json(folder.path_join("report.json"),report)
	print("COMPILED_NATIVE_WORK_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
