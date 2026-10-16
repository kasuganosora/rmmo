extends RefCounted
## Actual render/physics objects, never merely a CPU spec. Call AFTER the last
## publish/hinge physics tick. Full building membership may span many chunks.
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")

static func inspect(snapshot:Dictionary,root:Node,physics_frame:int,published_frame:int)->Dictionary:
	if snapshot.get("membership")!="indoor":return {"ok":false,"reason":"building_not_required"}
	if not is_instance_valid(root):return {"ok":false,"reason":"map_unavailable"}
	var b:Dictionary=snapshot.building
	var receipt:Dictionary={"instance_id":b.instance_id,"structure_revision":b.structure_revision,"pose_revision":b.pose_revision,"state_sequence":b.state_watermark,"member_ids":b.member_ids.duplicate(),"fixture_states":{},"structure_ready":true,"render_ready":true,"physics_synchronized":physics_frame>published_frame and published_frame>=0,"interactions_bound":true}
	var specs:Dictionary={};var missing:Array=[]
	for spec:Dictionary in root.get_meta("stream_library",[]):
		var uuid:String=str(spec.get("extras",{}).get("uuid",spec.get("uuid","")))
		if spec.get("extras",{}).get("building",{}).get("id")==b.instance_id and uuid not in b.member_ids:receipt.structure_ready=false
		if uuid in b.member_ids:
			if not specs.has(uuid):specs[uuid]=[]
			specs[uuid].append(spec)
	var meshes:Dictionary=root.get_meta("stream_meshes",{})
	var bodies:Dictionary=root.get_meta("stream_bodies",{})
	var batches:=root.get_node_or_null("GroundRenderBatches")
	var solid_batches:=root.get_node_or_null("FortificationCollisionBatches")
	for uuid:String in b.member_ids:
		if not specs.has(uuid):receipt.structure_ready=false;missing.append(uuid);continue
		for spec:Dictionary in specs[uuid]:
			var key:String=spec.uuid
			var r:Dictionary=spec.get("extras",{})
			if r.get("building",{}).get("id")!=b.instance_id:receipt.structure_ready=false
			var mesh:Variant=meshes.get(key)
			if not spec.get("native_visual",false):
				if not is_instance_valid(mesh) or not mesh.is_inside_tree() or mesh.is_queued_for_deletion() or mesh.mesh==null:receipt.render_ready=false
				elif mesh.mesh is CpuMesh:
					var batch_key:String=str(batches._member_groups.get(key,"")) if batches!=null else ""
					if batches==null or batch_key.is_empty() or not batches.groups.has(batch_key) or not is_instance_valid(batches.groups[batch_key].get("visual")):receipt.render_ready=false
			if str(r.get("rmmo_collision",r.get("collision","")))!="none" and not spec.get("native_visual",false):
				var body:Variant=bodies.get(key)
				if not is_instance_valid(body) and solid_batches!=null and solid_batches.has_method("body_for"):body=solid_batches.body_for(key)
				if not _body_ready(body,physics_frame):receipt.physics_synchronized=false
			var fixture:Dictionary=r.get("fixture",{})
			if not fixture.is_empty():
				if not spec.get("closed_transform") is Transform3D:receipt.interactions_bound=false
				else:
					var expected:Transform3D=Fixtures.pose(spec.closed_transform,fixture,float(fixture.open))
					if not spec.transform.is_equal_approx(expected):receipt.interactions_bound=false
					if is_instance_valid(mesh) and not mesh.global_transform.is_equal_approx(expected):receipt.interactions_bound=false
					var fixture_body:Variant=bodies.get(key)
					if is_instance_valid(fixture_body) and not fixture_body.global_transform.is_equal_approx(expected):receipt.physics_synchronized=false
				var id:String=fixture.id
				if receipt.fixture_states.has(id) and not is_equal_approx(float(receipt.fixture_states[id]),float(fixture.open)):receipt.interactions_bound=false
				receipt.fixture_states[id]=float(fixture.open)
	if receipt.fixture_states!=b.fixture_states:receipt.interactions_bound=false
	receipt.ok=receipt.structure_ready and receipt.render_ready and receipt.physics_synchronized and receipt.interactions_bound
	receipt.missing_members=missing
	return receipt

static func _body_ready(body:Variant,physics_frame:int)->bool:
	if not is_instance_valid(body) or not body is CollisionObject3D or not body.is_inside_tree() or body.is_queued_for_deletion() or body.collision_layer==0:return false
	if not body.has_meta("stream_physics_published_frame") or int(body.get_meta("stream_physics_published_frame"))>=physics_frame:return false
	for owner:int in body.get_shape_owners():
		if not body.is_shape_owner_disabled(owner) and body.shape_owner_get_shape_count(owner)>0:return true
	return false
