extends RefCounted
## A wall shell with actual apertures and no internal/coplanar cell faces.
static func grid(us: Array,vs: Array,openings: Array,start: float,end: float,height: float)->Dictionary:
	var u:Array=[];var v:Array=[];var cells:Array=[]
	for x in us:
		var value:=clampf(float(x),start,end)
		if u.is_empty() or value-u.back()>.0001:u.append(value)
	for y in vs:
		var value:=clampf(float(y),0,height)
		if v.is_empty() or value-v.back()>.0001:v.append(value)
	for j in v.size()-1:
		for i in u.size()-1:
			var x:float=(u[i]+u[i+1])/2;var y:float=(v[j]+v[j+1])/2
			cells.append(not openings.any(func(o):return absf(x-o.u)<o.width/2 and y>o.bottom and y<o.bottom+o.height))
	return {"u":u.map(func(x):return (x-start)/(end-start)),"v":v.map(func(y):return y/height),"cells":cells}

static func valid(r: Dictionary)->bool:
	var g:Variant=r.get("wall_grid")
	if not g is Dictionary or g.get("axis") not in ["x","z"]:return false
	for key in ["u","v"]:
		var a:Variant=g.get(key)
		if not a is Array or a.size()<2 or a.size()>128:return false
		for i in a.size():
			if not (a[i] is float or a[i] is int) or not is_finite(a[i]) or a[i]<0 or a[i]>1:return false
			if i>0 and a[i]<=a[i-1]:return false
		if a[0]!=0 or a.back()!=1:return false
	var c:Variant=g.get("cells")
	return c is Array and c.size()==(g.u.size()-1)*(g.v.size()-1) and c.all(func(value):return value is bool)

static func mesh(r:Dictionary,material:Material)->ArrayMesh:
	var g:Dictionary=r.wall_grid;var size:=Vector3(r.size[0],r.size[1],r.size[2])
	var w:float=size.x if g.axis=="x" else size.z
	var thickness:float=size.z if g.axis=="x" else size.x
	var nx:int=g.u.size()-1;var ny:int=g.v.size()-1
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(material)
	for j in ny:
		for i in nx:
			if not g.cells[j*nx+i]:continue
			var a:float=(g.u[i]-.5)*w;var b:float=(g.u[i+1]-.5)*w
			var c:float=(g.v[j]-.5)*size.y;var d:float=(g.v[j+1]-.5)*size.y
			var t:=thickness/2
			quad(st,[Vector3(a,c,-t),Vector3(b,c,-t),Vector3(b,d,-t),Vector3(a,d,-t)],Vector3.FORWARD,g.axis)
			quad(st,[Vector3(b,c,t),Vector3(a,c,t),Vector3(a,d,t),Vector3(b,d,t)],Vector3.BACK,g.axis)
			if i==0 or not g.cells[j*nx+i-1]:quad(st,[Vector3(a,c,t),Vector3(a,c,-t),Vector3(a,d,-t),Vector3(a,d,t)],Vector3.LEFT,g.axis)
			if i==nx-1 or not g.cells[j*nx+i+1]:quad(st,[Vector3(b,c,-t),Vector3(b,c,t),Vector3(b,d,t),Vector3(b,d,-t)],Vector3.RIGHT,g.axis)
			if j==0 or not g.cells[(j-1)*nx+i]:quad(st,[Vector3(a,c,t),Vector3(b,c,t),Vector3(b,c,-t),Vector3(a,c,-t)],Vector3.DOWN,g.axis)
			if j==ny-1 or not g.cells[(j+1)*nx+i]:quad(st,[Vector3(a,d,-t),Vector3(b,d,-t),Vector3(b,d,t),Vector3(a,d,t)],Vector3.UP,g.axis)
	st.generate_tangents();var arrays:=st.commit_to_arrays();var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(0,material)
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,[arrays])
	return result

static func quad(st:SurfaceTool,points:Array,normal:Vector3,axis:String)->void:
	# Swapping x/z reflects winding; keep outward normals and Godot clockwise faces.
	var indices:Array=[0,1,2,0,2,3] if axis=="x" else [0,2,1,0,3,2]
	for index in indices:
		var point:Vector3=points[index];var n:=normal
		if axis=="z":point=Vector3(point.z,point.y,point.x);n=Vector3(n.z,n.y,n.x)
		st.set_normal(n);st.set_uv(Vector2(point.x if absf(n.x)<.9 else point.z,point.z if absf(n.y)>.9 else point.y));st.add_vertex(point)
