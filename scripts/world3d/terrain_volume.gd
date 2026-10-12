extends RefCounted
## Bounded constructive solid terrain, persisted as a recipe; CPU-only meshing.
const S=preload("res://scripts/world3d/document_schema.gd")
const W=preload("res://scripts/world3d/waterway_data.gd")
const CORNERS=[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,1,0),Vector3(0,1,0),Vector3(0,0,1),Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1)]
const TETS=[[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6],[0,5,1,6]]
const EDGES=[[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]
static func operation_schema()->Dictionary:
	return W.obj({"mode":{"type":"string","enum":["add","subtract"]},"a":S.vector(-128,128),"b":S.vector(-128,128),"radius":S.number(.25,32)},["mode","a","b","radius"])
static func schema()->Dictionary:
	return W.obj({"version":S.number(1,1,true),"resolution":S.number(4,32,true),"seed":{"type":"string","enum":["box","ellipsoid"]},"operations":W.arr(operation_schema(),128)},["version","resolution","seed","operations"])
static func request_schema()->Dictionary:
	return W.obj({"id":W.text(128),"name":W.text(128),"center":S.vector(-10000,10000),"size":S.vector(2,64),"resolution":S.number(4,32,true),"seed":{"type":"string","enum":["box","ellipsoid"]},"material_id":W.text(512)},["id","center","size"])
static func stroke_schema()->Dictionary:
	return W.obj({"id":W.text(128),"mode":{"type":"string","enum":["add","subtract"]},"points":W.arr(S.vector(-10000,10000),64,1),"radius":S.number(.25,32)},["id","mode","points","radius"])
static func valid(record:Dictionary)->bool:
	if not record.has("terrain_volume"):return true
	if record.get("kind")!="box" or not S.validate(record.terrain_volume,schema()).is_empty():return false
	if not S.validate(record.get("size"),S.vector(2,64)).is_empty():return false
	for key in ["terrain_mesh","road_mesh","channel_mesh","building","building_shape","tile3d","fortification","fixture","rock_bank"]:
		if record.has(key):return false
	# Bounded work prevents an authored recipe from monopolising a load worker.
	return pow(record.terrain_volume.resolution+3,3)*(1+record.terrain_volume.operations.size())<=2000000
static func vector(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func field(p:Vector3,size:Vector3,data:Dictionary)->float:
	var half:=size*.45
	var q:=p.abs()-half
	var distance:float=(p/half).length()-1. if data.seed=="ellipsoid" else q.max(Vector3.ZERO).length()+minf(maxf(q.x,maxf(q.y,q.z)),0.)
	if data.seed=="ellipsoid":distance*=minf(half.x,minf(half.y,half.z))
	for operation:Dictionary in data.operations:
		var a:=vector(operation.a);var b:=vector(operation.b);var d:=b-a
		var nearest:=a+d*clampf((p-a).dot(d)/maxf(d.length_squared(),.000001),0,1)
		var sphere:float=p.distance_to(nearest)-operation.radius
		distance=minf(distance,sphere) if operation.mode=="add" else maxf(distance,-sphere)
	# Additions are clipped to the advertised extent; the padded lattice closes it.
	q=p.abs()-size*.5
	return maxf(distance,q.max(Vector3.ZERO).length()+minf(maxf(q.x,maxf(q.y,q.z)),0.))
static func arrays(record:Dictionary)->Array:
	var data:Dictionary=record.terrain_volume;var n:=int(data.resolution);var size:=vector(record.size);var step:=size/n
	var count:=n+3;var positions:=PackedVector3Array();var values:=PackedFloat32Array()
	for z in count:
		for y in count:
			for x in count:
				var p:Vector3=Vector3(x-1,y-1,z-1)*step-size*.5
				positions.append(p);values.append(field(p,size,data))
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile:Array=record.get("terrain_material",{}).get("tile_size",[2,2]);var uv_scale:=Vector2(tile[0],tile[1]);var triangles:=0
	for z in count-1:
		for y in count-1:
			for x in count-1:
				var cube:Array=[]
				for corner:Vector3 in CORNERS:cube.append((z+int(corner.z))*count*count+(y+int(corner.y))*count+x+int(corner.x))
				for tet:Array in TETS:
					var ids:Array=tet.map(func(i):return cube[i]);var inside:=0;var gradient:=Vector3.ZERO
					for id:int in ids:
						if values[id]<0:inside+=1
					if inside==0 or inside==4:continue
					var basis:=Basis(positions[ids[1]]-positions[ids[0]],positions[ids[2]]-positions[ids[0]],positions[ids[3]]-positions[ids[0]])
					gradient=basis.inverse().transposed()*Vector3(values[ids[1]]-values[ids[0]],values[ids[2]]-values[ids[0]],values[ids[3]]-values[ids[0]])
					var normal:=gradient.normalized();var polygon:Array[Vector3]=[]
					for edge:Array in EDGES:
						var a:int=ids[edge[0]];var b:int=ids[edge[1]]
						if (values[a]<0)==(values[b]<0):continue
						var p:=positions[a].lerp(positions[b],values[a]/(values[a]-values[b]))
						if not polygon.any(func(v):return v.distance_squared_to(p)<.0000000001):polygon.append(p)
					if polygon.size()<3:continue
					var center:=Vector3.ZERO
					for p:Vector3 in polygon:center+=p
					center/=polygon.size()
					var u:Vector3=(polygon[0]-center).normalized();var v:=normal.cross(u)
					polygon.sort_custom(func(a,b):return atan2((a-center).dot(v),(a-center).dot(u))>atan2((b-center).dot(v),(b-center).dot(u)))
					for j in range(1,polygon.size()-1):
						var vertices:Array=[polygon[0],polygon[j],polygon[j+1]]
						if (vertices[2]-vertices[0]).cross(vertices[1]-vertices[0]).length_squared()<.0000000001:continue
						for p:Vector3 in vertices:
							var uv:=Vector2(p.x,p.z) if absf(normal.y)>.5 else (Vector2(p.x,p.y) if absf(normal.z)>.5 else Vector2(p.z,p.y))
							st.set_normal(normal);st.set_uv(uv/uv_scale);st.add_vertex(p)
						triangles+=1
	if triangles==0:return []
	st.index();st.generate_tangents();return [st.commit_to_arrays()]
static func mesh(record:Dictionary,fallback:Material)->ArrayMesh:
	var result:=ArrayMesh.new()
	var material:Material=preload("res://scripts/world3d/surface_materials.gd").make_material(record.terrain_material) if record.has("terrain_material") else fallback
	for built:Array in arrays(record):
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,built);result.surface_set_material(0,material);result.surface_set_name(0,"volume_terrain")
	return result

