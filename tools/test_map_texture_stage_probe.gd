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
	check(Probe.map_texture_stage_argument_error(PackedStringArray(["--mesh-only","--white-material","--without-map-textures"])).is_empty(),"existing white arguments retain their contract")
	for flag:String in ["--white-material","--without-map-textures","--without-compiled"]:
		var before:=PackedStringArray([flag]);before.append_array(stage)
		var after:=stage.duplicate();after.append(flag)
		check(not Probe.map_texture_stage_argument_error(before).is_empty() and Probe.map_texture_stage_argument_error(before)==Probe.map_texture_stage_argument_error(after),"conflicting stage options fail independent of order: "+flag)
	check(not Probe.map_texture_stage_argument_error(PackedStringArray(["--map-texture-stage"])).is_empty(),"stage cannot accidentally start ordinary gameplay")
	var empty:={"outputs":0,"consumers":0,"retained_bytes":0}
	check(Probe.texture_pixels_settled(empty),"fully retired pixel pool permits ready")
	for field:String in ["outputs","consumers","retained_bytes"]:
		var pending:=empty.duplicate();pending[field]=1
		check(not Probe.texture_pixels_settled(pending),"empty geometry jobs do not hide remaining pixel "+field)
	check(not Probe.texture_pixels_settled({}),"missing pixel diagnostics cannot pass texture readiness")
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
	painted.next_pass=null;white.albedo_texture=null;white.normal_texture=null
	print("MAP_TEXTURE_STAGE_PROBE failures=",failures)
	quit(0 if failures==0 else 1)
