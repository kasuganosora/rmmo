extends RefCounted
## Private CPU channels; one native import replaces three API calls per vertex.
## Tangents still use Godot's exact SurfaceTool/MikkTSpace implementation.
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var uvs:=PackedVector2Array()
var at:=0
func triangle(a:Vector3,b:Vector3,c:Vector3,ua:Vector2,ub:Vector2,uc:Vector2)->void:
	var normal:Vector3=(c-a).cross(b-a).normalized()
	if normal.length()<.5:return
	vertices[at]=a;vertices[at+1]=b;vertices[at+2]=c
	normals[at]=normal;normals[at+1]=normal;normals[at+2]=normal
	uvs[at]=ua/1.76;uvs[at+1]=ub/1.76;uvs[at+2]=uc/1.76;at+=3
static func build(record:Dictionary)->Array:
	var parts:Array=record.road_mesh.get("kerbs",[]);var count:=0
	for part:Dictionary in parts:count+=36+12*int(part.cap_a)+12*int(part.cap_b)
	var work:=new();work.vertices.resize(count);work.normals.resize(count);work.uvs.resize(count)
	for part:Dictionary in parts:
		var a:Array=[];var b:Array=[]
		for p:Array in part.a:a.append(Vector3(p[0],p[1],p[2]))
		for p:Array in part.b:b.append(Vector3(p[0],p[1],p[2]))
		var v:=0.0
		for i in 6:
			var j:=(i+1)%6;var next:float=v+a[i].distance_to(a[j])
			work.triangle(a[i],b[i],b[j],Vector2(part.u,v),Vector2(part.u+part.length,v),Vector2(part.u+part.length,next))
			work.triangle(a[i],b[j],a[j],Vector2(part.u,v),Vector2(part.u+part.length,next),Vector2(part.u,next))
			v=next
		for cap in 2:
			if not part["cap_a" if cap==0 else "cap_b"]:continue
			var points:Array=a if cap==0 else b;var p:Vector3=points[0]
			for i in range(1,5):
				var q:Vector3=points[i] if cap==0 else points[i+1]
				var r:Vector3=points[i+1] if cap==0 else points[i]
				work.triangle(p,q,r,Vector2(p.distance_to(p),p.y),Vector2(q.distance_to(p),q.y),Vector2(r.distance_to(p),r.y))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	if work.at==0:return arrays
	work.vertices.resize(work.at);work.normals.resize(work.at);work.uvs.resize(work.at)
	arrays[Mesh.ARRAY_VERTEX]=work.vertices;arrays[Mesh.ARRAY_NORMAL]=work.normals;arrays[Mesh.ARRAY_TEX_UV]=work.uvs
	var st:=SurfaceTool.new();st.create_from_arrays(arrays);st.generate_tangents()
	return st.commit_to_arrays()
