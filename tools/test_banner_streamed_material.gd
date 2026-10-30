extends SceneTree
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Wind=preload("res://scripts/world3d/wind_material.gd")
var failed:=0
class NoReadback extends Texture2D:
	var reads:=0
	func _get_width()->int:return 2048
	func _get_height()->int:return 1024
	func _has_alpha()->bool:return true
	func _get_image()->Image:reads+=1;return null
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func _init()->void:call_deferred("run")
func run()->void:
	var path:=preload("res://scripts/world3d/map_paths.gd").external_root().path_join("banner-probe.png")
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.save_png(path)
	var owner:=NoReadback.new();Paint._store_texture(path,owner)
	var source:=PlaneMesh.new();source.orientation=PlaneMesh.FACE_Z
	var before:=source.surface_get_arrays(0)
	for shape:String in ["pointed","rectangle","swallowtail"]:
		for design:String in ["flag","emblem"]:
			var settings:=Banner.defaults().merged({"shape":shape,"design":design,"texture_path":path},true)
			var mesh:=Banner.build(source,settings)
			check(mesh!=null,shape+" "+design+" builds")
			if mesh==null:continue
			var material:StandardMaterial3D=mesh.surface_get_material(0)
			check(material.detail_albedo==owner and material.albedo_texture==null,"source texture shared without baked replacement")
			check(material.detail_enabled and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"transparent design mixes over opaque cloth")
			check(preload("res://scripts/world3d/wind_response.gd").material_error(material).is_empty(),"actual wind admission accepts streamed banner detail")
			if design=="emblem":
				check(material.detail_uv_layer==BaseMaterial3D.DETAIL_UV_2 and not mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2].is_empty(),"emblem gets independent UV2")
				check(material.detail_mask==Banner.emblem_mask(Banner.emblem_rect(Vector2i(2048,1024))),"coverage mask shared across shapes")
	check(owner.reads==0,"all styles perform zero source texture readbacks")
	check(Banner.emblem_rect(Vector2i(2048,1024))==Rect2i(86,170,340,170),"original emblem layout preserved")
	check(source.surface_get_arrays(0)==before,"source mesh remains unchanged")
	var unsupported:=StandardMaterial3D.new();unsupported.detail_enabled=true;unsupported.normal_enabled=true
	check(not preload("res://scripts/world3d/wind_response.gd").material_error(unsupported).is_empty(),"unimplemented detail normal blending remains rejected")
	unsupported.normal_enabled=false;unsupported.detail_normal=owner
	check(not preload("res://scripts/world3d/wind_response.gd").material_error(unsupported).is_empty(),"unimplemented detail normal texture remains rejected")
	Paint.refresh_sources();Banner._meshes.clear();Banner._masks.clear()
	print("BANNER_STREAMED_MATERIAL_FAILED=",failed);quit(1 if failed else 0)
