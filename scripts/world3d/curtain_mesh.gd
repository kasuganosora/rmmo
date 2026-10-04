extends RefCounted
## Blender-authored, continuous linen skin with a pocket over the curtain rod.
const DATA = preload("res://scripts/world3d/linen_curtain_data.gd").DATA

static func valid(r:Dictionary)->bool:
	var c:Variant=r.get("cloth")
	if not c is Dictionary or c.size()!=2:return false
	var side:Variant=c.get("side")
	return c.get("axis") in ["x","z"] and (side is int or side is float) and is_finite(float(side)) and (side==-1 or side==1) and r.get("collision")=="none"

static func mesh(r:Dictionary,base:Material)->ArrayMesh:
	var size:=Vector3(r.size[0],r.size[1],r.size[2]);var axis:String=r.cloth.axis
	var w:float=size.x if axis=="x" else size.z;var depth:float=size.z if axis=="x" else size.x
	var side:int=int(r.cloth.side)
	var material:StandardMaterial3D=base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=1;material.metallic=0
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(material);st.set_smooth_group(0)
	for triangle in DATA.triangles:
		var corners:Array=triangle.duplicate()
		if (side==-1)!=(axis=="z"):corners.reverse()
		for index in corners:
			var source:Array=DATA.vertices[index]
			var p:=Vector3(source[0]*w/.44*side,source[1]*size.y/1.8,source[2]*depth/.16)
			# The rod keeps its 45 mm cross-section when window height changes.
			if index<40:p.y=size.y/2+(source[1]-.9);p.z=source[2]
			if axis=="z":p=Vector3(p.z,p.y,p.x)
			var uv:Array=DATA.uv[index]
			st.set_uv(Vector2(uv[0]*w/.44,uv[1]*size.y/1.8));st.add_vertex(p)
	st.index();st.generate_normals();st.generate_tangents()
	var arrays:=st.commit_to_arrays();var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(0,material)
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,[arrays])
	return result
