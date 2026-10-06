extends RefCounted
## Split only the planar deck texture boundary, preserving positions and coverage.
static func clip(poly:Array,limit:float,less:bool)->Array:
	var result:Array=[]
	if poly.is_empty():return result
	var previous:Dictionary=poly[-1];var inside_before:bool=previous.p.z<=limit if less else previous.p.z>=limit
	for current:Dictionary in poly:
		var inside:bool=current.p.z<=limit if less else current.p.z>=limit
		if inside!=inside_before:
			var t:float=(limit-previous.p.z)/(current.p.z-previous.p.z)
			result.append({"p":previous.p.lerp(current.p,t),"n":previous.n.lerp(current.n,t).normalized(),"uv":previous.uv.lerp(current.uv,t),"color":previous.color.lerp(current.color,t)})
		if inside:result.append(current)
		previous=current;inside_before=inside
	return result
static func emit_polygon(st:SurfaceTool,poly:Array,stone:bool,tile:Vector2)->void:
	for i in range(1,poly.size()-1):
		var tri:Array=[poly[0],poly[i],poly[i+1]]
		if (tri[1].p-tri[0].p).cross(tri[2].p-tri[0].p).length_squared()<1e-14:continue
		for vertex:Dictionary in tri:
			st.set_normal(vertex.n);st.set_color(vertex.color)
			st.set_uv(Vector2(vertex.p.x,vertex.p.z)/tile if stone else vertex.uv);st.add_vertex(vertex.p)
static func emit(streams:Array,tri:Array,role:int,width:float,tile:Vector2)->int:
	# The inner parapet face is 0.51 m from the deck edge. Put the material
	# transition under its solid base, hiding both the outer lip and mortar gaps.
	var limit:float=width*.5-.5
	if role!=0 or not tri.any(func(v):return absf(v.p.z)>limit+.00001):
		emit_polygon(streams[role],tri,false,tile);return 0
	emit_polygon(streams[0],clip(clip(tri,limit,true),-limit,false),false,tile)
	emit_polygon(streams[1],clip(tri,limit,false),true,tile)
	emit_polygon(streams[1],clip(tri,-limit,true),true,tile)
	return 1
