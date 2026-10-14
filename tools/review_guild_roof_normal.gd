extends "res://tools/review_guild_reference_camera.gd"
## Affected-only terracotta normal review. No production material changes.
var expected_normal_scale:float=-1.0
var expected_normal_image:String=""
var source_roof_materials:Array=[]

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with('--normal-scale='):expected_normal_scale=float(arg.trim_prefix('--normal-scale='))
		if arg.begins_with('--normal-image='):expected_normal_image=arg.trim_prefix('--normal-image=')
	await super.run()

func roof_materials(scene:Node)->Array:
	var found:Dictionary={}
	for node in scene.find_children('*','MeshInstance3D',true,false):
		if node.mesh==null:continue
		for slot in node.mesh.get_surface_count():
			var material:=node.get_active_material(slot) as StandardMaterial3D
			if material==null or not 'terracotta' in material.resource_name or found.has(material):continue
			var image:Image=material.normal_texture.get_image() if material.normal_texture!=null else null
			var decoded:Dictionary={}
			if image!=null:
				decoded={"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"mipmap_count":image.get_mipmap_count()}
				# Production texture loading generates mip levels. Compare the PNG's
				# base level exactly, and keep the mip count as separate evidence.
				image.clear_mipmaps()
				image.convert(Image.FORMAT_RGBA8)
				decoded.rgba_sha256=sha(image.get_data())
			found[material]={"name":material.resource_name,"normal_enabled":material.normal_enabled,"normal_scale":material.normal_scale,"normal_texture":decoded,"normal_slot":"StandardMaterial3D.normal_texture; tangent-space RGB (no ORM channel selection)"}
	var results:Array=found.values()
	results.sort_custom(func(a,b):return str(a.name)<str(b.name))
	return results

func review_one(scene:Node,row:Dictionary,folder:String)->void:
	source_roof_materials=roof_materials(scene)
	await super.review_one(scene,row,folder)

func gallery(scene:Node,folder:String)->void:
	var native_materials:=roof_materials(scene)
	report.roof_normal_contract={"source":source_roof_materials,"native":native_materials,"expected_scale":expected_normal_scale,"expected_image_path":expected_normal_image}
	check(source_roof_materials.size()==1,'one unique terracotta material')
	check(stable(source_roof_materials)==stable(native_materials),'native preserves roof normal slot, scale and decoded pixels')
	var expected_pixels:String=""
	if not expected_normal_image.is_empty():
		var image:=Image.load_from_file(expected_normal_image)
		check(image!=null,'roof normal expected PNG decodes')
		if image!=null:
			image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8);expected_pixels=sha(image.get_data())
			report.roof_normal_contract.expected_rgba_sha256=expected_pixels
	for material in native_materials:
		check(material.normal_enabled,'native roof normal enabled')
		check(not material.normal_texture.is_empty(),'native roof normal texture loaded')
		if expected_normal_scale>=0:check(absf(material.normal_scale-expected_normal_scale)<.00001,'native roof normal scale matches source')
		if not expected_pixels.is_empty():check(material.normal_texture.get('rgba_sha256','')==expected_pixels,'native roof normal decoded pixels match exact embedded image')
	await super.gallery(scene,folder)
