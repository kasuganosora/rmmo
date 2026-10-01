extends SceneTree
const Assets=preload("res://scripts/char/character_axis_assets.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:=Art.path("characters/base/female_base_v2")
	var source:=Assets.build_materials()
	var tested:Dictionary={};var metrics:Array=[]
	for mode in [false,true]:
		var baked:=Assets.get_materials(folder,mode)
		assert(baked.materials.size()==source[mode].materials.size())
		for name in baked.materials:
			var material:Material=baked.materials[name];var original:Material=source[mode].materials[name]
			assert(material.resource_name==original.resource_name and material.render_priority==original.render_priority)
			if not material is ShaderMaterial:continue
			assert(material.shader.code==original.shader.code)
			for uniform:Dictionary in original.shader.get_shader_uniform_list():
				var expected:Variant=original.get_shader_parameter(uniform.name)
				var actual:Variant=material.get_shader_parameter(uniform.name)
				if not expected is Texture2D:
					assert(expected==actual);continue
				assert(actual is PortableCompressedTexture2D)
				if tested.has(actual):continue
				tested[actual]=true
				var before:Image=expected.get_image();var after:Image=actual.get_image()
				assert(before.get_size()==after.get_size() and before.has_mipmaps()==after.has_mipmaps())
				if after.is_compressed():assert(after.decompress()==OK)
				var mean:=0.0;var maximum:=0.0;var count:=0
				for y in range(0,before.get_height(),maxi(1,before.get_height()/64)):
					for x in range(0,before.get_width(),maxi(1,before.get_width()/64)):
						var a:=before.get_pixel(x,y);var b:=after.get_pixel(x,y)
						for axis in 4:
							var error:=absf(a[axis]-b[axis]);mean+=error;maximum=maxf(maximum,error);count+=1
				mean/=count
				metrics.append({"region":name,"map":uniform.name,"mean":mean,"max":maximum})
				assert(mean<.01 and maximum<.16,"Packed texture quality or channel order regression")
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_02/texture_quality.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"  "));file.close()
	print("PASS baked material shader/parameter/mipmap parity and BPTC sampled quality: ",tested.size()," textures")
	quit()
