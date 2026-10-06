extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const SkinMaterial=preload("res://scripts/char/character_skin_material.gd")
const LEGACY_LIGHT="""
void light() {float d=clamp(dot(NORMAL,LIGHT)*0.25+0.75,0.0,1.0);DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*d*0.12/PI;}
"""
func _initialize()->void:call_deferred("run")
func capture()->Image:
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	var frame:=root.get_texture().get_image();frame.convert(Image.FORMAT_RGB8);return frame
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Requires real renderer");quit(1);return
	root.size=Vector2i(640,900)
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	studio.model.play("idle","front_left",true);studio.model.pose_at(0)
	var body:MeshInstance3D=studio.model.gear.Body.filter(func(m):return m.name=="Body")[0]
	var face:MeshInstance3D=studio.model.gear.Body.filter(func(m):return m.name=="Face")[0]
	var body_material:Material=body.material_override;var face_material:Material=face.get_surface_override_material(0)
	var current:=await capture()
	var legacy:=ShaderMaterial.new();legacy.shader=Shader.new()
	legacy.shader.code="shader_type spatial;render_mode specular_disabled;uniform vec4 skin_color:source_color;void fragment(){ALBEDO=skin_color.rgb;EMISSION=ALBEDO*0.65;ROUGHNESS=1.0;}"+LEGACY_LIGHT
	legacy.set_shader_parameter("skin_color",Color("ffeadb"));body.material_override=legacy
	var face_legacy:ShaderMaterial=face_material.duplicate();var face_shader:=Shader.new()
	face_shader.code=face_legacy.shader.code.replace(SkinMaterial.LIGHT,LEGACY_LIGHT).replace("EMISSION = ALBEDO * skin_fill(NORMAL,INV_VIEW_MATRIX);","EMISSION = ALBEDO * 0.65;")
	face_legacy.shader=face_shader;face.set_surface_override_material(0,face_legacy)
	var before:=await capture()
	body.material_override=body_material;face.set_surface_override_material(0,face_material)
	var comparison:=Image.create(1280,900,false,Image.FORMAT_RGB8)
	comparison.blit_rect(before,Rect2i(0,0,640,900),Vector2i.ZERO);comparison.blit_rect(current,Rect2i(0,0,640,900),Vector2i(640,0))
	comparison.save_png(Art.review_path("character_3d/skin_material_before_after.png"))
	# Actual skin pixels, excluding clothes, hair, face and background.
	var mask_material:=ShaderMaterial.new();mask_material.shader=Shader.new();mask_material.shader.code="shader_type spatial;render_mode unshaded;void fragment(){ALBEDO=vec3(1.0,0.0,1.0);}"
	body.material_override=mask_material;var mask:=await capture();body.material_override=body_material
	studio.lighting.rotation.y=PI/2;var rotated:=await capture()
	var count:=0;var changed:=0;var clipped:=0
	var sums:=Vector2.ZERO;var squared:=Vector2.ZERO
	for y in current.get_height():
		for x in current.get_width():
			var pixel:Color=mask.get_pixel(x,y)
			if pixel.r<.95 or pixel.b<.95 or pixel.g>.05:continue
			var old:Color=before.get_pixel(x,y);var new:Color=current.get_pixel(x,y);var moved:Color=rotated.get_pixel(x,y)
			var luminance:=Vector2(old.get_luminance(),new.get_luminance());sums+=luminance;squared+=luminance*luminance;count+=1
			if absf(new.get_luminance()-moved.get_luminance())>.03:changed+=1
			if minf(new.r,minf(new.g,new.b))>.985:clipped+=1
	var variance:=squared/count-(sums/count)*(sums/count)
	var report={"skin_pixels":count,"flat_variance":variance.x,"new_variance":variance.y,"reacts_to_light_ratio":float(changed)/count,"white_clipping_ratio":float(clipped)/count,"comparison":"left=previous flat fill; right=regenerated material; identical geometry/camera/lights"}
	var file=FileAccess.open(Art.review_path("character_3d/skin_lighting_metrics.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
	print(report)
	var failed:bool=count<1000 or variance.y<variance.x*1.4 or float(changed)/count<.2 or float(clipped)/count>.05
	studio.free();print("FAIL skin lighting" if failed else "PASS visible skin form, light response and controlled highlights");quit(1 if failed else 0)
