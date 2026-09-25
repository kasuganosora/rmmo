extends RefCounted
## Sculpted ring profiles and tapered locks, shared by the modular character meshes.
static func profile(rings:Array,segments:int=32)->ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size()-1):
		for col in range(segments):
			for index in [Vector2i(col,row),Vector2i(col+1,row+1),Vector2i(col+1,row),Vector2i(col,row),Vector2i(col,row+1),Vector2i(col+1,row+1)]:
				var ring:Vector4=rings[index.y]
				var angle:=float(index.x)/segments*TAU
				st.add_vertex(Vector3(sin(angle)*ring.y,ring.x,cos(angle)*ring.z+ring.w))
	st.generate_normals();return st.commit()

static func lock(points:Array,width:float,depth:float)->ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices:Array=[]
	for i in range(points.size()):
		var t:=float(i)/(points.size()-1)
		var taper:=pow(1.0-t,.65)
		var tangent:Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
		var side:=Vector3.FORWARD.cross(tangent).normalized()
		var normal:=tangent.cross(side).normalized()
		for j in range(10):
			var a:=float(j)/10*TAU
			vertices.append(points[i]+side*cos(a)*width*taper+normal*sin(a)*depth*taper)
	for i in range(points.size()-1):
		for j in range(10):
			var a:=i*10+j;var b:=i*10+(j+1)%10;var c:=(i+1)*10+j;var d:=(i+1)*10+(j+1)%10
			for idx in [a,b,c,b,d,c]:st.add_vertex(vertices[idx])
	st.generate_normals();return st.commit()

static func almond(width:float,height:float)->ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(32):
		var a:=float(i)/32*TAU;var b:=float(i+1)/32*TAU
		st.add_vertex(Vector3.ZERO)
		for angle in [b,a]:
			st.add_vertex(Vector3(cos(angle)*width,sin(angle)*height*(.8+.2*absf(sin(angle))),0))
	st.generate_normals();return st.commit()
