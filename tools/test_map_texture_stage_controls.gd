extends SceneTree
## The partial texture arm must keep native geometry without whitening paints.
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Writer=preload("res://scripts/world3d/white_native_asset_writer.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prefetch=preload("res://scripts/world3d/target_scene_prefetch.gd")
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if ok:passed+=1
	else:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	check(not Native.active() and not Controls.white_materials and not Controls.discard_map_textures,"ordinary startup leaves diagnostic routes disabled")
	Controls.enable_native_geometry_only()
	check(Native.active() and Writer.active(),"partial textures retain the same native product and metadata readers")
	check(not Controls.white_materials and not Controls.discard_map_textures,"native product choice does not disable map textures or whiten procedural materials")
	var white:=Controls.white_material(BaseMaterial3D.CULL_DISABLED)
	check(white.cull_mode==BaseMaterial3D.CULL_DISABLED and white.albedo_color==Color.WHITE,"imported geometry retains canonical culling material")
	var definition:={"name":"stage_contract","color":[0.2,0.4,0.6,1.0],"roughness":0.75}
	var material:=Paint.make_material(definition)
	check(material!=white and material.albedo_color.is_equal_approx(Color(0.2,0.4,0.6,1.0)) and material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"procedural material retains authored color and shading")
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd");policy.verify_packages=false
	var template=preload("res://scripts/world3d/asset_spec_template.gd")
	var packed:=PackedScene.new();packed.set_meta(template.META,{"white_generation":Controls.white_generation,"generic":false})
	check(not template.supports(packed,{}),"texture stage cannot opt arbitrary colored packed scenes into white-only templates")
	packed.set_meta("white_native_geometry",true)
	check(template.supports(packed,{}),"unpainted native geometry retains existing worker template preparation")
	check(not template.supports(packed,{"surface_paint":[]}) and not template.supports(packed,{},true),"real face paint and local collisions retain their complete adapter paths")
	var folder:=preload("res://scripts/world3d/map_paths.gd").cache_directory("map_texture_stage_%d"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var map_path:=folder.path_join("map.gltf");var file:=FileAccess.open(map_path,FileAccess.WRITE);file.store_string("test scope");file.close()
	var invalid:=definition.duplicate();invalid.texture_path=folder.path_join("missing.png")
	var record:={"kind":"box","terrain_material":invalid}
	check(Prefetch.plan([record],folder,map_path,FileAccess.get_sha256(map_path),{}).is_empty(),"native geometry prefetch still accounts for required map textures")
	DirAccess.remove_absolute(map_path);DirAccess.remove_absolute(folder)
	Controls.enable_white_materials();Controls.discard_map_textures=true;Controls.native_geometry_only=false
	check(Native.active() and Paint.make_material(definition)==Controls.white_material(),"historical all-white control remains available")
	print("MAP_TEXTURE_STAGE passed=",passed," failures=",failures)
	quit(1 if failures else 0)
