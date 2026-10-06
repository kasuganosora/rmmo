extends "res://tools/test_ground_batch_lifetime.gd"
func run()->void:
	var host:=Node3D.new();root.add_child(host);var batch:=Batch.new();host.add_child(batch)
	var nodes:Array=[];var shared:=BoxMesh.new()
	for house in 6:
		for floor_ in 2:
			for part in 3:
				var node:=MeshInstance3D.new();node.mesh=shared;node.name="h%d_f%d_p%d"%[house,floor_,part]
				var rotation_:Basis=Basis(Vector3.UP,house*.43)
				node.transform=Transform3D(rotation_,Vector3(20+house*30,1+floor_*4,20)+rotation_*Vector3(part,0,0))
				node.set_meta("ground_batch_record",{"uuid":str(node.name),"kind":"box","size":[1,1,1],"building":{"id":"h%d"%house,"floor":floor_,"part":str(node.name),"role":"wall"},"fixture":{"id":"window","kind":"window"}})
				host.add_child(node);nodes.append(node)
	batch.sync(nodes);batch.flush()
	var groups:Array=batch.groups.values();check(groups.size()==12,"house and floor groups remain independent")
	check(batch.building_mesh_hits==11,"rotated equivalent groups share one immutable render mesh")
	for merged:Dictionary in groups:
		var expected:=PackedVector3Array()
		for source in merged.members:expected.append_array(source.global_transform*source.mesh.get_faces())
		var actual:PackedVector3Array=merged.visual.global_transform*merged.visual.mesh.get_faces()
		var same:=actual.size()==expected.size()
		for i in mini(actual.size(),expected.size()):
			if actual[i].distance_to(expected[i])>.0002:same=false;break
		check(same,"canonical batch retains world-space triangle positions")
	var group:Dictionary=groups[0];var before:Transform3D=group.visual.global_transform
	for node in group.members:node.position.x+=2
	await process_frame;await process_frame
	check(group.visual.global_position.is_equal_approx(before.origin+Vector3(2,0,0)),"fixture movement updates through transform notification")
	check(groups[1].visual.global_transform!=group.visual.global_transform,"other group pose remains independent")
	var pivot:Vector3=group.members[0].global_position
	var turn:=Transform3D(Basis(Vector3.UP,.8),pivot)
	var unpivot:=Transform3D(Basis.IDENTITY,-pivot)
	var old_pose:Transform3D=group.visual.global_transform
	for node in group.members:node.global_transform=turn*unpivot*node.global_transform
	await process_frame;await process_frame
	check(group.visual.global_transform.is_equal_approx(turn*unpivot*old_pose),"opening rotated fixture keeps shared geometry attached")
	for node in group.members:node.hide()
	check(not group.visual.visible and groups[1].visual.visible,"shared mesh retains independent floor visibility")
	var unchanged:Mesh=groups[1].visual.mesh
	var first:MeshInstance3D=groups[1].members[0];batch.release([str(first.name)])
	first.mesh=BoxMesh.new();first.mesh.size=Vector3(2,1,1)
	batch.sync(nodes);batch.flush()
	var changed:Dictionary=batch.groups[batch._member_groups[str(first.name)]]
	check(changed.visual.mesh!=unchanged,"one-house geometry edit does not mutate shared buffers")
	host.free();print("HOUSE_BATCH_SHARE_FINISHED failures=",failed);quit(1 if failed else 0)
