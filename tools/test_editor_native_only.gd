extends SceneTree
## Temporary native products only. A logical GLB path must never be opened.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const LoadJob=preload("res://scripts/world_editor/load_job.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
var failures:=0
var passed:=0

func result_label()->String:return "EDITOR_NATIVE_ONLY"

func check(value:bool,label:String)->void:
	if value:passed+=1;print("PASS: ",label)
	else:failures+=1;printerr("FAIL: ",label)

func _initialize()->void:run.call_deferred()

func publish(root_:String,source:String,name_:String)->Dictionary:
	var node:=Node3D.new();node.name=name_
	var packed:=PackedScene.new();var err:=packed.pack(node);node.free()
	if err!=OK:return {}
	var folder:=Compiled.directory(root_);DirAccess.make_dir_recursive_absolute(folder)
	var temp:=folder.path_join(name_+".scn")
	if ResourceSaver.save(packed,temp)!=OK:return {}
	var payload_sha:=FileAccess.get_sha256(temp);var target:=folder.path_join(payload_sha+".scn")
	if DirAccess.rename_absolute(temp,target)!=OK:return {}
	var product:=FileAccess.open(target,FileAccess.READ);var bytes:=product.get_length();product.close()
	var source_sha:="a".repeat(64);var generator:="b".repeat(64)
	var index:={"version":Compiled.VERSION,"source_sha":source_sha,"payload_sha":payload_sha,"generator":generator,"bytes":bytes}
	var file:=FileAccess.open(Compiled.index_path(source,root_),FileAccess.WRITE);file.store_string(JSON.stringify(index));file.close()
	var descriptor:={"version":Footprint.VERSION,"source_path":source,"source_sha":source_sha,"payload_sha":payload_sha,"generator":generator,"bytes":bytes,"estimated_bytes":65536,"resident_bytes":65536}
	var body:=JSON.stringify(descriptor);var envelope:={"version":Footprint.VERSION,"body":body,"sha256":body.sha256_text()}
	DirAccess.make_dir_recursive_absolute(Footprint.directory(root_))
	file=FileAccess.open(Footprint.descriptor_path(source,root_),FileAccess.WRITE);file.store_string(JSON.stringify(envelope));file.close()
	return {"product":target,"index":Compiled.index_path(source,root_)}

func run()->void:
	var root_:="D:/code/rmmo_runtime/review_artifacts/editor_native_only_fixture_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(root_)
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override;manager.content_root_override=root_
	var source:=root_.path_join("asset/model.glb")
	var published:=publish(root_,source,"first")
	check(not published.is_empty() and not FileAccess.file_exists(source),"native fixture has no authoring GLB")
	var job:=LoadJob.new();root.add_child(job);job._timings.build={"units":{}}
	var record:={"kind":"asset","uuid":"native_job","asset_path":source}
	job._begin_asset_lookahead([record,record])
	check(job._asset_paths.size()==1 and job._preparation.has("model:"+source),"editor lookahead schedules one native model without GLB")
	var prepared:Dictionary=await job._prepare_asset(record)
	check(prepared.get("scene") is Node3D and prepared.scene.name=="first","editor load job publishes native without GLB")
	if prepared.get("scene") is Node:prepared.scene.free()
	var ledger:RefCounted=job._preparation.ledger;job._clear_asset_lookahead()
	for frame:int in 30:
		if ledger.reserved_bytes==0:break
		await process_frame
	check(ledger.reserved_bytes==0,"editor native job releases its lease")
	job.free();Library.evict_cached_scene(source)
	var scene:=Library.instantiate(source)
	check(scene!=null and scene.name=="first","editor instantiate loads published native without source")
	if scene!=null:scene.free()
	var preview:=Library.instantiate_preview(source)
	check(preview!=null and preview.name=="first","editor preview loads published native without source")
	if preview!=null:preview.free()
	var held_job:=LoadJob.new();root.add_child(held_job);held_job._timings.build={"units":{}}
	held_job._begin_asset_lookahead([record])
	var held:Dictionary=await held_job._prepare_asset(record)
	check(held.get("template") is PackedScene,"cached native owner is pinned for publication")
	var next:=publish(root_,source,"second")
	var updated:=Library.instantiate(source)
	check(not next.is_empty() and updated!=null and updated.name=="second","new native payload replaces old same-source cached template")
	if updated!=null:updated.free()
	var held_document:=Document.new();held_document.add_asset({"asset_path":source},Vector3.ZERO)
	var held_visual:=held_document._asset(held_document.records[0],held)
	check(held_visual.get_child_count()>0 and held_visual.get_child(0).name=="first","publication across replacement keeps pinned native owner")
	held_visual.free()
	var late:Dictionary=await held_job._prepare_asset(record)
	check(late.has("scene") and late.scene==null,"later publication does not silently switch pinned owner")
	held_job._clear_asset_lookahead();held_job.free();held.clear()
	var doc:=Document.new();var authored_id:=doc.add_asset({"asset_path":source},Vector3.ZERO)
	check(doc.missing_assets().is_empty(),"document sees native-only asset as available without GLB")
	var save_paths:={source:true}
	check(doc.validate_save_asset_paths(save_paths)==OK,"save validation accepts native-only source identity")
	var map_path:=root_.path_join("map.gltf")
	var save_error:int=doc.save(map_path)
	check(save_error==OK,"native-only authored document saves without GLB")
	var reopened=Document.open_file(map_path) if save_error==OK else null
	check(reopened!=null and reopened.records.size()==1 and reopened.records[0].uuid==authored_id and reopened.records[0].asset_path==source and reopened.missing_assets().is_empty(),"saved native-only authored document reopens without GLB")
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd");var old_policy:bool=policy.verify_packages
	policy.verify_packages=false
	Library.evict_cached_scene(source)
	var trusted:=Library.instantiate(source)
	check(trusted!=null,"trusted owner is cached before strict audit")
	if trusted!=null:trusted.free()
	var product_bytes:=FileAccess.get_file_as_bytes(next.product)
	var damaged:=product_bytes.duplicate();damaged[damaged.size()-1]^=1
	var product_file:=FileAccess.open(next.product,FileAccess.WRITE);product_file.store_buffer(damaged);product_file.close()
	policy.verify_packages=true
	var unaudited_scene:=Library.instantiate(source);var unaudited_preview:=Library.instantiate_preview(source)
	check(unaudited_scene==null and unaudited_preview==null,"first strict access audits previously trusted cache and rejects damaged native")
	if unaudited_scene!=null:unaudited_scene.free()
	if unaudited_preview!=null:unaudited_preview.free()
	product_file=FileAccess.open(next.product,FileAccess.WRITE);product_file.store_buffer(product_bytes);product_file.close()
	var strict:=Library.instantiate(source)
	check(strict!=null and strict.name=="second","strict audit verifies native product without GLB")
	check(strict!=null and Library.cache_scene(source,strict,"a".repeat(64)),"audited native owner can be repacked into editor cache")
	check(Library._scenes.get(source) is PackedScene and Library._scenes[source].get_meta("_rmmo_native_audited",false),"repacked editor cache retains native audit provenance")
	check(Library.native_candidate(source,root_,"c".repeat(64)).is_empty(),"explicit conversion generator mismatch rejects native candidate")
	product_file=FileAccess.open(next.product,FileAccess.WRITE);product_file.store_buffer(damaged);product_file.close()
	var audited:=Library.instantiate(source)
	check(audited!=null and audited.name=="second","strict mode reuses already audited in-memory owner")
	if audited!=null:audited.free()
	Library.evict_cached_scene(source)
	check(Library.instantiate(source)==null and not FileAccess.file_exists(source),"strict native checksum rejects damaged product without GLB fallback")
	product_file=FileAccess.open(next.product,FileAccess.WRITE);product_file.store_buffer(product_bytes);product_file.close()
	policy.verify_packages=old_policy
	DirAccess.remove_absolute(next.index)
	check(Library.instantiate(source)==null and Library.instantiate_preview(source)==null,"missing native index fails without cached/raw fallback")
	check(not doc.missing_assets().is_empty(),"document reports missing native product")
	Library.evict_cached_scene(source);manager.content_root_override=old_root
	print(result_label()," passed=",passed," failures=",failures," root=",root_)
	quit(1 if failures else 0)
