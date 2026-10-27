extends SceneTree
## Probe contract only: synthetic materials and scalar lease snapshots. No map,
## authored texture reads, renderer readback or GPU performance claim.
const Probe=preload("res://tools/profile_axel_game_pipeline.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var stage:=PackedStringArray(["--mesh-only","--map-texture-stage"])
	check(Probe.map_texture_stage_argument_error(stage).is_empty(),"isolated map texture stage is accepted")
	check(Probe.fixture_manifest_name(stage)=="fixture_manifest.json","map texture keeps the original fixture manifest")
	check(Probe.fixture_manifest_name(PackedStringArray(["--full-material-stage"]))=="full_fixture_manifest.json","full stage uses the full-native fixture manifest")
	check(Probe.map_texture_stage_argument_error(PackedStringArray(["--mesh-only","--white-material","--without-map-textures"])).is_empty(),"existing white arguments retain their contract")
	for flag:String in ["--white-material","--without-map-textures","--without-compiled"]:
		var before:=PackedStringArray([flag]);before.append_array(stage)
		var after:=stage.duplicate();after.append(flag)
		check(not Probe.map_texture_stage_argument_error(before).is_empty() and Probe.map_texture_stage_argument_error(before)==Probe.map_texture_stage_argument_error(after),"conflicting stage options fail independent of order: "+flag)
	check(not Probe.map_texture_stage_argument_error(PackedStringArray(["--map-texture-stage"])).is_empty(),"stage cannot accidentally start ordinary gameplay")
	var full:=PackedStringArray(["--mesh-only","--native-only","--full-material-stage"])
	check(Probe.map_texture_stage_argument_error(full).is_empty(),"full material stage accepts native-only mesh scope")
	var prepack:=full.duplicate();prepack.append("--full-native-worker-prepack")
	check(Probe.map_texture_stage_argument_error(prepack).is_empty(),"full stage explicitly accepts candidate worker prepack")
	check(not Probe.map_texture_stage_argument_error(PackedStringArray(["--mesh-only","--map-texture-stage","--full-native-worker-prepack"])).is_empty(),"worker prepack cannot be silently enabled outside full stage")
	var reuse:=full.duplicate();reuse.append("--full-native-template-reuse")
	check(Probe.map_texture_stage_argument_error(reuse).is_empty(),"full stage explicitly accepts template reuse")
	var plan_baseline:=reuse.duplicate();plan_baseline.append("--without-full-native-material-plan")
	check(Probe.map_texture_stage_argument_error(plan_baseline).is_empty(),"material-plan baseline keeps direct-template route")
	check(not Probe.map_texture_stage_argument_error(PackedStringArray(["--mesh-only","--native-only","--full-material-stage","--without-full-native-material-plan"])).is_empty(),"material-plan control requires direct-template route")
	check(not Probe.map_texture_stage_argument_error(PackedStringArray(["--mesh-only","--map-texture-stage","--full-native-template-reuse"])).is_empty(),"template reuse requires full stage")
	reuse.append("--full-native-worker-prepack")
	check(not Probe.map_texture_stage_argument_error(reuse).is_empty(),"template reuse cannot mix with worker packing experiment")
	for flag:String in ["--map-texture-stage","--white-material","--without-map-textures","--without-compiled"]:
		var conflict:=full.duplicate();conflict.append(flag)
		check(not Probe.map_texture_stage_argument_error(conflict).is_empty(),"full material stage rejects "+flag)
	check(not Probe.map_texture_stage_argument_error(PackedStringArray(["--mesh-only","--full-material-stage"])).is_empty(),"full material stage requires native products")
	var empty:={"outputs":0,"consumers":0,"retained_bytes":0}
	check(Probe.texture_pixels_settled(empty),"fully retired pixel pool permits ready")
	for field:String in ["outputs","consumers","retained_bytes"]:
		var pending:=empty.duplicate();pending[field]=1
		check(not Probe.texture_pixels_settled(pending),"empty geometry jobs do not hide remaining pixel "+field)
	check(not Probe.texture_pixels_settled({}),"missing pixel diagnostics cannot pass texture readiness")
	check(Probe.textured_stage_ready(false,false,{}),"white stage does not require a pixel queue")
	check(Probe.textured_stage_ready(true,true,empty),"full or map texture stage waits for idle and empty pixels")
	check(not Probe.textured_stage_ready(true,false,empty),"texture stage requires the queue to be idle")
	for field:String in ["outputs","consumers","retained_bytes"]:
		var pending:=empty.duplicate();pending[field]=1
		check(not Probe.textured_stage_ready(true,true,pending),"full or map texture stage blocks on shared pixel "+field)
	var white:=StandardMaterial3D.new();white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;white.albedo_color=Color.WHITE
	var info:Dictionary=Probe.texture_material_info(white)
	check(not info.nonwhite and info.textures.is_empty(),"canonical imported white material is not texture restoration proof")
	var painted:=StandardMaterial3D.new();painted.albedo_color=Color(.5,.2,.1)
	info=Probe.texture_material_info(painted)
	check(info.nonwhite and info.textures.is_empty(),"authored color alone does not count as a texture")
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var texture:=ImageTexture.create_from_image(image)
	white.albedo_texture=texture;white.normal_texture=texture
	info=Probe.texture_material_info(white)
	check(info.nonwhite and info.textures.size()==1,"bound textures on a white material count once per resource")
	painted.next_pass=white
	info=Probe.texture_material_info(painted)
	check(info.nonwhite and info.textures.size()==1,"next-pass textures are included without reading image pixels")
	painted.next_pass=null
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var surface:=ArrayMesh.new();surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);surface.surface_set_material(0,white)
	var visual:=MeshInstance3D.new();visual.mesh=surface;visual.material_override=painted
	var actual:=Probe.model_surface_material_info(visual,0)
	check(actual.overridden and actual.base.textures.size()==1 and actual.active.textures.is_empty(),"model base texture remains distinguishable from an untextured active override")
	surface.surface_set_material(0,painted);visual.material_override=white
	actual=Probe.model_surface_material_info(visual,0)
	check(actual.overridden and actual.base.textures.is_empty() and actual.active.textures.size()==1,"active paint cannot prove an imported base material has a texture")
	visual.free();white.albedo_texture=null;white.normal_texture=null
	print("MAP_TEXTURE_STAGE_PROBE failures=",failures)
	quit(0 if failures==0 else 1)
