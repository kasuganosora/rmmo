extends RefCounted
## Private packed channels for road pavement, underside and edge surfaces.
## Exact triangle order/UV equations and native tangent generation are retained.
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var uvs:=PackedVector2Array()
var at:=0
var surface:=0
var uv:=Vector3.ZERO
func triangle(a:Vector3,b:Vector3,c:Vector3)->void:
	var normal:Vector3=(c-a).cross(b-a).normalized()
	if normal.length()<.5:return
	vertices[at]=a;vertices[at+1]=b;vertices[at+2]=c
	normals[at]=normal;normals[at+1]=normal;normals[at+2]=normal
	if surface<2:
		uvs[at]=Vector2(a.x+uv.x,a.z+uv.z);uvs[at+1]=Vector2(b.x+uv.x,b.z+uv.z);uvs[at+2]=Vector2(c.x+uv.x,c.z+uv.z)
	else:
		var across:=Vector3.UP.cross(normal)
		uvs[at]=Vector2((a+uv).dot(across),a.y+uv.y);uvs[at+1]=Vector2((b+uv).dot(across),b.y+uv.y);uvs[at+2]=Vector2((c+uv).dot(across),c.y+uv.y)
	at+=3
static func build(polygons:Array,drop:Vector3,origin:Vector3)->Array:
	var result:Array=[];var top:=0;var edge:=0
	for p:Array in polygons:top+=3*(p.size()-2);edge+=6*p.size()
	for side in 3:
		var work:=new();work.surface=side;work.uv=origin
		var count:int=top if side<2 else edge
		work.vertices.resize(count);work.normals.resize(count);work.uvs.resize(count)
		for p:Array in polygons:
			if side<2:
				for i in range(1,p.size()-1):
					if side==0:work.triangle(p[0],p[i],p[i+1])
					else:work.triangle(p[0]+drop,p[i+1]+drop,p[i]+drop)
			else:
				for i in p.size():
					var a:Vector3=p[i];var b:Vector3=p[(i+1)%p.size()]
					work.triangle(a,a+drop,b+drop);work.triangle(a,b+drop,b)
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		if work.at==0:result.append(arrays);continue
		work.vertices.resize(work.at);work.normals.resize(work.at);work.uvs.resize(work.at)
		arrays[Mesh.ARRAY_VERTEX]=work.vertices;arrays[Mesh.ARRAY_NORMAL]=work.normals;arrays[Mesh.ARRAY_TEX_UV]=work.uvs
		var st:=SurfaceTool.new();st.create_from_arrays(arrays);st.generate_tangents();result.append(st.commit_to_arrays())
	return result
