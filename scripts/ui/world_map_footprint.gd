extends RefCounted
## WorldMapData emits closed convex hulls, including subpixel grass footprints.
## Use their known topology instead of an ear clipper sensitive to thin edges.
static func draw(item:RID,polygon:PackedVector2Array,color:Color,width:float)->void:
	var count:=polygon.size()
	if count>1 and polygon[0]==polygon[count-1]:count-=1
	if count<2:return
	for point in polygon:
		if not point.is_finite():return
	var indices:=PackedInt32Array()
	for corner in range(1,count-1):indices.append_array(PackedInt32Array([0,corner,corner+1]))
	if not indices.is_empty():RenderingServer.canvas_item_add_triangle_array(item,indices,polygon,PackedColorArray([color]))
	RenderingServer.canvas_item_add_polyline(item,polygon,PackedColorArray([color.darkened(.25)]),width,true)
