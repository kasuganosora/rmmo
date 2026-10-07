extends RefCounted
## One private, linear float texel per wind controller, never a global clock.
## Vertex shaders sample current world velocity and time without CPU LOD scans.
var image:Image
var texture:ImageTexture
var value:=Vector4(INF,INF,INF,INF)
var updates:=0

func update(wind:Vector3,time:float)->void:
	var next:=Vector4(wind.x,wind.y,wind.z,time)
	if next==value:return
	value=next
	if image==null:image=Image.create(1,1,false,Image.FORMAT_RGBAF)
	image.set_pixel(0,0,Color(wind.x,wind.y,wind.z,time))
	if texture==null:texture=ImageTexture.create_from_image(image)
	else:texture.update(image)
	updates+=1
