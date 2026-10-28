extends SceneTree
## Transaction/identity regression; default run uses the headless renderer and
## no HTTP/editor. --native is reserved for the later coordinated GPU suite.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Embedded=preload("res://scripts/world3d/embedded_glb.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var failures:=0
var checks:=0
var native:=false

func _init()->void:call_deferred("run")

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("%s: %s"%["PASS" if value else "FAIL",label])

func write_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes);file.close()

func write_glb(path:String,data:Dictionary,binary:PackedByteArray)->void:
	var json:=JSON.stringify(data).to_utf8_buffer();binary=binary.duplicate()
	while json.size()%4:json.append(32)
	while binary.size()%4:binary.append(0)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+json.size()+binary.size())
	file.store_32(json.size());file.store_32(0x4e4f534a);file.store_buffer(json)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close()

func fixture(morph:bool=false)->Dictionary:
	# Nonzero extent on each axis avoids the engine's minimum flat-AABB epsilon.
	var binary:=PackedFloat32Array([0,0,0,1,0,0,0,1,0.5]).to_byte_array()
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0,1]}],"nodes":[{"name":"One","mesh":0,"extras":{"artwork_slot":"import-fixture"}},{"name":"Two","mesh":0,"translation":[2,0,0]}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}],"materials":[{"name":"ExactColor","pbrMetallicRoughness":{"baseColorFactor":[0.2,0.4,0.6,1.0],"metallicFactor":0.0,"roughnessFactor":0.7}}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0.5]}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36}],"buffers":[{"byteLength":36}]}
	if morph:
		binary.append_array(PackedFloat32Array([0,0,1,0,0,1,0,0,1]).to_byte_array())
		data.buffers[0].byteLength=binary.size()
		data.bufferViews.append({"buffer":0,"byteOffset":36,"byteLength":36})
		data.accessors.append({"bufferView":1,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,1],"max":[0,0,1]})
		data.meshes[0].weights=[0.2];data.meshes[0].primitives[0].targets=[{"POSITION":1}]
		data.nodes[0].weights=[0.75];data.nodes[1].weights=[0.25]
	return {"data":data,"binary":binary}

func no_staging(folder:String)->bool:
	for filename in DirAccess.get_files_at(folder):
		if filename.begins_with("import_"):return false
	return true

func run()->void:
	native="--native" in OS.get_cmdline_user_args()
	if native and DisplayServer.get_name()=="headless":
		check(false,"--native requires coordinated GPU renderer");quit(1);return
	var folder:=Paths.cache_directory("import_preparation_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	# Native products/footprints are derived into this isolated test root.
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override;manager.content_root_override=folder
	var f:=fixture();var source:=folder.path_join("source.glb")
	write_glb(source,f.data,f.binary)
	var bytes:=FileAccess.get_file_as_bytes(source);var digest:=FileAccess.get_sha256(source)
	check(Embedded.can_copy(source),"self-contained fixture takes byte-preserving staging path")
	var prepared:=Compiled.prepare_source(source)
	check(prepared.error==OK and prepared.current() and prepared.parse_count==1,"one validated parse binds complete source SHA")
	var first:=prepared.get_scene() as Node3D
	check(first!=null and is_same(first,prepared.get_scene()) and prepared.scene_count==1,"bounds and native builder borrow the same scene")
	if first==null:prepared.dispose();manager.content_root_override=old_root;quit(1);return
	var expected:=Library.bounds_of(first)
	check(expected.is_equal_approx(AABB(Vector3.ZERO,Vector3(3,1,0.5))),"bounds include both independently translated mesh instances")
	check(Io.extras_of(Io.find_named(first,"One")).get("artwork_slot")=="import-fixture","generated scene preserves authored extras")
	var state_ref:WeakRef=weakref(prepared.state);var document_ref:WeakRef=weakref(prepared.document);var scene_id:=first.get_instance_id()
	first=null;prepared.dispose();prepared.dispose()
	check(prepared.disposed and prepared.state==null and prepared.document==null and prepared.scene==null,"owner disposal is complete and idempotent")
	check(state_ref.get_ref()==null and document_ref.get_ref()==null and not is_instance_id_valid(scene_id),"disposal releases state/document and borrowed scene before footprint phase")
	check(prepared.get_scene()==null and not prepared.relocate(source),"disposed owner cannot generate or rebind")
	prepared=Compiled.prepare_source(source)
	var changed:=bytes.duplicate();changed[changed.size()-1]^=1;write_bytes(source,changed)
	check(not prepared.current() and prepared.get_scene()==null,"source replacement after parse blocks scene generation")
	prepared.dispose();write_bytes(source,bytes)
	prepared=Compiled.prepare_source(source)
	var other:=folder.path_join("other.glb");write_bytes(other,changed)
	check(not prepared.relocate(other) and prepared.path==source,"relocation rejects mismatching final bytes without changing owner identity")
	write_bytes(other,bytes)
	check(prepared.relocate(other) and prepared.current(),"relocation accepts only identical complete bytes")
	prepared.dispose()
	prepared=Compiled.prepare_source(source)
	var mismatched:=Library._compile_import(other,prepared)
	check(not mismatched.ok and mismatched.reason=="prepared_source_path" and prepared.disposed and not Library._compiled_imports.has(other),"mismatched compile path releases owner without publishing a success identity")
	var library:=Library.new(folder.path_join("library"))
	check(not Library._import_product_gate(source,{"ok":false,"reason":"unsupported_scene"},{}).ok,"native build failure blocks catalog publication")
	check(not Library._import_product_gate(source,{"ok":true,"footprint":{"ok":false}},{}).ok,"footprint failure blocks catalog publication")
	var imported:Dictionary=library.import_file(source)
	if not native:
		check(not imported.get("ok",false) and imported.get("compiled_asset",{}).get("reason","")=="graphics_required","headless import rejects when native product cannot be built")
		check(library.entries.is_empty() and not FileAccess.file_exists(library.directory.path_join("library.json")),"failed native build never publishes catalog entry")
		check(no_staging(library.directory) and FileAccess.get_sha256(source)==digest,"failed native import preserves source and removes staging")
		manager.content_root_override=old_root
		print("ASSET_IMPORT_PREPARATION checks=%d failures=%d native=%s"%[checks,failures,native]);quit(1 if failures else 0);return
	check(imported.get("ok",false),"cold library import succeeds")
	if not imported.get("ok",false):print(imported);manager.content_root_override=old_root;quit(1);return
	var target:String=imported.entry.asset_path
	check(imported.import_preparation.parse_count==1 and imported.import_preparation.scene_count==1,"cold embedded import performs one parse and one scene generation")
	check(FileAccess.get_file_as_bytes(target)==bytes and target.get_file()==digest+".glb","staged copy remains byte exact and content addressed")
	check(imported.import_preparation.source_sha==FileAccess.get_sha256(target),"import diagnostic is bound to final immutable GLB")
	check(imported.entry.bounds_position==[expected.position.x,expected.position.y,expected.position.z] and imported.entry.bounds_size==[expected.size.x,expected.size.y,expected.size.z],"catalog stores exact generated bounds")
	check(str(imported.entry.thumbnail_path).ends_with(digest+".png"),"thumbnail identity and path remain unchanged")
	check(not Library._scenes.has(target),"bounds preparation never publishes into runtime scene cache")
	check(no_staging(library.directory),"successful import removes staging filename")
	if native:
		check(imported.compiled_asset.ok and imported.compiled_asset.footprint.ok,"same prepared scene produces native product and offline footprint")
		var hit:=Compiled.read(target)
		check(hit.hit,"new product validates against final source and generator")
		if hit.hit:
			var model:=Compiled.instantiate(hit.packed)
			check(Library.bounds_of(model).is_equal_approx(expected),"native result keeps preview bounds")
			Drainer.dispose_scene(model);hit.clear()
		else:Compiled.dispose_miss(hit)
	var reopened:=Library.new(library.directory)
	check(reopened.entries==library.entries,"atomic catalog save/reopen preserves entry identity")
	var again:Dictionary=library.import_file(source)
	check(again.ok and library.entries.size()==1 and again.entry.asset_path==target,"repeat external source does not duplicate catalog entry")
	check(again.import_preparation.parse_count==1,"repeat staged source does not parse again for preview/native")
	var snapshot:=library.entries.duplicate(true);var revision:=FileAccess.get_sha256(library.directory.path_join("library.json"))
	write_bytes(target,changed)
	var rejected:=library.import_file(source)
	check(not rejected.ok and library.entries==snapshot and FileAccess.get_sha256(library.directory.path_join("library.json"))==revision,"corrupt content-addressed target rejects with no catalog changes")
	check(no_staging(library.directory),"corrupt-target rejection cleans staging")
	write_bytes(target,bytes)
	var conflict:=Library.new(folder.path_join("conflict"));DirAccess.make_dir_recursive_absolute(conflict.directory)
	write_bytes(conflict.directory.path_join("library.json"),"[]".to_utf8_buffer())
	var conflict_sha:=FileAccess.get_sha256(conflict.directory.path_join("library.json"))
	check(not conflict.import_file(source).ok and conflict.entries.is_empty(),"concurrent catalog revision rejects and rolls back in-memory entry")
	check(FileAccess.get_sha256(conflict.directory.path_join("library.json"))==conflict_sha and no_staging(conflict.directory),"catalog conflict preserves external catalog and cleans staging")
	var external:Dictionary=f.data.duplicate(true);external.buffers[0].uri="geometry.bin"
	var external_path:=folder.path_join("external.gltf")
	write_bytes(external_path,JSON.stringify(external).to_utf8_buffer());write_bytes(folder.path_join("geometry.bin"),f.binary)
	var converted:Dictionary=library.import_file(external_path)
	check(converted.get("ok",false),"external glTF dependency conversion succeeds")
	if converted.get("ok",false):
		check(converted.import_preparation.parse_count==2 and converted.import_preparation.scene_count==1,"conversion parses original then final GLB once each, generating only final scene")
		check(converted.import_preparation.source_sha==FileAccess.get_sha256(converted.entry.asset_path) and converted.import_preparation.source_sha!=FileAccess.get_sha256(external_path),"conversion never binds original glTF SHA/state to exported native product")
		check(Embedded.can_copy(converted.entry.asset_path),"converted model is self-contained")
		DirAccess.remove_absolute(folder.path_join("geometry.bin"))
		var model:=Library.instantiate_preview(converted.entry.asset_path)
		check(model!=null and Library.bounds_of(model).is_equal_approx(expected),"converted model still loads after original dependency removal")
		if model!=null:Drainer.dispose_scene(model)
	var m:=fixture(true);var morph_path:=folder.path_join("morph.glb");write_glb(morph_path,m.data,m.binary)
	var before_morph:Array=library.entries.duplicate(true)
	var before_morph_catalog:=FileAccess.get_sha256(library.directory.path_join("library.json"))
	var morph:Dictionary=library.import_file(morph_path)
	check(not morph.get("ok",false),"unsupported native geometry rejects instead of publishing GLB fallback")
	check(library.entries==before_morph and FileAccess.get_sha256(library.directory.path_join("library.json"))==before_morph_catalog,"unsupported native import leaves catalog unchanged")
	check(FileAccess.get_sha256(source)==digest,"all operations leave original source unchanged")
	manager.content_root_override=old_root
	print("ASSET_IMPORT_PREPARATION checks=%d failures=%d native=%s"%[checks,failures,native])
	quit(0 if failures==0 else 1)
