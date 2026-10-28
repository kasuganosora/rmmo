extends "camera_probe.gd"
## File-format / partial initial upload contract for the shared CPU writer.
## Complete Image readback is intentional offline validation, never runtime IO.
const Product=preload("streamed_texture_product.gd")

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	Engine.max_fps=60
	if output.is_empty():push_error("--output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.scope="staged GSTF v1 byte preservation, including existing compressed blocks; no production import"
	check(ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming"),"streaming API exists")
	if failed:finish();return
	streaming=Engine.get_singleton("TextureStreaming")
	report.memory_before=streaming.call("get_memory_budget_bytes_used")
	check(Product.write(null,Image.new())==ERR_INVALID_PARAMETER,"writer rejects an absent file / empty image")
	for size:Vector2i in [Vector2i(1,1),Vector2i(7,11),Vector2i(64,32),Vector2i(256,128)]:
		for format:int in [Image.FORMAT_R8,Image.FORMAT_RG8,Image.FORMAT_RGB8,Image.FORMAT_RGBA8,Image.FORMAT_DXT1,Image.FORMAT_DXT5,Image.FORMAT_RGTC_R,Image.FORMAT_RGTC_RG]:
			var image:=Image.create(size.x,size.y,true,format)
			var bytes:=image.get_data()
			for index:int in bytes.size():bytes[index]=(index*73+index/97)&255
			image.set_data(size.x,size.y,true,format,bytes)
			var name:="%dx%d_format%d"%[size.x,size.y,format]
			var path:=output.path_join(name+".stex")
			write_stex(image,path)
			check(image.get_format()==format and image.get_data()==bytes,name+": writer does not mutate source pixels or compressed blocks")
			var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
			check(texture.call("load",path)==OK,name+": published format loads")
			var full:=texture.get_image()
			check(full.get_size()==size and full.get_format()==format and full.get_data()==bytes,name+": complete file mip chain preserves exact bytes")
			var mip:=mini(3,image.get_mipmap_count())
			var expected:=Image.create_from_data(maxi(1,size.x>>mip),maxi(1,size.y>>mip),image.get_mipmap_count()>mip,format,bytes.slice(image.get_mipmap_offset(mip)))
			var actual:=RenderingServer.texture_2d_get(texture.get_rid())
			# RD can expand RGB8 internally; texture_2d_get converts the readback
			# back to the original image format, so compare that exact byte chain.
			check(actual.get_size()==expected.get_size() and actual.get_format()==expected.get_format() and actual.get_data()==expected.get_data(),name+": initial GPU upload is only the expected mip tail")
			texture=null
			check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),name+": final release drains")
	finish()
