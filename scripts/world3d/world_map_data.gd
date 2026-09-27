extends RefCounted
## Shared cartographic projection of the full document, independent of residency.
var bounds:=Rect2()
var shapes:Array=[]
var markers:Array=[]
var title:="三维地图"
var pins:Array[Vector2]=[]

func build(root:Node)->void:
	shapes.clear();markers.clear()
	title=str(preload("res://scripts/world3d/gltf_map_io.gd").extras_of(root).get("map_name","三维地图"))
	var first:=true
	for spec in root.get_meta("stream_library",[]):
		if not spec.get("mesh") is Mesh:continue
		var box:AABB=spec.mesh.get_aabb()
		var transform:Transform3D=spec.transform
		var projected:=PackedVector2Array()
		for i in 8:
			var p:Vector3=transform*box.get_endpoint(i)
			projected.append(Vector2(p.x,p.z))
		var polygon:=Geometry2D.convex_hull(projected)
		var rect:=Rect2(projected[0],Vector2.ZERO)
		for p in projected:rect=rect.expand(p)
		bounds=rect if first else bounds.merge(rect);first=false
		var extra:Dictionary=spec.get("extras",{})
		var kind:=str(extra.get("kind",""))
		var center:=rect.get_center()
		if kind in ["npc","warp","gather"] or extra.get("hostile",false) or extra.get("ally",false):
			markers.append({"position":center,"id":str(spec.uuid),"kind":kind,"hostile":bool(extra.get("hostile",false)),"name":str(extra.get("name",kind))})
			continue
		if polygon.size()<4:continue
		var world_box:AABB=transform*box
		var color:=Color("68765b") if world_box.size.y<.6 else Color("8c8374")
		if kind=="water":color=Color("4b7888")
		shapes.append({"polygon":polygon,"bounds":rect,"color":color,"height":world_box.end.y})
	shapes.sort_custom(func(a,b):return a.height<b.height)
	if first:bounds=Rect2(-10,-10,20,20)
	bounds=bounds.grow(2)

func toggle_pin(point:Vector2)->void:
	for i in pins.size():
		if pins[i].distance_to(point)<1.5:pins.remove_at(i);return
	if pins.size()>=3:pins.pop_front()
	pins.append(point)
