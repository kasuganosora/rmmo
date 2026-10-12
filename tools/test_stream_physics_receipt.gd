extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Physical=preload("res://scripts/world3d/physical_traversal.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func spec(id:String,at:Vector3,size:Vector3)->Dictionary:
	var node:=MeshInstance3D.new();node.name=id;node.position=at
	var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh
	var result:Dictionary=Stream._spec(node);node.free();return result
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var ground:=spec("floor",Vector3(0,-.25,0),Vector3(16,.5,16))
	var wall:=spec("wall",Vector3(2,1,0),Vector3(.2,2,4))
	map.set_meta("stream_library",[ground,wall]);map.set_meta("stream_children",0)
	for key:String in Index.build([ground,wall]):map.set_meta(key,Index.build([ground,wall])[key])
	var clip:=AABB(Vector3(-.5,-.5,-.5),Vector3(1,3,1))
	check(not Stream.collision_readiness(map,clip).ok,"catalogue alone never grants physical readiness")
	Stream.sync(map,host,Vector3(0,.9,0))
	check(not Stream.collision_readiness(map,clip).ok,"newly published body waits for a later physics frame")
	await physics_frame;await physics_frame;await process_frame
	var receipt:=Stream.collision_readiness(map,clip)
	check(receipt.ok and Physical.readiness(receipt,Engine.get_physics_frames()).ok,"published actual floor becomes ready after physics sync")
	var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.3
	check(Physical.landing(host.get_world_3d().direct_space_state,Vector3.ZERO,capsule,Transform3D(Basis.IDENTITY,Vector3(0,.9,0)),1,[],receipt).ok,"readiness plus real support and capsule fit permits landing")
	var bodies:Dictionary=map.get_meta("stream_bodies")
	var wall_body:Node=bodies[wall.uuid];bodies.erase(wall.uuid)
	check(Stream.collision_readiness(map,clip).ok,"an unrelated missing collider does not block the current footprint")
	var swept:=clip.merge(AABB(Vector3(1.8,-.5,-.5),Vector3(1,3,1)))
	check(not Stream.collision_readiness(map,swept).ok,"swept footprint blocks before reaching a missing wall")
	bodies[wall.uuid]=wall_body;wall_body.collision_layer=0
	check(not Stream.collision_readiness(map,swept).ok,"disabled actual collider cannot grant readiness")
	wall_body.collision_layer=1
	wall_body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	check(not Stream.collision_readiness(map,swept).ok,"republished collider invalidates same-frame receipt")
	await physics_frame;await physics_frame;await process_frame
	check(Stream.collision_readiness(map,swept).ok,"all intersecting colliders are synchronized")
	var void_clip:=AABB(Vector3(60,-.5,60),Vector3(1,3,1))
	check(not Physical.readiness(Stream.collision_readiness(map,void_clip),Engine.get_physics_frames()).ok,"empty indexed space provides no fabricated support watermark")
	host.free()
	print("STREAM_PHYSICS_RECEIPT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
