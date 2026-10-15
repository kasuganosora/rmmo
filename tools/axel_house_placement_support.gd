extends RefCounted
## Authoring-only floor sampling. Native prefab collision remains authoritative.
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")

static func sample(doc,records:Array,origin:Vector3,basis:Basis,parameters:Dictionary)->Dictionary:
	var highest:=-INF;var lowest:=INF;var count:=0
	for record:Dictionary in records:
		var building:Dictionary=record.get("building",{})
		if building.get("floor",-1)!=0 or building.get("role","")!="floor":continue
		var shape:Dictionary=Footprint.record_shape(record)
		var bounds:AABB=shape.bounds
		count+=1
		for ix in 9:
			for iz in 9:
				var local:=Vector3(lerpf(bounds.position.x,bounds.end.x,ix/8.),0,lerpf(bounds.position.z,bounds.end.z,iz/8.))
				if not Geometry2D.is_point_in_polygon(Vector2(local.x,local.z),shape.polygon):continue
				var y:float=Props.ground(doc,origin+basis*local)
				if not is_finite(y):return {"ok":false,"reason":"ground-floor support sample has no terrain"}
				highest=maxf(highest,y);lowest=minf(lowest,y)
		# Include every real footprint vertex; polygon edge conventions must not
		# accidentally omit the corners of a foundation on sloping ground.
		for point:Vector2 in shape.polygon:
			var y:float=Props.ground(doc,origin+basis*Vector3(point.x,0,point.y))
			if not is_finite(y):return {"ok":false,"reason":"ground-floor footprint vertex has no terrain"}
			highest=maxf(highest,y);lowest=minf(lowest,y)
	if count==0 or not is_finite(highest) or not is_finite(lowest):return {"ok":false,"reason":"missing valid ground-floor support footprint"}
	var raised:float=float(parameters.get("base_height",0)) if parameters.get("layout") in ["townhouse","hall"] else 0.
	var position:=origin
	position.y=maxf(position.y,highest-raised+.025)
	return {"ok":true,"position":position,"highest":highest,"lowest":lowest,"support_components":count}
