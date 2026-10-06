extends SceneTree
const MapData=preload("res://scripts/world3d/world_map_data.gd")
func _initialize()->void:
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	var record={"uuid":"floor", "kind":"box", "position":[0,0,0],"size":[4,.2,4],"building":{"id":"house","part":"floor","role":"floor","floor":0}}
	var node=doc._mesh(record)
	assert(node.get_meta("extras").get("building",{})==record.building)
	node.free()
	var host:=Node.new();var specs:Array=[]
	var add=func(id:String,at:Vector3,size:Vector3,extras:Dictionary):
		var mesh:=BoxMesh.new();mesh.size=size
		specs.append({"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,at),"extras":extras})
	# L-shaped footprint must retain the open courtyard, regardless of upper roofs.
	add.call("a",Vector3(-3,0,0),Vector3(2,.2,8),{"building":{"role":"floor","floor":0}})
	add.call("b",Vector3(1,0,3),Vector3(6,.2,2),{"building":{"role":"floor","floor":0}})
	add.call("roof",Vector3(0,5,0),Vector3(8,1,8),{"building":{"role":"roof","floor":1}})
	for i in 1000:add.call(str(i),Vector3.ZERO,Vector3(.1,.1,.1),{"building":{"role":"hardware","floor":0}})
	add.call("portal",Vector3(10,0,0),Vector3.ONE,{"kind":"warp"})
	host.set_meta("stream_library",specs)
	var data:=MapData.new();data.build(host)
	assert(data.shapes.size()==2 and data.markers.size()==1 and data.markers[0].id=="portal")
	for shape in data.shapes:assert(not Geometry2D.is_point_in_polygon(Vector2.ZERO,shape.polygon))
	assert(data.bounds.has_point(Vector2(10,0)))
	data.toggle_pin(Vector2.ONE);assert(data.pins.size()==1);data.toggle_pin(Vector2.ONE);assert(data.pins.is_empty())
	host.free();print("HOUSE_MAP_PROJECTION PASS courtyard, markers, pins and 1000 decorative parts");quit()
