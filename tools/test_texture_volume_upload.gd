extends SceneTree
## Exact byte round trips for whole-mipmap initialization, including odd
## volume depths and slice sizes smaller than the transfer offset alignment.
var failures:Array[String]=[]
var rows:Array=[]
var output:=""
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	for dimensions:Vector3i in [Vector3i(4,4,4),Vector3i(5,7,3),Vector3i(1,1,9),Vector3i(17,19,9),Vector3i(7,5,1)]:
		for channels:int in [1,4]:
			var format:=RDTextureFormat.new()
			format.texture_type=RenderingDevice.TEXTURE_TYPE_3D
			format.width=dimensions.x;format.height=dimensions.y;format.depth=dimensions.z
			format.format=RenderingDevice.DATA_FORMAT_R8_UNORM if channels==1 else RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
			format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
			format.mipmaps=1+int(floor(log(float(maxi(dimensions.x,maxi(dimensions.y,dimensions.z))))/log(2.)))
			var expected:=PackedByteArray();var size:=dimensions
			for mip:int in format.mipmaps:
				for z:int in size.z:
					for y:int in size.y:
						for x:int in size.x:
							for channel:int in channels:expected.append((mip*31+z*17+y*11+x*7+channel*53)%256)
				size=Vector3i(maxi(1,size.x>>1),maxi(1,size.y>>1),maxi(1,size.z>>1))
			var texture:=rd.texture_create(format,RDTextureView.new(),[expected])
			var actual:=rd.texture_get_data(texture,0) if texture.is_valid() else PackedByteArray()
			var ok:=texture.is_valid() and actual==expected
			rows.append({"dimensions":str(dimensions),"channels":channels,"mipmaps":format.mipmaps,"bytes":expected.size(),"roundtrip":ok})
			if not ok:failures.append(str(rows.back()))
			if texture.is_valid():rd.free_rid(texture)
	rd.free()
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"\t"))
	print("TEXTURE_VOLUME_UPLOAD cases=",rows.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
