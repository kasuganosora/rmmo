extends RefCounted
## Native Godot spring adapter. Kept opt-in until real contact/visual acceptance.
var simulators:Array[SpringBoneSimulator3D]=[]
var snapshots:Dictionary={}
var contacts:Array=[]
var contacts_enabled:=false

func install_contacts(body:Node3D)->void:
	var path:String=preload("res://scripts/asset/art_paths.gd").path("characters/hair/female_base_v2/body_contacts.json")
	if not FileAccess.file_exists(path):return
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	for simulator in simulators:
		for spec:Dictionary in data.shapes:
			var index:int=body.skeleton.find_bone(spec.bone)
			assert(index>=0,"Source hair collider target bone missing")
			var capsule:=SpringBoneCollisionCapsule3D.new()
			capsule.name=spec.source
			capsule.inside=spec.inside
			simulator.add_child(capsule)
			contacts.append({"node":capsule,"bone":index,"a":Vector3(spec.a[0],spec.a[1],spec.a[2]),"b":Vector3(spec.b[0],spec.b[1],spec.b[2]),"radius":float(spec.radius)})
	set_contacts_enabled(false)
	sync_contacts(body)

func set_contacts_enabled(value:bool)->void:
	contacts_enabled=value
	for simulator in simulators:
		var shapes:Array=[]
		for spec:Dictionary in contacts:
			if spec.node.get_parent()==simulator:shapes.append(spec.node)
		for i in simulator.setting_count:
			# Explicit paths refresh the native cached list when toggled. Merely
			# flipping enable_all_child_collisions did not rebuild it in our run.
			simulator.set_enable_all_child_collisions(i,false)
			simulator.set_collision_count(i,shapes.size() if value else 0)
			if value:
				for j in shapes.size():simulator.set_collision_path(i,j,simulator.get_path_to(shapes[j]))

func sync_contacts(body:Node3D)->void:
	for spec:Dictionary in contacts:
		var pose:Transform3D=body.solved_bones[spec.bone]
		var a:Vector3=body.global_transform*(pose*spec.a+body.root_offset)
		var b:Vector3=body.global_transform*(pose*spec.b+body.root_offset)
		var size:Vector3=body.global_basis.get_scale().abs()
		var radius:float=spec.radius*maxf(size.x,maxf(size.y,size.z))
		var capsule:SpringBoneCollisionCapsule3D=spec.node
		capsule.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())) if a.distance_to(b)>.00001 else Basis.IDENTITY,(a+b)*.5)
		capsule.radius=radius
		capsule.height=a.distance_to(b)+2*radius

static func bake_fit(source:Node3D,fit:Transform3D)->float:
	var max_error:=0.0
	for skeleton:Skeleton3D in source.find_children("*","Skeleton3D",true,false):
		var old:Array[Transform3D]=[]
		var current:Array[Transform3D]=[]
		if skeleton.has_meta("native_unfitted_rests"):
			old.assign(skeleton.get_meta("native_unfitted_rests"))
		else:
			for i in skeleton.get_bone_count():old.append(skeleton.get_bone_global_rest(i))
			skeleton.set_meta("native_unfitted_rests",old.duplicate())
		for i in skeleton.get_bone_count():
			var rest:Transform3D=old[i]
			current.append(Transform3D((fit.basis*rest.basis).orthonormalized(),fit*rest.origin))
		for mesh:MeshInstance3D in skeleton.find_children("*","MeshInstance3D",true,false):
			var original:Skin=mesh.skin
			if mesh.has_meta("native_unfitted_skin"):original=mesh.get_meta("native_unfitted_skin")
			else:mesh.set_meta("native_unfitted_skin",original)
			var skin:=Skin.new()
			for j in original.get_bind_count():
				var index:=original.get_bind_bone(j)
				var target:Transform3D=fit*old[index]*original.get_bind_pose(j)
				var bind:Transform3D=current[index].affine_inverse()*target
				skin.add_bind(index,bind)
				var restored:Transform3D=current[index]*bind
				max_error=maxf(max_error,(restored.origin-target.origin).length())
				for axis in 3:max_error=maxf(max_error,(restored.basis[axis]-target.basis[axis]).length())
			mesh.skin=skin
			# Native renderer rest transforms are already in its bind matrices.
			var aabb:=AABB();var first:=true
			for surface in mesh.mesh.get_surface_count():
				var arrays:Array=mesh.mesh.surface_get_arrays(surface)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var ids:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
				var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
				for vertex in vertices.size():
					var p:=Vector3.ZERO
					for slot in 4:
						var k:=vertex*4+slot;var binding:=ids[k]
						p+=(current[skin.get_bind_bone(binding)]*skin.get_bind_pose(binding)*vertices[vertex])*weights[k]
					if first:aabb=AABB(p,Vector3.ZERO);first=false
					else:aabb=aabb.expand(p)
			mesh.set_meta("native_fitted_rest_bounds",aabb)
			mesh.custom_aabb=aabb.grow(.1)
		for i in skeleton.get_bone_count():
			var parent:=skeleton.get_bone_parent(i)
			var local:Transform3D=current[parent].affine_inverse()*current[i] if parent>=0 else current[i]
			skeleton.set_bone_rest(i,local)
			skeleton.reset_bone_pose(i)
	return max_error

func install(source:Node3D)->void:
	for skeleton:Skeleton3D in source.find_children("*","Skeleton3D",true,false):
		var chains:Array=skeleton.get_meta("source_spring_chains",[])
		if chains.is_empty():continue
		var simulator:=SpringBoneSimulator3D.new()
		simulator.name="NativeHairSpring"
		skeleton.add_child(simulator)
		simulator.setting_count=chains.size()
		for i in chains.size():
			var chain:Dictionary=chains[i]
			simulator.set_root_bone(i,chain.bones[0])
			simulator.set_end_bone(i,chain.bones[-1])
			simulator.set_extend_end_bone(i,false)
			simulator.set_drag(i,float(chain.source_config.m_Damping))
			# Different engines use different stiffness equations. Native 1.0 is
			# the evaluation baseline, not an asserted numeric DynamicBone port.
			simulator.set_stiffness(i,1.0)
			simulator.set_gravity(i,0.0)
			simulator.set_radius(i,float(chain.source_config.m_Radius))
		simulator.modification_processed.connect(func():
			var poses:Array[Transform3D]=[]
			for j in skeleton.get_bone_count():poses.append(skeleton.get_bone_global_pose(j))
			snapshots[skeleton.get_instance_id()]=poses)
		simulators.append(simulator)
		simulator.reset()

func set_enabled(value:bool)->void:
	for simulator in simulators:
		simulator.active=value
		simulator.reset()
