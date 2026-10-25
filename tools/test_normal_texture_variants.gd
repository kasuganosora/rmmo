extends SceneTree
## Regression for one source used as albedo and both normal conventions.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const EditorPrep=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var source:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
	if source.is_empty():quit(2);return
	Paint.refresh_sources()
	var definition:={"name":"same source roles","color":[1,1,1,1],"roughness":.8,"texture_path":source,"normal_path":source,"normal_format":"opengl"}
	var directx:Dictionary=definition.duplicate();directx.normal_format="directx"
	var color:Texture2D=Paint.texture(definition)
	var normal:Texture2D=Paint.texture(definition,"normal_path")
	var flipped:Texture2D=Paint.texture(directx,"normal_path")
	check(color!=null and normal!=null and flipped!=null,"all variants load")
	check(color!=normal and normal!=flipped,"normal convention and color role have distinct owners")
	check(color.get_image().get_format()==Image.FORMAT_DXT1,"albedo keeps RGB compression")
	check(normal.get_image().get_format()==Image.FORMAT_RGTC_RG,"normal selects RG compression")
	check(flipped.get_image().get_format()==Image.FORMAT_RGTC_RG,"DirectX normal selects converted RG compression")
	var record:={"terrain_material":definition,"road_kerb_material":directx}
	var requested:=Prep.sources(record)
	check(requested.size()==3,"prefab requests retain all three role/orientation variants")
	check(requested.has(source) and requested.has(source+"|normal") and requested.has(source+"|normal|flip_y"),"preparation keys match GPU variant keys")
	check(EditorPrep.requests(record,{}).is_empty(),"editor skips duplicate PNG work when every exact variant has a DDS")
	var packet:=Prep.prepare(requested,Prep.estimate(requested,source.get_base_dir()),source.get_base_dir())
	check(packet.error.is_empty() and packet.images.size()==3,"worker prepares complete role variants: "+str(packet.error))
	Paint._textures.clear()
	check(Paint.texture(definition)==color and Paint.texture(definition,"normal_path")==normal and Paint.texture(directx,"normal_path")==flipped,"weak catalog cannot cross variants after hot eviction")
	Paint.refresh_sources()
	check(Paint.texture(definition)!=color and Paint.texture(definition,"normal_path")!=normal,"source refresh clears both variant generations")
	color=Paint.texture(definition);normal=Paint.texture(definition,"normal_path");flipped=Paint.texture(directx,"normal_path")
	var images:Dictionary={}
	for key:String in requested:
		var pixels:=Image.create(16,8,true,Image.FORMAT_RGBA8);pixels.fill(Color(.3,.8,.5));pixels.set_meta("runtime_source_sha256","b".repeat(64));images[key]=pixels
	Paint.prepare_images(images)
	var fresh_color:Texture2D=Paint.texture(definition);var fresh_normal:Texture2D=Paint.texture(definition,"normal_path");var fresh_flip:Texture2D=Paint.texture(directx,"normal_path")
	check(fresh_color!=color and fresh_normal!=normal and fresh_flip!=flipped,"new prepared generation invalidates every role without mutating held owners")
	check(fresh_color!=fresh_normal and fresh_normal!=fresh_flip,"prepared publication retains distinct GPU variants")
	check(Paint.prepared_images.is_empty(),"each exact prepared variant is consumed once")
	var compressed_color:=FileAccess.get_file_as_bytes(source+".dxt1.dds")
	DirAccess.remove_absolute(source+".dxt1.dds");Paint.refresh_sources()
	color=Paint.texture(definition);normal=Paint.texture(definition,"normal_path")
	check(not color.get_image().is_compressed() and normal.get_image().get_format()==Image.FORMAT_RGTC_RG,"BC5-only normal sidecar never hijacks same-source albedo")
	check(EditorPrep.requests(record,{}).keys()==[source],"same-source albedo still prepares PNG when only normal has a DDS")
	var file:=FileAccess.open(source+".dxt1.dds",FileAccess.WRITE);file.store_buffer(compressed_color);file.close()
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var white:bool=controls.white_materials;var discard:bool=controls.discard_map_textures
	controls.enable_white_materials();controls.discard_map_textures=true;Paint.texture_profile_enabled=true;Paint.reset_profile()
	check(Paint.make_material(definition)!=null and Prep.sources(record)==requested and Prep.estimate(requested,source.get_base_dir()).rows.is_empty(),"white/discard preserves dependencies but prepares no textures")
	check(not Paint.has_compressed_sidecar(source,false,true),"white/discard bypasses sidecar filesystem lookup")
	check(Paint.profile_snapshot().counters.is_empty(),"white/discard performs no texture lookup, decode or upload")
	controls.white_materials=white;controls.discard_map_textures=discard;Paint.texture_profile_enabled=false
	print(JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
