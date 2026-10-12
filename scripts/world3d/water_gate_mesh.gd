extends RefCounted
## A real segmental intrados, through opening and individual front voussoirs.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static func mesh(record:Dictionary,fallback:Material=null)->ArrayMesh:
	var w:float=record.size[0];var h:float=record.size[1];var d:float=record.size[2];var rise:float=minf(h-.35,w*.32)
	var stone:=SurfaceTool.new();stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim:=SurfaceTool.new();trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=32;var ring:=minf(.28,(h-rise)*.8)
	for i in count:
		var a:float=PI*(1.-float(i)/count);var b:float=PI*(1.-float(i+1)/count)
		var x0:=cos(a)*w*.5;var x1:=cos(b)*w*.5
		var y0:float=-h*.5+sin(a)*rise;var y1:float=-h*.5+sin(b)*rise
		for side in [-1,1]:
			var z:float=side*(d*.5-.03)
			quad(stone,[Vector3(x0,y0,z),Vector3(x1,y1,z),Vector3(x1,h*.5,z),Vector3(x0,h*.5,z)],Vector3(0,0,side))
			var gap:float=minf(.012,(x1-x0)*.1);z=side*d*.5
			quad(trim,[Vector3(x0+gap,y0,z),Vector3(x1-gap,y1,z),Vector3(x1-gap,y1+ring,z),Vector3(x0+gap,y0+ring,z)],Vector3(0,0,side))
		quad(stone,[Vector3(x0,y0,-d*.5+.03),Vector3(x1,y1,-d*.5+.03),Vector3(x1,y1,d*.5-.03),Vector3(x0,y0,d*.5-.03)],Vector3(y1-y0,-(x1-x0),0).normalized())
		quad(stone,[Vector3(x0,h*.5,-d*.5+.03),Vector3(x1,h*.5,-d*.5+.03),Vector3(x1,h*.5,d*.5-.03),Vector3(x0,h*.5,d*.5-.03)],Vector3.UP)
	for side in [-1,1]:quad(stone,[Vector3(side*w*.5,-h*.5,-d*.5+.03),Vector3(side*w*.5,h*.5,-d*.5+.03),Vector3(side*w*.5,h*.5,d*.5-.03),Vector3(side*w*.5,-h*.5,d*.5-.03)],Vector3(side,0,0))
	var result:=ArrayMesh.new()
	for pair:Array in [[stone,"stone"],[trim,"trim"]]:
		var st:SurfaceTool=pair[0];st.index();st.generate_tangents();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays())
		var material:Material=Paint.make_material(record.fortification_materials[pair[1]]) if record.has("fortification_materials") else fallback
		result.surface_set_material(result.get_surface_count()-1,material)
	return result
static func quad(st:SurfaceTool,points:Array,normal:Vector3)->void:
	if (points[2]-points[0]).cross(points[1]-points[0]).dot(normal)<0:points.reverse()
	for i in [0,1,2,0,2,3]:
		var p:Vector3=points[i];st.set_normal(normal);st.set_uv(Vector2(p.x,p.y) if absf(normal.z)>.5 else (Vector2(p.x,p.z) if absf(normal.y)>.5 else Vector2(p.z,p.y)));st.add_vertex(p)
