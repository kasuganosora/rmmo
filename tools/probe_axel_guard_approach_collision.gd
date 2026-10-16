extends "res://tools/review_axel_functional_building_exteriors.gd"
## Read-only isolated headless physics, using current native source triangles.
const Road=preload("res://scripts/world3d/road_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Authority=preload("res://scripts/world3d/world_authority.gd")
class ProbeBody extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface()->void:pass
var host:Node3D
var actor:ProbeBody
var authority:RefCounted
var sequence:=0
func add_faces(faces:PackedVector3Array,id:String,source:String,pose:Transform3D=Transform3D.IDENTITY)->void:
	if faces.is_empty():return
	var body:=StaticBody3D.new();body.set_meta("uuid",id);body.set_meta("source",source)
	var collision:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);collision.shape=shape;body.add_child(collision);host.add_child(body);body.global_transform=pose
func closest_triangle(point:Vector3,triangle:Array)->Vector3:
	var normal:Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
	var projected:Vector3=point-normal*normal.dot(point-triangle[0])
	var inside:=true;var nearest:=Vector3.ZERO;var distance:=INF
	for i in 3:
		var a:Vector3=triangle[i];var b:Vector3=triangle[(i+1)%3]
		if (b-a).cross(projected-a).dot(normal)<-.000001:inside=false
		var at:=Geometry3D.get_closest_point_to_segment(point,a,b)
		if at.distance_to(point)<distance:distance=at.distance_to(point);nearest=at
	return projected if inside else nearest
func contact_rows(collision:KinematicCollision3D)->Array:
	var result:Array=[]
	for i in collision.get_collision_count():
		var collider:=collision.get_collider(i)
		result.append({"id":collider.get_meta("uuid","") if collider else "","source":collider.get_meta("source","") if collider else "","position":xyz(collision.get_position(i)),"normal":xyz(collision.get_normal(i))})
	return result
func cast_at(point:Vector3,motion:Vector3)->Dictionary:
	actor.global_position=point+Vector3.UP*.9;actor.velocity=Vector3.ZERO
	var collision:=KinematicCollision3D.new();var hit:=actor.test_move(actor.global_transform,motion,collision,.001,false,16)
	return {"feet":xyz(point),"motion":xyz(motion),"hit":hit,"travel":xyz(collision.get_travel()),"contacts":contact_rows(collision)}
func ray_floor(point:Vector3)->Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.6,point-Vector3.UP*.6,1,[actor.get_rid()])
	var hit:=host.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return {}
	return {"id":hit.collider.get_meta("uuid",""),"source":hit.collider.get_meta("source",""),"position":xyz(hit.position),"normal":xyz(hit.normal)}
func walk_probe(start:Vector3,target:Vector3,label_:String)->Dictionary:
	actor.global_position=start+Vector3.UP*.9;actor.velocity=Vector3.ZERO
	var first_contacts:Array=[];var minimum_y:=start.y
	var sample:Array=[]
	for tick in 180:
		await physics_frame
		var wish:=Vector3(target.x-actor.position.x,0,target.z-actor.position.z)
		if wish.length()<.08:break
		sequence+=1;authority.move_intent(sequence,wish.normalized(),minf(4.,wish.length()*60.))
		minimum_y=minf(minimum_y,actor.position.y-.9)
		if tick in [0,1,2,5,20,59,119,179]:
			var contacts:Array=[]
			for i in actor.get_slide_collision_count():contacts.append_array(contact_rows(actor.get_slide_collision(i)))
			sample.append({"tick":tick,"feet":xyz(actor.position-Vector3.UP*.9),"velocity":xyz(actor.velocity),"on_floor":actor.is_on_floor(),"contacts":contacts})
	return {"label":label_,"start":xyz(start),"end":xyz(actor.position-Vector3.UP*.9),"remaining_xz":Vector2(actor.position.x-target.x,actor.position.z-target.z).length(),"minimum_y":minimum_y,"samples":sample}
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/final_candidate_records.json"))
	var all_records:Array=data.records
	var stopped:=Vector3(162.39045715332,7.41017198562622,180.379974365234)
	var target:=Vector3(158.5,7.43635892868042,180.5)
	var corridor:=Rect2(Vector2(minf(stopped.x,target.x),minf(stopped.z,target.z)),Vector2(absf(stopped.x-target.x),absf(stopped.z-target.z))).grow(1.)
	var direction:=Vector3(target.x-stopped.x,0,target.z-stopped.z).normalized()
	host=Node3D.new();root.add_child(host)
	var record:Dictionary=all_records.filter(func(r):return r.uuid=="obj_1233")[0]
	var source:=source_data(record.asset_path);var bounds:=Bounds.read(record.asset_path)
	var nearest:Array=[];var triangles:=0
	for part:Dictionary in bounds.mesh_nodes:
		var node:Dictionary=source.json.nodes[part.node_index];var extras:Dictionary=node.get("extras",{})
		if extras.get("rmmo_collision","")=="none":continue
		var id:=str(extras.get("rmmo_source_uuid",extras.get("uuid","")))
		var pose:Transform3D=Imported.frame(record)*part.transform
		var faces:=PackedVector3Array();var distance:=INF;var closest:=Vector3.ZERO
		for primitive:Dictionary in source.json.meshes[part.mesh_index].primitives:
			var positions:=accessor(source,int(primitive.attributes.POSITION));var indices:=accessor(source,int(primitive.indices)) if primitive.has("indices") else range(positions.size())
			for i in range(0,indices.size(),3):
				var tri:Array=[pose*positions[indices[i]],pose*positions[indices[i+1]],pose*positions[indices[i+2]]]
				faces.append_array(PackedVector3Array([tri[0],tri[2],tri[1]]));triangles+=1
				var at:=closest_triangle(stopped+Vector3.UP*.9,tri)
				if at.distance_to(stopped+Vector3.UP*.9)<distance:distance=at.distance_to(stopped+Vector3.UP*.9);closest=at
		add_faces(faces,"obj_1233__"+id,"guardhouse "+str(extras.get("rmmo_part",{})))
		nearest.append({"source_id":id,"semantic":extras.get("rmmo_part",{}),"nearest_surface_point":xyz(closest),"distance_to_capsule_center_m":distance})
	nearest.sort_custom(func(a,b):return a.distance_to_capsule_center_m<b.distance_to_capsule_center_m)
	var local_roads:Array=[];var terrains:Array=[]
	for item:Dictionary in all_records:
		if item.has("road_mesh"):
			var pose:=Terrain.transform(item);var box:=pose*AABB(-vector(item.size)*.5,vector(item.size))
			if not Rect2(box.position.x,box.position.z,box.size.x,box.size.z).intersects(corridor,true):continue
			var built:=Road.arrays(item)
			for index in built.size():
				var cpu:=Cpu.new();cpu.surfaces=[built[index]];add_faces(cpu.collision_faces(),item.uuid,"road surface "+str(index),pose)
			local_roads.append({"id":item.uuid,"position":item.position,"size":item.size,"surface_count":built.size(),"source":item.get("road_source","")})
		elif item.has("terrain_mesh"):
			var pose:=Terrain.transform(item);var box:AABB=pose*Terrain.bounds(item)
			if not Rect2(box.position.x,box.position.z,box.size.x,box.size.z).intersects(corridor,true):continue
			var cpu:=Cpu.new();cpu.surfaces=Terrain.arrays(item);add_faces(cpu.collision_faces(),item.uuid,"terrain",pose);terrains.append(item.uuid)
	actor=ProbeBody.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.9;collider.shape=capsule;collider.position.y=.05;actor.add_child(collider);host.add_child(actor);actor.floor_snap_length=.2
	authority=Authority.new();authority.mount(actor,null,"read_only_isolated_probe")
	# Every fixture's real shape has been installed above, so this isolated
	# fixture can provide its own publication receipt without town streaming.
	var published:=Engine.get_physics_frames()
	authority.traversal_guard=func(_aabb):return {"ok":true,"physics_published_frame":published}
	for tick in 5:await physics_frame
	var floor_hit:=ray_floor(stopped);var casts:Array=[]
	for rise:float in [0.,.002,.025,.035,.08]:casts.append(cast_at(stopped+Vector3.UP*rise,direction*.066667))
	var walks:Array=[];walks.append(await walk_probe(stopped,target,"logged stop pose with complete source geometry"))
	if not floor_hit.is_empty():walks.append(await walk_probe(vector(floor_hit.position)+Vector3.UP*.002,target,"exact actual road top with complete source geometry"))
	var result:={"scope":"Read-only actual guard source triangles plus native road/terrain triangle arrays; isolated headless PhysicsServer and unchanged WorldAuthority; no navigation or town residency proof","candidate_sha256":data.map_sha256,"source_sha256":FileAccess.get_sha256(record.asset_path),"source_triangle_count":triangles,"nearest_source_components":nearest.slice(0,5),"road_records":local_roads,"terrain_records":terrains,"actual_floor_at_stop":floor_hit,"casts":casts,"authority_walks":walks}
	var file:=FileAccess.open(FB_OUT+"/guard_approach_collision_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close();print("GUARD_APPROACH_PROBE ",JSON.stringify(result));quit()
