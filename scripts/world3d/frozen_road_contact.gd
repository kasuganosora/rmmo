extends RefCounted
## Saved static native prefabs retain their real openings after render batching.
## Unknown payloads and articulated fixtures keep conservative occupancy.
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Contact=preload("res://scripts/world3d/asset_road_contact.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
static func geometry(record:Dictionary,cache:Dictionary)->Dictionary:
 if not record.has("house_prefab") or record.has("fixture") or record.has("wind_response") or record.has("bridge_mesh"):return {"known":false}
 # Include the actual payload, not only its claimed digest, and the complete pose.
 var key=City.token([record.house_prefab,record.get("kind"),record.get("position"),record.get("rotation"),record.get("size")])
 if cache.has(key):return cache[key]
 var data=Frozen.decode(record.house_prefab)
 if data.is_empty() or data.entries.size()!=1 or data.entries[0][0]!=[0]:return {"known":false}
 var basis=Basis.from_euler(City.vec(record.rotation)*PI/180.)
 # Native box-prefab size is its bounds; only asset-prefabs apply local scaling.
 if record.get("kind")=="asset":basis=basis*Basis.from_scale(City.vec(record.size))
 if absf(basis.determinant())<.000001:return {"known":false}
 var pose=Transform3D(basis,City.vec(record.position))
 var result={"known":true,"faces":[],"solids":[]}
 var seen={}
 for mesh_index in data.entries[0][1]:
  if seen.has(mesh_index):continue
  seen[mesh_index]=true
  var mesh:Dictionary=data.meshes[mesh_index]
  var surfaces:Array=mesh.surfaces
  if mesh.box_size!=Vector3.ZERO:
   var box=BoxMesh.new();box.size=mesh.box_size;surfaces=[Cpu.primitive_arrays(box,0)]
  var solid:Array=[]
  for surface:Array in surfaces:
   var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
   var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX] if surface[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
   if indices.is_empty():
    for i in vertices.size():indices.append(i)
   if indices.size()%3!=0:return {"known":false}
   for at in range(0,indices.size(),3):
    var a:Vector3=pose*vertices[indices[at]];var b:Vector3=pose*vertices[indices[at+1]];var c:Vector3=pose*vertices[indices[at+2]]
    if not a.is_finite() or not b.is_finite() or not c.is_finite():return {"known":false}
    if (b-a).cross(c-a).length_squared()<1e-16:continue
    var face={"points":[a,b,c],"bounds":AABB(a,Vector3.ZERO).expand(b).expand(c).grow(.0001)}
    result.faces.append(face);solid.append(face)
  if not solid.is_empty():result.solids.append(solid)
 if result.faces.is_empty():result.known=false
 cache[key]=result
 return result
static func intersects(road:Dictionary,record:Dictionary,occupancy:Array,shape:Dictionary,cache:Dictionary)->bool:
 return Contact.intersects_geometry(road,geometry(record,cache),occupancy,shape)
