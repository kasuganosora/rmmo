extends RefCounted
## Refine an otherwise rejected brush only for verified frozen native stone
## bridges. Excavating an arch is distinct from excavating its actual footings.
const City=preload("res://scripts/world3d/city_layout.gd")
const D=preload("res://scripts/world3d/bridge_data.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Meshes=preload("res://scripts/world3d/bridge_mesh.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Clip=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Contact=preload("res://scripts/world_editor/terrain_prop_contact.gd")
const ROUNDING:=.00001
const CONTACT:=.005

static func face_key(points:Array)->String:
	var keys:Array=[]
	for p:Vector3 in points:keys.append(str(Vector3i((p*100000.).round())))
	keys.sort();return str(keys)

static func faces(surfaces:Array)->Array:
	var result:Array=[]
	for surface:Array in surfaces:
		var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX] if surface[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():indices.append(i)
		for i in range(0,indices.size(),3):result.append([vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]])
	return result

static func projected(points:Array,pose:Transform3D)->Dictionary:
	var world:Array=points.map(func(p):return pose*p)
	var polygon:Array=world.map(func(p):return Vector2(p.x,p.z))
	if Poly.area(polygon)<1e-10:return {}
	if Geometry2D.is_polygon_clockwise(PackedVector2Array(polygon)):polygon.reverse()
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for p:Vector2 in polygon:bounds=bounds.expand(p)
	return {"polygon":polygon,"bounds":bounds,"point":world[0],"normal":(world[1]-world[0]).cross(world[2]-world[0])}

static func geometry(bridge:Dictionary,cache:Dictionary)->Dictionary:
	if not bridge.has("bridge_mesh") or not bridge.has("house_prefab") or not D.valid(bridge):return {}
	if absf(bridge.rotation[0])+absf(bridge.rotation[2])>.0001 or bridge.bridge_mesh.recipe.style not in ["segmental","pointed","rustic"]:return {}
	var path:String=bridge.get("asset_path","")
	var candidate:=preload("res://scripts/world_editor/asset_library.gd").native_validation_candidate(path)
	if candidate.is_empty():return {}
	var key:=City.token([bridge.house_prefab.sha256,bridge.bridge_mesh,bridge.position,bridge.rotation,bridge.size,path,candidate.native_product_kind,candidate.source_sha,candidate.payload_sha,candidate.generator])
	if cache.has(key):return cache[key]
	cache[key]={} # Fail closed, including a missing/changed module or unknown pack.
	var decoded:=Frozen.decode(bridge.house_prefab)
	if decoded.is_empty() or decoded.entries.size()!=1 or decoded.entries[0][0]!=[0]:return {}
	var collision:Dictionary=decoded.meshes[decoded.entries[0][1][1]]
	if collision.box_size!=Vector3.ZERO:return {}
	var actual:=faces(collision.surfaces);var actual_keys:Dictionary={}
	for face:Array in actual:actual_keys[face_key(face)]=true
	# The private geometry owns this published native version; saving/editing the
	# original GLB has no effect until an explicit reimport publishes a new one.
	var owner:Node3D=preload("res://scripts/world_editor/asset_library.gd").instantiate_geometry(path,candidate)
	if owner==null:return {}
	var pieces:Dictionary={}
	for node:MeshInstance3D in Paint.meshes(owner):pieces[str(node.name)]={"mesh":node.mesh,"transform":node.transform}
	if not pieces.has("abutment") or not pieces.has("pier"):owner.free();return {}
	var builder:=Meshes.new();builder.data=bridge.bridge_mesh
	for slot in 3:
		var stream:=SurfaceTool.new();stream.begin(Mesh.PRIMITIVE_TRIANGLES);builder.streams.append(stream);builder.tiles.append(Vector2.ONE)
	var d:Dictionary=bridge.bridge_mesh;var opening:float=(d.length-2-(d.arches-1)*d.recipe.pier_width)/d.arches
	var station_faces:Array=[];var foundation_keys:Dictionary={}
	# Node3D applies its authored scale in local space, before rotation.
	var pose:=Transform3D(Basis.from_euler(City.vec(bridge.rotation)*PI/180)*Basis.from_scale(City.vec(bridge.size)),City.vec(bridge.position))
	var bases:Array=[]
	for i in int(d.arches)+1:
		# Same station arrangement and actual deformation as BridgeMesh.build;
		# the resulting triangles must exist in the saved collision source.
		var x:float=-d.length*.5+.5 if i==0 else (d.length*.5-.5 if i==int(d.arches) else -d.length*.5+1+i*opening+(i-1)*d.recipe.pier_width+d.recipe.pier_width*.5)
		for stream:SurfaceTool in builder.streams:stream.clear();stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.append_piece(pieces.abutment if i==0 or i==int(d.arches) else pieces.pier,Vector3(x,0,0),Vector3(1 if i==0 or i==int(d.arches) else d.recipe.pier_width/1.3,(d.depth-.25)/4.75,d.width/7),true)
		var arrays:Array=[]
		for stream:SurfaceTool in builder.streams:
			var a:=stream.commit_to_arrays()
			if a[Mesh.ARRAY_VERTEX]!=null and not a[Mesh.ARRAY_VERTEX].is_empty():arrays.append(a)
		station_faces=faces(arrays);var base_count:=0
		for face:Array in station_faces:
			var identity:=face_key(face)
			if not actual_keys.has(identity):owner.free();return {}
			foundation_keys[identity]=true
			if face.all(func(p):return absf(p.y+float(d.depth))<ROUNDING):
				var base:=projected(face,pose)
				if not base.is_empty():bases.append(base);base_count+=1
		# Unequal-depth/unsupported modules cannot silently lose a footing.
		if base_count==0:owner.free();return {}
	owner.free()
	if preload("res://scripts/world_editor/asset_library.gd").native_validation_candidate(path)!=candidate:return {}
	var body:Array=[]
	for face:Array in actual:
		# An unrecognised bottom-reaching structure is not an arch intrados.
		if not foundation_keys.has(face_key(face)) and face.any(func(p):return p.y<=-float(d.depth)+ROUNDING):return {}
		# Foundation bevels/cutwaters also remain protected from backfilling;
		# their projections need not be identical to the flat sole footprint.
		var part:=projected(face,pose)
		if not part.is_empty():body.append(part)
	var result:={"bases":bases,"body":body,"source_sha256":candidate.source_sha,"native_payload_sha":candidate.payload_sha}
	cache[key]=result;return result

static func preserves(record:Dictionary,result:Dictionary,bridge:Dictionary,cache:Dictionary)->bool:
	if absf(record.rotation[0])+absf(record.rotation[2])>.0001:return false
	var Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
	if Furrows.maximum_height(record)>0 or Furrows.maximum_height(result.record)>0:return false
	var mesh:=geometry(bridge,cache)
	if mesh.is_empty():return false
	var world:=Terrain.transform(record);var t:Dictionary=record.terrain_mesh
	for at in result.cells:
		var x:=int(at)%int(t.columns);var z:=int(at)/int(t.columns)
		if t.holes[at] and result.record.terrain_mesh.holes[at]:continue
		var before:Array=Terrain.cell(record,x,z).map(func(p):return world*p)
		var after:Array=Terrain.cell(result.record,x,z).map(func(p):return world*p)
		for indices in [[0,1,2],[0,2,3]]:
			var p:Vector3=before[indices[0]];var q:Vector3=after[indices[0]]
			var n:Vector3=(before[indices[1]]-p).cross(before[indices[2]]-p);var m:Vector3=(after[indices[1]]-q).cross(after[indices[2]]-q)
			if absf(n.y)<1e-8 or absf(m.y)<1e-8:return false
			var triangle:Array=indices.map(func(i):return Vector2(before[i].x,before[i].z))
			var bounds:=Rect2(triangle[0],Vector2.ZERO)
			for point:Vector2 in triangle:bounds=bounds.expand(point)
			var rising:bool=t.holes[at] and not result.record.terrain_mesh.holes[at]
			for index:int in indices:rising=rising or after[index].y>before[index].y+ROUNDING
			for base:Dictionary in mesh.bases:
				if not bounds.intersects(base.bounds,true):continue
				var overlap:=Clip.intersection(base.polygon,triangle)
				if overlap.size()<3 or Poly.area(overlap)<1e-10:continue
				if t.holes[at] or result.record.terrain_mesh.holes[at]:return false
				# Both ground planes and the base plane are affine. Their extrema
				# over this exact polygon occur at these intersection vertices.
				for point:Vector2 in overlap:
					var bottom:=Contact.height(base.point,base.normal,point)
					if Contact.height(p,n,point)<bottom-CONTACT-ROUNDING or Contact.height(q,m,point)<bottom-CONTACT-ROUNDING:return false
			if not rising:continue
			# This refinement grants excavation only. Raising within a real
			# structure/arch opening remains protected, even without an
			# existing water record (a river generation stages its water later).
			for part:Dictionary in mesh.body:
				if not bounds.intersects(part.bounds,true):continue
				var overlap:=Clip.intersection(part.polygon,triangle)
				if overlap.size()<3 or Poly.area(overlap)<1e-10:continue
				if t.holes[at]:return false
				for point:Vector2 in overlap:
					if Contact.height(q,m,point)>Contact.height(p,n,point)+ROUNDING:return false
	return true
