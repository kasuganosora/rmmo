extends SceneTree
## Independent 4.8 import contract, including mip0 identity and distant cutouts.
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var checks:=0
var failures:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func _work(task:Callable)->Variant:
	var worker:=Thread.new();var started:=worker.start(task)
	if started!=OK:return {}
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()
static func coverage(image:Image,mip:int,threshold:float=.5)->float:
	var data:=image.get_data();var begin:=image.get_mipmap_offset(mip)
	var end:=image.get_mipmap_offset(mip+1) if mip<image.get_mipmap_count() else data.size()
	var level:=Image.create_from_data(maxi(1,image.get_width()>>mip),maxi(1,image.get_height()>>mip),false,image.get_format(),data.slice(begin,end))
	if level.is_compressed():level.decompress()
	var total:=0
	for y:int in level.get_height():
		for x:int in level.get_width():total+=int(level.get_pixel(x,y).a>threshold)
	return float(total)/(level.get_width()*level.get_height())
func run()->void:
	var root:=Paths.external_root();var folder:=root.path_join("cache/alpha_coverage_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var source:=folder.path_join("leaves.png")
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y:int in 64:
		for x:int in 64:image.set_pixel(x,y,Color(.2,.65,.3,1. if (x*37+y*67+x*y*13)%101<30 else 0.))
	check(image.save_png(source)==OK,"create independent leaf-like alpha fixture")
	var original:=image.get_data();var source_sha:=FileAccess.get_sha256(source)
	var directory:=folder.path_join("materials");var results:Array[Dictionary]=[]
	for options:Array in [[false,.5],[true,.5],[true,.7],[false,.7]]:
		var prepared:Dictionary=await _work(Worker.prepare.bind(source,directory,null,root,{},Callable(),"source",options[0],options[1]))
		check(prepared.get("ok",false),"CPU preparation accepts explicit coverage option")
		if not prepared.get("ok",false):quit(1);return
		var result:Dictionary=await _work(Worker.encode_publish.bind(prepared,null,root,Callable(),Callable(),true))
		check(result.get("ok",false),"CPU publication succeeds")
		if not result.get("ok",false):quit(1);return
		var pixels:Image=result.prepared_image
		check(pixels.get_data().slice(0,original.size())==original,"mip0 pixels and alpha are byte-identical")
		var label:Dictionary=await _work(Worker.publish_material.bind(result,"same label",null,root))
		check(label.get("ok",false),"material descriptor publishes at library root")
		results.append({"prepared":prepared,"result":result,"label":label})
	check(results[0].result.texture_path==results[3].result.texture_path,"disabled threshold does not add a variant")
	check(results[0].label.material_id==results[3].label.material_id,"disabled threshold shares the original material identity")
	check(results[0].result.texture_path!=results[1].result.texture_path and results[1].result.texture_path!=results[2].result.texture_path,"enabled and distinct thresholds have independent products")
	check(results[0].label.material_id!=results[1].label.material_id and results[1].label.material_id!=results[2].label.material_id,"material identities do not overwrite default or other threshold")
	var plain:Image=results[0].result.prepared_image;var kept:Image=results[1].result.prepared_image
	var base:=coverage(plain,0);var before:=coverage(plain,2);var after:=coverage(kept,2)
	check(absf(after-base)<absf(before-base),"distant mip alpha-test coverage is closer to the source")
	print("ALPHA_COVERAGE_MEASURE ",JSON.stringify({"base":base,"plain_mip2":before,"coverage_mip2":after}))
	var library:=Library.new(directory)
	for i:int in 3:
		var material:=library.find(results[i].label.material_id)
		check(not material.is_empty() and material.texture_path==results[i].result.texture_path,"catalog resolves the selected variant after reopening descriptor")
		check(material.has("alpha_scissor_threshold")==bool(i>0),"only opted-in materials change transparency mode")
	check(FileAccess.get_sha256(source)==source_sha,"original source file is unchanged")
	check(Worker.coverage_options(true,-.01).is_empty() and Worker.coverage_options(true,NAN).is_empty(),"invalid/nonfinite thresholds fail before work")
	var bad:Dictionary=results[1].label.material.duplicate(true);bad.alpha_scissor_threshold=1.1
	check(not Paint.material_valid(bad,false,root),"invalid material cutoff cannot enter a saved map")
	# Two IEEE-distinct thresholds must not alias through short float strings.
	check(Worker.coverage_options(true,.500000001).coverage_key!=Worker.coverage_options(true,.5).coverage_key,"parameter identity retains exact threshold precision")
	var native=preload("res://scripts/world3d/streamed_texture_source.gd")
	check(native.enabled(),"CPU fixture exercises production native publication")
	for enabled:bool in [false,true]:
		var failure_directory:=folder.path_join("failure_coverage" if enabled else "failure_default")
		var staged:Dictionary=await _work(Worker.prepare.bind(source,failure_directory,null,root,{},Callable(),"source",enabled,.5))
		check(staged.get("ok",false),"prepare isolated descriptor write-failure fixture")
		if not staged.get("ok",false):continue
		# A directory at the final descriptor path makes the real atomic write
		# fail, without replacing another material or modifying the input PNG.
		var blocker:String=native.descriptor_path(staged.texture_path,false,false,false)
		check(DirAccess.make_dir_recursive_absolute(blocker)==OK,"create real descriptor publication failure")
		var marker:=FileAccess.open(blocker.path_join("marker.txt"),FileAccess.WRITE);marker.store_string("preserve");marker.close()
		var rejected:Dictionary=await _work(Worker.encode_publish.bind(staged,null,root,Callable(),Callable(),true))
		check(not rejected.get("ok",false) if enabled else (rejected.get("ok",false) and not rejected.get("streamed_ready",true)),"opt-in fails explicitly while default retains its existing fallback")
		check(not FileAccess.file_exists(failure_directory.path_join(Worker._label_identity(staged,"failed import")+".json")) and DirAccess.dir_exists_absolute(blocker) and FileAccess.get_sha256(source)==source_sha,"failure advertises no material and preserves input and occupied destination")
	print("SURFACE_ALPHA_COVERAGE ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder}))
	quit(0 if failures.is_empty() else 1)
