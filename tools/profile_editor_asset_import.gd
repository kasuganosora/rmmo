extends SceneTree
## Single cold asset, private desktop GPU probe. Does not modify its input.
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")

func _initialize()->void:call_deferred("run")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var path:String=args[0];var output:String=args[1]
	var document:=GLTFDocument.new();var state:=GLTFState.new();var timings:={}
	await process_frame
	var mark:=Time.get_ticks_usec()
	var error:=document.append_from_file(path,state,0,path.get_base_dir())
	timings.append_ms=(Time.get_ticks_usec()-mark)/1000.
	if error!=OK:push_error(error_string(error));quit(1);return
	mark=Time.get_ticks_usec()
	var scene:Node=Io.generate_scene(document,state)
	timings.generate_ms=(Time.get_ticks_usec()-mark)/1000.
	if scene==null:quit(1);return
	mark=Time.get_ticks_usec()
	var cached:=Library.cache_scene(path,scene)
	timings.cache_pack_ms=(Time.get_ticks_usec()-mark)/1000.
	if not cached:quit(1);return
	mark=Time.get_ticks_usec()
	var instance:=Library.instantiate(path)
	timings.instantiate_ms=(Time.get_ticks_usec()-mark)/1000.
	var result:={"path":path,"ok":instance!=null,"timings":timings,"nodes":state.nodes.size(),"meshes":state.meshes.size(),"materials":state.materials.size(),"images":state.json.get("images",[]).size()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("EDITOR_ASSET_IMPORT_PROFILE ",JSON.stringify(result))
	if instance!=null:instance.free()
	Library._scenes.clear()
	for i in 3:await process_frame
	quit(0 if result.ok else 1)
