extends RefCounted
## One private, linear float texel per wind controller, never a global clock.
## Vertex shaders sample current world velocity and time without CPU LOD scans.
var image:Image # Last submitted state; replaced, never mutated after upload.
var texture:ImageTexture
var value:=Vector4(INF,INF,INF,INF)
var updates:=0

func update(wind:Vector3,time:float)->void:
	var next:=Vector4(wind.x,wind.y,wind.z,time)
	if next==value:return
	value=next
	# A separate render thread uploads queued images later.
	image=Image.create_from_data(1,1,false,Image.FORMAT_RGBAF,PackedFloat32Array([wind.x,wind.y,wind.z,time]).to_byte_array())
	if texture==null:texture=ImageTexture.create_from_image(image)
	else:texture.update(image)
	updates+=1
