extends SceneTree
const Builder=preload("res://tools/isolated_texture_map_builder.gd")
const Helpers=preload("res://tools/test_isolated_map_retarget.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const NativeRekey=preload("res://tools/isolated_native_cache.gd")
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const MODEL_SHA="9a1bb221422047ec2bba1393752f44c7dd8523ac431ec5f8d0da89a94ed60de9"
var failures:Array[String]=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func put(path:String,value:Variant)->void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:failures.append("cannot write "+path);return
	if value is PackedByteArray:f.store_buffer(value)
	else:f.store_string(JSON.stringify(value,"\t"))
	f.close()
func run()->void:
	var base:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):base=arg.trim_prefix("--output=")
	if base.is_empty() or not Paths.allowed(base,Builder.REVIEW_ROOT) or DirAccess.dir_exists_absolute(base):printerr("new external --output required");quit(2);return
	var original:=base.path_join("original");var pack:=original.path_join("packs/default");var stage:=base.path_join("stage");var target:=base.path_join("candidate")
	DirAccess.make_dir_recursive_absolute(pack.path_join("assets"));DirAccess.make_dir_recursive_absolute(stage.path_join("blobs"))
	var helper:=Helpers.new();var source:=pack.path_join("assets/shared.png");var image:=Image.create(7,11,false,Image.FORMAT_RGBA8);image.fill(Color(.25,.5,.75));image.save_png(source)
	Controls.enable_native_geometry_only()
	var source_model:=pack.path_join("assets/"+MODEL_SHA+".glb")
	var native_seed:=NativeRekey.rekey("D:/code/rmmo_runtime/packs/default/assets/"+MODEL_SHA+".glb",source_model,"D:/code/rmmo_runtime",original)
	check(native_seed.get("ok",false),"seed one validated native product without copying GLB")
	var record:Dictionary=helper.make_record(source);var second:Dictionary=record.duplicate(true);second.uuid="fixture_wall_2";second.position=[8.,2.,0.]
	var asset:Dictionary={"uuid":"fixture_native","kind":"asset","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"asset_path":source_model}
	var map:=pack.path_join("map.gltf");var saved:Dictionary=helper.write_map(map,original,[record,second,asset])
	check(saved.get("ok",false),"source fixture saves "+str(saved.get("reason","")))
	var audit_path:=base.path_join("audit.json");var map_sha:=FileAccess.get_sha256(map);var source_sha:=FileAccess.get_sha256(source)
	var native_item:Dictionary={"model":source_model,"source_sha256":MODEL_SHA,"product_sha256":native_seed.payload_sha256,"bytes":native_seed.product_bytes}
	for native_file:Dictionary in native_seed.files:
		var field:String={"index":"index","metadata":"descriptor","payload":"product"}[native_file.kind]
		native_item[field]=native_file.target;native_item[field+"_sha256"]=native_file.sha256
	var native_manifest:=base.path_join("native.json");var path_inventory:=base.path_join("path_inventory.json")
	put(path_inventory,{"map":map,"map_sha256":map_sha,"path_fields":{"record.asset_path":{"count":1,"values":[source_model]},"record.prefab_materials[].texture_path":{"count":2,"values":[source]}}})
	var native_data:Dictionary={"map":map,"source_root":original,"map_sha256":map_sha,"errors":[],"requested":1,"passed":1,"models":[native_item],"inventory":path_inventory,"inventory_sha256":FileAccess.get_sha256(path_inventory)}
	put(native_manifest,native_data)
	var audit:Dictionary={"map":map,"map_sha256":map_sha,"map_unchanged":true,"errors":[],"texture_variants":[{"source":source,"normal_role":false,"flip_normal_green":false,"selected_sidecar":""},{"source":source,"normal_role":true,"flip_normal_green":true,"selected_sidecar":""}]}
	for i:int in 10:
		var extra:=pack.path_join("assets/shared_%02d.png"%i)
		if DirAccess.copy_absolute(source,extra)!=OK:printerr("cannot create fixture texture");quit(1);return
		audit.texture_variants.append({"source":extra,"normal_role":true,"flip_normal_green":true,"selected_sidecar":""})
	put(audit_path,audit)
	var blob:=stage.path_join("blobs/normal.dds");put(blob,helper.bc5(7,11));var blob_sha:=FileAccess.get_sha256(blob)
	var stage_data:Dictionary={"map":map,"map_sha256":map_sha,"audit_sha256":FileAccess.get_sha256(audit_path),"pack_root":pack,"blobs":[{"path":"blobs/normal.dds","sha256":blob_sha,"source_sha256":source_sha,"role":"normal","flip":true,"width":7,"height":11}],"targets":[{"source":"assets/shared.png","source_sha256":source_sha,"target":"assets/shared.png.flip.bc5.dds","role":"normal","flip":true,"blob":"blobs/normal.dds","blob_sha256":blob_sha}]}
	for i:int in 10:
		var relative:="assets/shared_%02d.png"%i
		stage_data.targets.append({"source":relative,"source_sha256":source_sha,"target":relative+".flip.bc5.dds","role":"normal","flip":true,"blob":"blobs/normal.dds","blob_sha256":blob_sha})
	put(stage.path_join("manifest.json"),stage_data);put(stage.path_join("COMPLETE"),PackedByteArray())
	var bad:=stage_data.duplicate(true);bad.targets[0].target="assets/shared.png.dxt1.dds";put(stage.path_join("manifest.json"),bad)
	var red:Dictionary=Builder.build(map,original,audit_path,stage,base.path_join("red_role"),native_manifest);check(not red.get("ok",false),"wrong candidate role/suffix rejected")
	put(stage.path_join("manifest.json"),stage_data)
	var inventory_bytes:=FileAccess.get_file_as_bytes(path_inventory);var bad_inventory:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path_inventory));bad_inventory.path_fields["record.unknown_runtime_path"]={"count":1,"values":[source]};put(path_inventory,bad_inventory)
	var bad_native:Dictionary=native_data.duplicate(true);bad_native.inventory_sha256=FileAccess.get_sha256(path_inventory);put(native_manifest,bad_native)
	var unknown:=Builder.build(map,original,audit_path,stage,base.path_join("red_unknown_path"),native_manifest);check(not unknown.get("ok",false) and str(unknown.get("error","")).begins_with("unhandled serialized path field"),"unhandled path fails before any target root is created")
	put(path_inventory,inventory_bytes);put(native_manifest,native_data)
	put(source+".flip.bc5.dds",helper.bc5(7,11))
	var changed:=Builder.build(map,original,audit_path,stage,base.path_join("red_changed_sidecar"),native_manifest);check(not changed.get("ok",false) and str(changed.get("error","")).begins_with("inventoried sidecar changed"),"new source sidecar rejected instead of changing baseline")
	DirAccess.remove_absolute(source+".flip.bc5.dds")
	put(blob,PackedByteArray([0,1,2]))
	var invalid_blob:=Builder.build(map,original,audit_path,stage,base.path_join("red_header"),native_manifest);check(not invalid_blob.get("ok",false) and invalid_blob.get("error","")=="staged sidecar header/role mismatch","candidate with invalid DDS header rejected")
	put(blob,helper.bc5(7,11))
	var built:Dictionary=Builder.build(map,original,audit_path,stage,target,native_manifest)
	check(built.get("ok",false),"isolated closure builds: "+str(built.get("error","")))
	if not built.get("ok",false):quit(1);return
	check(built.material_edits==4 and built.prefab_edits==2 and built.candidate_targets.size()==11 and built.texture_variants.size()==12,"exact role inventory and prefab retarget counts")
	var loaded:Dictionary=helper.read_map(built.target_map,target)
	check(loaded.get("ok",false) and loaded.records.size()==3,"target reloads")
	if loaded.get("ok",false):
		check(Prefab.valid(loaded.records[0]) and loaded.records[0].prefab_materials[0].normal_path==target.path_join("packs/default/assets/shared.png"),"embedded prefab and texture root agree")
		var mismatch:Dictionary=loaded.records[0].duplicate(true);mismatch.prefab_materials[0].normal_path=source
		check(not Builder._strict_prefab_valid(mismatch) and not Builder.Policy.verify_packages,"offline strict validation catches a paint/packet mismatch and restores runtime policy")
		check(loaded.records[0].provenance_note==source,"unrelated paths remain untouched")
		var relocated_model:String=loaded.records[2].asset_path
		check(built.native.size()==1 and not FileAccess.file_exists(relocated_model) and Native.read(relocated_model,MODEL_SHA,target,true).get("hit",false),"builder-native index hits rewritten logical path without GLB")
		var index:=Index.build_for_loading(built.target_map,target,loaded.records,"",1,Index.Snapshot.RETAIN_LIMIT,true)
		var rows:Array=index.get("index",{}).get("rows",[])
		check(index.get("ok",false) and rows.size()==3 and rows[2].asset_path==relocated_model and rows[2].reason=="model_accessor_bounds","runtime dependency index classifies relocated native model: "+str(index.get("reason","")))
	var row:Dictionary=built.candidate_targets[0];var isolated_source:String=row.source
	check(not FileAccess.file_exists(row.target) and Compressed.plan(isolated_source,true,true,target).is_empty(),"A starts with no candidate sidecar")
	check(DirAccess.copy_absolute(row.blob,row.target)==OK and FileAccess.get_sha256(row.target)==blob_sha,"B installs exactly inventoried candidate")
	var plan:=Compressed.plan(isolated_source,true,true,target)
	check(not plan.is_empty() and plan.sidecar==row.target and Compressed.read(plan).get_meta("runtime_normal_xy",false),"B selects correct normal role")
	check(Compressed.plan(isolated_source,false,false,target).is_empty(),"normal sidecar cannot affect color")
	check(DirAccess.remove_absolute(row.target)==OK and Compressed.plan(isolated_source,true,true,target).is_empty(),"A restores absence using exact owned path")
	check(FileAccess.get_sha256(map)==map_sha and FileAccess.get_sha256(source)==source_sha and not FileAccess.file_exists(source+".flip.bc5.dds"),"source map and files untouched")
	var again:=Builder.build(map,original,audit_path,stage,target,native_manifest);check(not again.get("ok",false),"existing fixture is never overwritten")
	var missing_errors:Dictionary=audit.duplicate(true);missing_errors.erase("errors");put(audit_path,missing_errors)
	var missing:=Builder.build(map,original,audit_path,stage,base.path_join("red_missing_errors"),native_manifest);check(not missing.get("ok",false) and missing.get("error","").begins_with("inventory"),"missing audit error list rejected")
	var bad_audit:Dictionary=audit.duplicate(true);bad_audit.map_sha256="stale";put(audit_path,bad_audit)
	var stale:=Builder.build(map,original,audit_path,stage,base.path_join("red_stale"),native_manifest);check(not stale.get("ok",false),"stale inventory rejected")
	put(audit_path,audit)
	helper.free();print("ISOLATED_BUILDER checks=",checks," failures=",failures.size()," output=",base)
	for failure:String in failures:printerr("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
