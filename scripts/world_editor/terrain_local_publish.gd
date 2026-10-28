extends RefCounted
## Editor-only derived render buffers and bounded, exact picking/walk shapes.
## CPU geometry is authoritative for painting, batching and export consumers.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Incremental=preload("res://scripts/world_editor/terrain_mesh_incremental.gd")
const BLOCK=16
const META="terrain_local_publication"
static var enabled:=true # Diagnostic A/B, shared by UI and HTTP operations.
static var last_work:Dictionary={}
static func eligible(r:Dictionary)->bool:
	return enabled and r.has("terrain_mesh") and not r.has("surface_paint") and not r.has("terrain_grade") and preload("res://scripts/world3d/terrain_furrows.gd").arrays(r).is_empty()
static func signature(r:Dictionary)->Dictionary:
	var result:=r.duplicate(true);result.terrain_mesh.erase("heights")
	return result
static func faces(r:Dictionary,key:Vector2i)->PackedVector3Array:
	var t:Dictionary=r.terrain_mesh;var result:=PackedVector3Array()
	for z in range(key.y*BLOCK,mini((key.y+1)*BLOCK,int(t.rows))):
		for x in range(key.x*BLOCK,mini((key.x+1)*BLOCK,int(t.columns))):
			if not T.solid(t,x,z):continue
			var p:=T.cell(r,x,z);var bottom:Array=[]
			for v:Vector3 in p:bottom.append(Vector3(v.x,t.floor*r.size[1],v.z))
			for i in [0,1,2,0,2,3]:result.append(p[i])
			for i in [0,2,1,0,3,2]:result.append(bottom[i])
			var neighbors:=[Vector2i(x,z-1),Vector2i(x+1,z),Vector2i(x,z+1),Vector2i(x-1,z)]
			for i in 4:
				if T.solid(t,neighbors[i].x,neighbors[i].y):continue
				var j:=(i+1)%4
				for v:Vector3 in [p[i],bottom[i],bottom[j],p[i],bottom[j],p[j]]:result.append(v)
	return result
static func can_initialize(node:MeshInstance3D,r:Dictionary)->bool:
	if not eligible(r) or node.mesh==null:return false
	return Cpu.capture(node.mesh).surfaces.size()==2
static func initialize(node:MeshInstance3D,r:Dictionary,body:StaticBody3D,context:Dictionary={})->bool:
	if not can_initialize(node,r):return false
	var cpu:Mesh=Cpu.capture(node.mesh)
	var blocks:Dictionary={}
	for z in ceili(float(r.terrain_mesh.rows)/BLOCK):
		for x in ceili(float(r.terrain_mesh.columns)/BLOCK):
			var key:=Vector2i(x,z);var shape:=CollisionShape3D.new();var geometry:=ConcavePolygonShape3D.new()
			var soup:=faces(r,key)
			if soup.is_empty():continue
			geometry.set_faces(soup);shape.shape=geometry;body.add_child(shape);blocks[key]=shape
	node.set_meta(META,{"record":r.duplicate(true),"arrays":cpu.surfaces,"vertex_map":Incremental.mapping(r,cpu.surfaces),"blocks":blocks,"body":body,"normals":context.get("normals",{}).duplicate(true)})
	return true
static func encode16(value:float)->int:
	# Match RenderingServer's float32 multiplication before uint16 truncation.
	return clampi(int(PackedFloat32Array([value*65535.])[0]),0,65535)
static func packed_frames(arrays:Array,begin:int,end:int)->PackedByteArray:
	var result:=PackedByteArray();result.resize((end-begin)*8)
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	for i in range(begin,end):
		var n:=normals[i].octahedron_encode();var t:=Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2]).octahedron_encode()
		t.y=maxf(t.y,1./32767.);t.y=t.y*.5+.5
		if tangents[i*4+3]<0:t.y=1.-t.y
		var tx:=encode16(t.x);var ty:=encode16(t.y)
		if tx==0 and ty==65535:tx=65535
		var offset:=(i-begin)*8
		result.encode_u16(offset,encode16(n.x));result.encode_u16(offset+2,encode16(n.y))
		result.encode_u16(offset+4,tx);result.encode_u16(offset+6,ty)
	return result
static func ranges(a:Variant,b:Variant,multiplier:int=1)->Array[Vector2i]:
	var result:Array[Vector2i]=[];var begin:=-1
	for i in a.size()/multiplier:
		var different:=false
		for j in multiplier:
			if a[i*multiplier+j]!=b[i*multiplier+j]:different=true;break
		if different and begin<0:begin=i
		if not different and begin>=0:result.append(Vector2i(begin,i));begin=-1
	if begin>=0:result.append(Vector2i(begin,a.size()/multiplier))
	return result
static func prepare(node:Node,r:Dictionary,context:Dictionary)->Dictionary:
	if not node is MeshInstance3D or not node.has_meta(META) or not node.mesh is ArrayMesh or not eligible(r):return {}
	var state:Dictionary=node.get_meta(META)
	if signature(state.record)!=signature(r):return {}
	var old:Array=state.arrays
	var geometry_unchanged:bool=state.record==r and state.normals==context.get("normals",{})
	var patch:Dictionary={} if geometry_unchanged else Incremental.patch(state,r,context)
	var arrays:Array=old if geometry_unchanged else (patch.arrays if not patch.is_empty() else T.arrays(r,context))
	if arrays.size()!=2 or old.size()!=2 or node.mesh.get_surface_count()!=2:return {}
	var updates:Array=[];var bytes:=0
	for slot in (0 if geometry_unchanged else 2):
		var a:Array=old[slot];var b:Array=arrays[slot];var count:int=a[Mesh.ARRAY_VERTEX].size()
		if count!=b[Mesh.ARRAY_VERTEX].size() or a[Mesh.ARRAY_INDEX]!=b[Mesh.ARRAY_INDEX]:return {}
		for channel in Mesh.ARRAY_MAX:
			if channel not in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV] and a[channel]!=b[channel]:return {}
		var format:int=node.mesh.surface_get_format(slot)
		if format&Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES or RenderingServer.mesh_surface_get_format_vertex_stride(format,count)!=12 or RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)!=8 or RenderingServer.mesh_surface_get_format_attribute_stride(format,count)!=8:return {}
		for span:Vector2i in ranges(a[Mesh.ARRAY_VERTEX],b[Mesh.ARRAY_VERTEX]):
			var data:PackedByteArray=b[Mesh.ARRAY_VERTEX].slice(span.x,span.y).to_byte_array();bytes+=data.size()
			updates.append({"slot":slot,"offset":span.x*12,"data":data,"attribute":false})
		var changed:Dictionary={}
		for channel in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
			for span:Vector2i in ranges(a[channel],b[channel],4 if channel==Mesh.ARRAY_TANGENT else 1):
				for i in range(span.x,span.y):changed[i]=true
		var indices:Array=changed.keys();indices.sort();var spans:Array[Vector2i]=[]
		for i:int in indices:
			if spans.is_empty() or spans[-1].y!=i:spans.append(Vector2i(i,i+1))
			else:spans[-1].y=i+1
		var normal_offset:=RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_NORMAL)
		for span:Vector2i in spans:
			var data:=packed_frames(b,span.x,span.y);bytes+=data.size()
			updates.append({"slot":slot,"offset":normal_offset+span.x*8,"data":data,"attribute":false})
		for span:Vector2i in ranges(a[Mesh.ARRAY_TEX_UV],b[Mesh.ARRAY_TEX_UV]):
			var data:PackedByteArray=b[Mesh.ARRAY_TEX_UV].slice(span.x,span.y).to_byte_array();bytes+=data.size()
			updates.append({"slot":slot,"offset":span.x*8,"data":data,"attribute":true})
	var blocks:Dictionary={};var t:Dictionary=r.terrain_mesh;var stride:=int(t.columns)+1
	for i in t.heights.size():
		if t.heights[i]==state.record.terrain_mesh.heights[i]:continue
		var x:int=i%stride;var z:int=i/stride
		for dz in [z-1,z]:
			for dx in [x-1,x]:
				if T.solid(t,dx,dz):blocks[Vector2i(dx/BLOCK,dz/BLOCK)]=true
	var shapes:Dictionary={}
	for key:Vector2i in blocks:
		if not state.blocks.has(key) or not is_instance_valid(state.blocks[key]):return {}
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces(r,key));shapes[key]=shape
	return {"arrays":arrays,"updates":updates,"shapes":shapes,"record":r,"bytes":bytes,"cpu_patch":Incremental.last_work.duplicate() if not geometry_unchanged else {"unchanged":true}}
static func publish(node:MeshInstance3D,packet:Dictionary,context:Dictionary)->void:
	var state:Dictionary=node.get_meta(META);var r:Dictionary=packet.record;var mesh:ArrayMesh=node.mesh
	var copied:bool=not packet.updates.is_empty() and state.get("owned_mesh",0)!=mesh.get_instance_id()
	if copied:
		# First edit acquires private storage. Loaded/retired source resources may
		# still be referenced by caches; never mutate another owner's GPU mesh.
		var private_mesh:=ArrayMesh.new()
		for slot in packet.arrays.size():
			private_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,packet.arrays[slot],[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
			private_mesh.surface_set_material(slot,mesh.surface_get_material(slot))
			private_mesh.surface_set_name(slot,["terrain","bedrock_and_cut_edges"][slot])
		node.mesh=private_mesh;mesh=private_mesh;state.owned_mesh=mesh.get_instance_id()
	# No await: render data, authoritative CPU data, material halo and every
	# collision shape become one editor revision before the operation returns.
	for update:Dictionary in ([] if copied else packet.updates):
		if update.attribute:mesh.surface_update_attribute_region(update.slot,update.offset,update.data)
		else:mesh.surface_update_vertex_region(update.slot,update.offset,update.data)
	for key:Vector2i in packet.shapes:state.blocks[key].shape=packet.shapes[key]
	if not packet.shapes.is_empty():
		var host:Node=state.body.get_parent()
		if host!=null:
			var pending:Dictionary=host.get_meta("terrain_pending_rays",{})
			for id:int in pending.keys():
				if not is_instance_valid(pending[id].node.get_ref()) or Engine.get_physics_frames()>int(pending[id].frame)+1:pending.erase(id)
			pending[node.get_instance_id()]={"node":weakref(node),"frame":Engine.get_physics_frames()}
			host.set_meta("terrain_pending_rays",pending)
	var bounds:=T.bounds(r);mesh.custom_aabb=bounds;node.custom_aabb=bounds
	var cpu:Mesh=Cpu.remember(mesh,packet.arrays);cpu.bounds=bounds
	# ArrayMesh region updates do not refresh its native triangle/AABB caches.
	# Route authoring reads through the fresh canonical CPU mesh, not those caches.
	node.set_meta("paint_source",cpu)
	if node.has_meta("paint_geometry"):node.remove_meta("paint_geometry")
	node.set_meta("ground_batch_record",r.duplicate(true))
	preload("res://scripts/world3d/river_materials.gd").apply(node,r,context)
	state.record=r.duplicate(true);state.arrays=packet.arrays;state.normals=context.get("normals",{}).duplicate(true)
	last_work={"private_copy":copied,"bytes":packet.bytes,"regions":packet.updates.size(),"collision_blocks":packet.shapes.size(),"total_blocks":state.blocks.size(),"cpu_patch":packet.get("cpu_patch",{})}

	node.set_meta("terrain_local_stats",last_work.duplicate())

static func intersect_ray(space:PhysicsDirectSpaceState3D,query:PhysicsRayQueryParameters3D,host:Node)->Dictionary:
	var pending:Dictionary=host.get_meta("terrain_pending_rays",{})
	var active:Array=[];var excluded:Array[RID]=query.exclude.duplicate()
	for id:int in pending.keys():
		var node:Node=pending[id].node.get_ref()
		if not is_instance_valid(node) or Engine.get_physics_frames()>int(pending[id].frame)+1:
			pending.erase(id);continue
		var state:Dictionary=node.get_meta(META,{})
		if state.is_empty() or not is_instance_valid(state.body):pending.erase(id);continue
		var body:StaticBody3D=state.body
		if not query.collide_with_bodies or body.get_rid() in query.exclude or body.collision_layer&query.collision_mask==0:continue
		excluded.append(body.get_rid());active.append(state)
	if active.is_empty():return space.intersect_ray(query)
	var native_query:=PhysicsRayQueryParameters3D.create(query.from,query.to,query.collision_mask,excluded)
	native_query.collide_with_areas=query.collide_with_areas;native_query.collide_with_bodies=query.collide_with_bodies
	native_query.hit_back_faces=query.hit_back_faces;native_query.hit_from_inside=query.hit_from_inside
	var hit:=space.intersect_ray(native_query)
	var distance:float=query.from.distance_to(hit.position) if not hit.is_empty() else query.from.distance_to(query.to)
	for state:Dictionary in active:
		var body:StaticBody3D=state.body;var inverse:=body.global_transform.affine_inverse()
		var origin:=inverse*query.from;var end:=inverse*query.to;var direction:=end-origin
		for shape:CollisionShape3D in state.blocks.values():
			if shape.disabled:continue
			var geometry:ConcavePolygonShape3D=shape.shape
			var soup:PackedVector3Array=geometry.get_faces()
			var bounds:=AABB(soup[0],Vector3.ZERO)
			if geometry.has_meta("terrain_ray_bounds"):bounds=geometry.get_meta("terrain_ray_bounds")
			else:
				for p:Vector3 in soup:bounds=bounds.expand(p)
				geometry.set_meta("terrain_ray_bounds",bounds)
			if not bounds.grow(.0001).intersects_segment(origin,end):continue
			for i in range(0,soup.size(),3):
				var normal:Vector3=(soup[i+2]-soup[i]).cross(soup[i+1]-soup[i]).normalized()
				if not query.hit_back_faces and normal.dot(direction)>=0:continue
				var local:Variant=Geometry3D.segment_intersects_triangle(origin,end,soup[i],soup[i+1],soup[i+2])
				if local==null:continue
				var position:Vector3=body.global_transform*local;var measured:=position.distance_to(query.from)
				if measured>distance:continue
				distance=measured
				hit={"position":position,"normal":(body.global_transform.basis.inverse().transposed()*normal).normalized(),"collider":body,"collider_id":body.get_instance_id(),"rid":body.get_rid(),"shape":shape.get_index(),"face_index":i/3}
	return hit
