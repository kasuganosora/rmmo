extends "res://tools/test_world3d_mcp.gd"
const Library = preload("res://scripts/world_editor/asset_library.gd")
const Embedded = preload("res://scripts/world3d/embedded_glb.gd")

func write_glb(path: String, data: Dictionary, binary: PackedByteArray) -> void:
	var encoded := JSON.stringify(data).to_utf8_buffer()
	while encoded.size() % 4: encoded.append(32)
	while binary.size() % 4: binary.append(0)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_32(0x46546c67); file.store_32(2); file.store_32(28 + encoded.size() + binary.size())
	file.store_32(encoded.size()); file.store_32(0x4e4f534a); file.store_buffer(encoded)
	file.store_32(binary.size()); file.store_32(0x004e4942); file.store_buffer(binary); file.close()

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	var directory := Paths.external_root().path_join("__embedded_glb_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"), FileAccess.WRITE).store_string('{"id":"embedded_glb","name":"Temporary embedded GLB test"}')
	var binary := PackedFloat32Array([0,0,0, 1,0,0, 0,1,0, 0,0,1, 0,0,1, 0,0,1]).to_byte_array()
	var pixels := Image.create(2,2,false,Image.FORMAT_RGBA8); pixels.fill(Color(.3,.6,.9,1))
	var png := pixels.save_png_to_buffer(); binary.append_array(png)
	var data := {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0,1]}],"nodes":[{"name":"FlagA","mesh":0,"weights":[.75],"extras":{"rmmo_collision":"none","rmmo_wind":{"profile":"cloth","anchor":"top"}}},{"name":"FlagB","mesh":0,"translation":[2,0,0],"weights":[.25]}],"meshes":[{"weights":[.2],"primitives":[{"attributes":{"POSITION":0},"targets":[{"POSITION":1}],"material":0}]}],"materials":[{"name":"ExactPBR","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.65},"doubleSided":true}],"textures":[{"source":0,"sampler":0}],"samplers":[{"magFilter":9728,"minFilter":9728}],"images":[{"bufferView":2,"mimeType":"image/png"}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,1],"max":[0,0,1]}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":png.size()}],"buffers":[{"byteLength":binary.size()}]}
	var source := directory.path_join("source.glb"); write_glb(source,data,binary)
	check(Embedded.can_copy(source),"strict embedded fixture is eligible")
	var library := Library.new(directory.path_join("input_assets"))
	var imported: Dictionary = library.import_file(source)
	check(imported.ok,"embedded import succeeds")
	if not imported.ok: quit(1); return
	var target: String = imported.entry.asset_path
	check(FileAccess.get_file_as_bytes(source)==FileAccess.get_file_as_bytes(target),"import source/output bytes identical")
	var again: Dictionary = library.import_file(source)
	check(again.ok and again.entry.asset_path==target and library.entries.size()==1,"repeat source import retains same hash and one entry")
	var other := Library.new(directory.path_join("other_assets")); var copied: Dictionary = other.import_file(target)
	check(copied.ok and FileAccess.get_file_as_bytes(copied.entry.asset_path)==FileAccess.get_file_as_bytes(source),"cross-library import cannot inflate bytes")
	var model := Library.instantiate_preview(target)
	var meshes: Array = preload("res://scripts/world3d/surface_materials.gd").meshes(model)
	check(meshes.size()==2 and is_equal_approx(meshes[0].get_blend_shape_value(0),.75) and is_equal_approx(meshes[1].get_blend_shape_value(0),.25),"shared mesh distinct node morph defaults restored without export")
	model.free()
	var damaged := data.duplicate(true); damaged.images[0].bufferView=99
	var broken := directory.path_join("broken.glb"); write_glb(broken,damaged,binary)
	check(not Embedded.can_copy(broken),"invalid image view rejects raw-copy eligibility")
	var before := library.entries.duplicate(true); var revision := FileAccess.get_sha256(library.directory.path_join("library.json"))
	FileAccess.open(broken,FileAccess.WRITE).store_string("not GLB")
	check(not library.import_file(broken).ok and library.entries==before and FileAccess.get_sha256(library.directory.path_join("library.json"))==revision,"invalid import has no catalog side effects")
	var bad_png := binary.duplicate(); bad_png[72]=0; write_glb(broken,data,bad_png)
	check(not library.import_file(broken).ok and library.entries==before,"corrupt embedded image fails without catalog changes")
	for change in [{"extensionsUsed":["KHR_materials_unlit"]},{"extras":{"uri":"external.bin"}},{"buffers":[{"byteLength":binary.size(),"uri":"external.bin"}]}]:
		write_glb(broken,data.merged(change,true),binary); check(not Embedded.can_copy(broken),"unknown extension or URI stays on packing fallback")
	var external := data.duplicate(true); external.buffers[0].uri="external.bin"; external.buffers[0].byteLength=binary.size(); external.images[0]={"uri":"external.png"}
	var gltf := directory.path_join("external.gltf")
	FileAccess.open(gltf,FileAccess.WRITE).store_string(JSON.stringify(external))
	FileAccess.open(directory.path_join("external.bin"),FileAccess.WRITE).store_buffer(binary)
	FileAccess.open(directory.path_join("external.png"),FileAccess.WRITE).store_buffer(png)
	var packed: Dictionary = library.import_file(gltf)
	check(packed.ok and Embedded.can_copy(packed.entry.asset_path),"external glTF still packs all dependencies")
	if not packed.ok: quit(1); return
	DirAccess.remove_absolute(directory.path_join("external.bin")); DirAccess.remove_absolute(directory.path_join("external.png"))
	var packed_model := Library.instantiate_preview(packed.entry.asset_path)
	check(packed_model!=null,"packed fallback works after external dependencies removed")
	if packed_model!=null: packed_model.free()
	var doc := Doc.new(); var path := directory.path_join("map.gltf"); check(doc.save(path)==OK,"temporary HTTP map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	editor._assets=library; editor._shared_assets=[]
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"3D HTTP server starts")
	var discovery:=await rpc("tools/list"); check(discovery.result.tools.any(func(t):return t.name=="save_prefab"),"3D save_prefab discovered")
	var placed:=await call_tool("place_asset",{"asset_id":target,"position":[0,0,0]})
	await call_tool("select_objects",{"ids":placed.ids})
	var saved:=await call_tool("save_prefab",{"name":"Exact GLB prefab","pack_root":directory})
	var payload:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(saved.entry.prefab_path)); var packaged: String=directory.path_join("assets").path_join(payload.records[0].asset_path)
	check(FileAccess.get_file_as_bytes(packaged)==FileAccess.get_file_as_bytes(source),"HTTP prefab cross-library dependency bytes identical")
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[5,0,0]}); await call_tool("undo"); await call_tool("redo")
	var snapshot: Dictionary=editor._doc.recovery_snapshot(); await call_tool("save_prefab",{"name":"","pack_root":directory},false)
	check(equivalent(snapshot,editor._doc.recovery_snapshot()),"invalid HTTP capture leaves document unchanged")
	await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(editor._doc.records.size()==2 and not editor._dirty,"HTTP save/reopen keeps both independent instances even without generated thumbnails")
	editor.queue_free(); await settle(); print("EMBEDDED_GLB_IMPORT failures=",failed); quit(0 if failed==0 else 1)
