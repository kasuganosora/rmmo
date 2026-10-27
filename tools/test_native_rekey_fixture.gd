extends SceneTree
## A tiny, read-only relocation proof for one already-built white native product.
## No GLB is copied or opened by this test. All output remains in a caller-owned,
## newly created directory under the external review-artifact root.
const Writer=preload("res://scripts/world3d/white_native_asset_writer.gd")
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const Relocate=preload("res://tools/isolated_native_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const ORIGINAL_ROOT:="D:/code/rmmo_runtime"
const SOURCE_SHA:="9a1bb221422047ec2bba1393752f44c7dd8523ac431ec5f8d0da89a94ed60de9"
const ORIGINAL_MODEL:=ORIGINAL_ROOT+"/packs/default/assets/"+SOURCE_SHA+".glb"
const ARTIFACT_ROOT:="D:/code/rmmo_runtime/review_artifacts"
var passed:=0
var failed:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1

func geometry(packed:PackedScene)->Array:
	var state:=packed.get_state();var rows:Array=[]
	for i:int in state.get_node_count():
		for j:int in state.get_node_property_count(i):
			if state.get_node_property_name(i,j)!=&"mesh":continue
			var mesh:Variant=state.get_node_property_value(i,j)
			if not mesh is ArrayMesh:continue
			if not mesh.has_meta("ground_cpu_cache"):return []
			var cpu:Variant=mesh.get_meta("ground_cpu_cache")
			rows.append({"geometry_key":cpu.geometry_key(),"surface_count":cpu.surfaces.size(),"faces":cpu.collision_faces().size(),"bounds":cpu.bounds})
	return rows

func run()->void:
	var out:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):out=arg.trim_prefix("--output=").replace("\\","/").simplify_path()
	if out.is_empty() or not Paths.allowed(out,ARTIFACT_ROOT) or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out):
		printerr("A new --output directory under external review_artifacts is required");quit(2);return
	if DirAccess.make_dir_recursive_absolute(out)!=OK:printerr("Cannot create test root");quit(2);return
	var temp_root:=out.path_join("content")
	var temp_model:=temp_root.path_join("packs/default/assets/"+SOURCE_SHA+".glb")
	var original_index:=Writer.index_path(ORIGINAL_MODEL,ORIGINAL_ROOT)
	var original_descriptor:=Metadata.path_for(ORIGINAL_MODEL,ORIGINAL_ROOT)
	var original_info:Variant=JSON.parse_string(FileAccess.get_file_as_string(original_index))
	if not original_info is Dictionary or not original_info.has("payload_sha"):
		printerr("Original native index missing");quit(2);return
	var payload_sha:String=original_info.payload_sha
	var original_product:=Writer.directory(ORIGINAL_ROOT).path_join(payload_sha+".scn")
	var target_index:=Writer.index_path(temp_model,temp_root)
	var target_descriptor:=Metadata.path_for(temp_model,temp_root)
	var target_product:=Writer.directory(temp_root).path_join(payload_sha+".scn")
	check(Paths.allowed(temp_model,temp_root) and not FileAccess.file_exists(temp_model),"temporary logical key is confined and has no GLB")
	check(original_index.get_file()!=target_index.get_file(),"renamed native index keys differ by logical absolute path")
	check(original_info.get("source_sha","")==SOURCE_SHA,"original index preserves named source identity")
	check(FileAccess.get_sha256(original_product)==payload_sha,"original immutable native product matches its identity")
	check(DirAccess.make_dir_recursive_absolute(temp_root)==OK,"create caller-owned temporary content root")
	check(ResourceLoader.get_dependencies(original_product).is_empty(),"original native product declares no external resource dependencies")
	Controls.enable_native_geometry_only()
	var built:Dictionary=Relocate.rekey(ORIGINAL_MODEL,temp_model,ORIGINAL_ROOT,temp_root)
	check(built.get("ok",false),"isolated helper relocates trusted native product")
	if not built.get("ok",false):
		print("NATIVE_REKEY_FIXTURE passed=",passed," failed=",failed," reason=",built.get("reason",""));quit(1);return
	check(FileAccess.get_sha256(original_index)==FileAccess.get_sha256(target_index),"index copied byte-identically under temporary key")
	check(FileAccess.get_sha256(original_descriptor)==FileAccess.get_sha256(target_descriptor),"metadata copied byte-identically under temporary key")
	check(FileAccess.get_sha256(original_product)==FileAccess.get_sha256(target_product),"native product copied byte-identically into temporary root")
	check(ResourceLoader.get_dependencies(target_product).is_empty(),"relocated native product declares no external resource dependencies")
	check(built.get("files",[]).size()==3 and built.get("source_sha256","")==SOURCE_SHA and built.get("payload_sha256","")==payload_sha,"helper returns exact three-file identity manifest")
	var replay:Dictionary=Relocate.rekey(ORIGINAL_MODEL,temp_model,ORIGINAL_ROOT,temp_root)
	check(replay.get("ok",false) and replay.get("reused",0)==3,"repeated same-source preparation reuses matching isolated files")
	check(not Relocate.rekey(ORIGINAL_MODEL,ORIGINAL_MODEL,ORIGINAL_ROOT,ORIGINAL_ROOT).get("ok",false),"helper rejects writes to the original content root")
	var second_root:=out.path_join("second_content")
	var second_model:=second_root.path_join("packs/default/assets/"+SOURCE_SHA+".glb")
	check(DirAccess.make_dir_recursive_absolute(second_root)==OK,"create second caller-owned content root")
	var second:Dictionary=Relocate.rekey(temp_model,second_model,temp_root,second_root)
	check(second.get("ok",false) and not FileAccess.file_exists(temp_model) and not FileAccess.file_exists(second_model),"helper relocates from an absent original GLB to an absent temporary GLB")
	var conflict_root:=out.path_join("conflict_content")
	var conflict_model:=conflict_root.path_join("packs/default/assets/"+SOURCE_SHA+".glb")
	var conflict_index:=Writer.index_path(conflict_model,conflict_root)
	check(DirAccess.make_dir_recursive_absolute(conflict_index.get_base_dir())==OK,"create isolated conflict fixture")
	var conflict_file:=FileAccess.open(conflict_index,FileAccess.WRITE)
	if conflict_file==null:printerr("Cannot create isolated conflict marker");quit(2);return
	conflict_file.store_string("existing fixture data");conflict_file.close()
	var conflict_sha:=FileAccess.get_sha256(conflict_index)
	var conflict:Dictionary=Relocate.rekey(ORIGINAL_MODEL,conflict_model,ORIGINAL_ROOT,conflict_root)
	check(not conflict.get("ok",false) and conflict.get("reason","")=="target_conflict" and FileAccess.get_sha256(conflict_index)==conflict_sha,"different existing target fails without overwrite")
	check(not FileAccess.file_exists(Writer.directory(conflict_root).path_join(payload_sha+".scn")) and not FileAccess.file_exists(Metadata.path_for(conflict_model,conflict_root)),"preflight conflict leaves other targets uncreated")
	var original_meta:Dictionary=Metadata.read(ORIGINAL_MODEL,ORIGINAL_ROOT,SOURCE_SHA)
	var relocated_meta:Dictionary=Metadata.read(temp_model,temp_root,SOURCE_SHA)
	check(not original_meta.is_empty() and not relocated_meta.is_empty(),"both real metadata reads hit")
	if not original_meta.is_empty() and not relocated_meta.is_empty():
		check(relocated_meta.path==temp_model and relocated_meta.native_source_sha==SOURCE_SHA,"relocated metadata identifies temporary logical path")
		check(relocated_meta.local_bounds==original_meta.local_bounds and relocated_meta.memory==original_meta.memory and relocated_meta.native_payload_sha==original_meta.native_payload_sha,"native metadata bounds, admission and product identity unchanged")
	var original:Dictionary=Native.read(ORIGINAL_MODEL,SOURCE_SHA,ORIGINAL_ROOT,true)
	var relocated:Dictionary=Native.read(temp_model,SOURCE_SHA,temp_root,true)
	check(original.get("hit",false) and relocated.get("hit",false),"trusted native reader loads both products")
	if original.get("hit",false) and relocated.get("hit",false):
		check(relocated.source_digest==SOURCE_SHA and relocated.bytes==original.bytes,"native source digest and product size preserved")
		var a:Array=geometry(original.packed);var b:Array=geometry(relocated.packed)
		check(not a.is_empty() and a==b,"CPU geometry keys, surface counts, faces and bounds match")
	check(not Native.read(temp_model,"0".repeat(64),temp_root,true).get("hit",false),"wrong expected source identity is rejected")
	check(not Native.read(temp_model,SOURCE_SHA,temp_root,false).get("hit",false),"strict read rejects missing temporary GLB")
	check(not FileAccess.file_exists(temp_model),"trusted relocation did not materialize a GLB")
	check(FileAccess.get_sha256(original_index)==FileAccess.get_sha256(target_index) and FileAccess.get_sha256(original_descriptor)==FileAccess.get_sha256(target_descriptor) and FileAccess.get_sha256(original_product)==FileAccess.get_sha256(target_product),"original and temporary native bytes remain identical")
	var result:={"passed":passed,"failed":failed,"source":ORIGINAL_MODEL,"source_sha256":SOURCE_SHA,"temporary_root":temp_root,
		"original_index":original_index,"temporary_index":target_index,"payload_sha256":payload_sha,"native_product_bytes":int(original_info.bytes),
		"original_descriptor_sha256":FileAccess.get_sha256(original_descriptor),"temp_descriptor_sha256":FileAccess.get_sha256(target_descriptor),
		"helper_manifest":built,"second_helper_manifest":second,"conflict_reason":conflict.get("reason",""),
		"note":"No GLB is copied; the temporary GLB does not exist. Trusted readers use native index/metadata/product and the packed product declares no external ResourceLoader dependencies; OS file opens were not independently traced. Not a full-map/native dependency closure or performance result."}
	var report:=FileAccess.open(out.path_join("result.json"),FileAccess.WRITE)
	if report==null:printerr("Cannot write isolated result");quit(2);return
	report.store_string(JSON.stringify(result,"\t"));report.close()
	print("NATIVE_REKEY_FIXTURE passed=",passed," failed=",failed)
	quit(0 if failed==0 else 1)
