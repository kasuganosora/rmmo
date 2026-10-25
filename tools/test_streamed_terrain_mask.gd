extends SceneTree
## CPU/Image-only regression for the real native-reference worker and its
## borrowed document context. All authored files are outside the project.
const Prepare=preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Format=preload("res://scripts/world3d/world_location.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
var passed:=0
var failures:=0
var folder:=""
var content_root:=""
var created:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1

func terrain(id:String,x:float,regions:bool=true)->Dictionary:
	var heights:Array=[];heights.resize(25);heights.fill(0.)
	var holes:Array=[];holes.resize(16);holes.fill(false)
	var record:={"uuid":id,"kind":"box","surface_id":"grass","collision":"none","position":[x,0.,0.],"rotation":[0.,0.,0.],"size":[8.,1.,8.],"terrain_mesh":{"version":1,"columns":4,"rows":4,"floor":-1.,"heights":heights,"holes":holes}}
	if regions:
		record.terrain_regions={"materials":[{"name":"soil","color":[1.,1.,1.,1.],"roughness":1.}],"regions":[{"id":"field","layer":0,"opacity":.8,"feather":1.,"polygon":[[-3.,-3.],[3.,-3.],[3.,3.],[-3.,3.]]}]}
	return record

func fixture(records:Array)->Dictionary:
	var path:=folder.path_join("map.gltf")
	var stored:=Store.write_records(records,path,content_root)
	if not stored.ok:return {}
	var extras:={"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0.,1.,0.]}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extras}]}));file.close()
	created.append(path);created.append(Index.cache_path(path,content_root))
	for uri:String in stored.dependencies:created.append(folder.path_join(uri))
	return {"path":path,"index":Index.build(path,content_root,records)}

func entries(index:Dictionary,positions:Array)->Array:
	var result:Array=[]
	for at:int in positions:
		var row:Dictionary=index.rows[at]
		result.append({"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path,"memory_bytes":row.memory_bytes})
	return result

func prepare_worker(f:Dictionary,positions:Array,token:RefCounted=null)->Dictionary:
	var worker:=Thread.new()
	var error:=worker.start(Prepare.prepare.bind(f.index,entries(f.index,positions),f.path,content_root,token,null,{}, {},0,true))
	check(error==OK,"real reference worker starts")
	if error!=OK:return {"error":"thread start failed"}
	return worker.wait_to_finish()

func discard_case(result:Dictionary,cancelled:bool)->void:
	var mask:Image=result.get("terrain_contexts",{}).get("left",{}).get("region_mask")
	if mask==null:return
	var weak:WeakRef=weakref(mask);mask=null
	var queue:=Queue.new();var path:="reference:terrain-mask"
	queue._accept_prepared_records(result)
	check(queue._doc.terrain_neighbors.data.left.region_mask==weak.get_ref(),"document borrows exactly the worker Image")
	var token:=Queue.Drainer.CancelToken.new()
	if cancelled:token.cancel()
	queue._admission.reserve(path,{"estimated_bytes":1048576,"exclusive":false})
	queue._jobs[path]={"result":result,"token":token,"publication_ids":[]}
	queue._discard_job(path)
	check(result.is_empty() and queue._doc.terrain_neighbors.data.is_empty() and weak.get_ref()==null,"cancelled result releases mask owners" if cancelled else "completed job releases mask owners after document handoff")
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"discard releases the original admission lease")
	queue.free()

func run()->void:
	content_root=Paths.external_root();folder=Paths.cache_directory("streamed_terrain_mask_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var records:Array=[terrain("left",0.),terrain("neighbor",8.),terrain("plain",16.,false),terrain("distant",1000.)]
	var before:=var_to_bytes(records);var expected:=Regions.mask(records[0]).get_data()
	var f:=fixture(records)
	check(not f.is_empty() and f.index.ok,"temporary native terrain catalogue builds")
	if f.is_empty() or not f.index.ok:quit(1);return
	var original_sha:=FileAccess.get_sha256(f.path)
	var result:=prepare_worker(f,[0,2])
	check(result.error.is_empty(),"native terrain worker succeeds")
	var contexts:Dictionary=result.get("terrain_contexts",{})
	check(contexts.size()==2 and contexts.has("left") and contexts.has("plain") and not contexts.has("neighbor") and not contexts.has("distant"),"worker publishes requested tiles only, not seam dependencies")
	var mask:Image=contexts.get("left",{}).get("region_mask")
	check(mask!=null,"streamed terrain carries its authored region mask from the worker")
	check(int(result.read_profile.get("terrain_mask_generations",-1))==1 and int(result.read_profile.get("terrain_mask_on_main",-1))==0,"one requested mask is generated on the worker and zero on main")
	if mask!=null:
		check(mask.get_format()==Image.FORMAT_RG8 and mask.get_data()==expected,"prepared mask equals every canonical pixel")
		check(mask.get_data_size()==Regions.RESOLUTION*Regions.RESOLUTION*2,"fixed RG8 mask charge matches actual bytes")
		check(int(result.read_profile.terrain_mask_bytes)==mask.get_data_size(),"worker reports the retained mask bytes")
		River.reset_index_profile()
		var reused:=true
		for i:int in 20:reused=reused and River._region_mask(records[0],contexts.left)==mask
		check(reused and River.region_mask_prepared_hits==20 and River.region_mask_fallback_generations==0,"main publication resolver borrows the worker image without any regeneration")
		print("MASK_WORK ",JSON.stringify({"worker_generations":result.read_profile.terrain_mask_generations,"worker_us":result.read_profile.terrain_mask_us,"main_generations":River.region_mask_fallback_generations,"prepared_reuses":River.region_mask_prepared_hits,"bytes":result.read_profile.terrain_mask_bytes}))
	check(not contexts.get("plain",{}).has("region_mask"),"terrain without authored regions does no mask work")
	check(var_to_bytes(records)==before and FileAccess.get_sha256(f.path)==original_sha,"worker preserves author records and map bytes")
	# Existing terrain fixed reserve covers RG8 mask plus the largest RF halo
	# and its float/byte construction buffers; per-cell reserve covers geometry.
	var maximum_halo_bytes:=(64+1+33*2)*(64+1+33*2)*4
	check(Regions.RESOLUTION*Regions.RESOLUTION*2+maximum_halo_bytes*3<1048576 and int(f.index.rows[0].memory_bytes)>1048576,"existing fixed terrain admission covers mask and maximum halo scratch")
	mask=null;contexts={}
	discard_case(result,false)
	var token:=Queue.Drainer.CancelToken.new();token.cancel()
	var cancelled:=prepare_worker(f,[0],token)
	check(cancelled.get("cancelled",false) and cancelled.records.is_empty() and cancelled.get("terrain_contexts",{}).is_empty(),"pre-cancelled worker publishes no masks or records")
	var returned:=prepare_worker(f,[0]);discard_case(returned,true)
	for mode:String in ["white","discard"]:
		Controls.white_materials=mode=="white";Controls.discard_map_textures=mode=="discard"
		var skipped:=prepare_worker(f,[0])
		check(skipped.error.is_empty() and not skipped.terrain_contexts.left.has("region_mask") and int(skipped.read_profile.terrain_mask_generations)==0 and int(skipped.read_profile.terrain_mask_bytes)==0,mode+" controls keep streamed mask work at zero")
	Controls.white_materials=false;Controls.discard_map_textures=false
	River.reset_index_profile()
	var fallback:=River._region_mask(records[0],{})
	check(fallback.get_data()==expected and River.region_mask_fallback_generations==1 and River.region_mask_prepared_hits==0,"synchronous editor callers keep the exact canonical fallback")
	fallback=null
	var edited:Array=records.duplicate(true);edited[0].terrain_regions.regions[0].opacity=.3
	var next:=fixture(edited);var updated:=prepare_worker(next,[0])
	check(updated.error.is_empty() and updated.terrain_contexts.left.region_mask.get_data()!=expected and updated.terrain_contexts.left.region_mask.get_data()==Regions.mask(edited[0]).get_data(),"later map revision prepares fresh region pixels without a cross-load mask cache")
	discard_case(updated,false)
	for path:String in created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("STREAMED_TERRAIN_MASK passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
