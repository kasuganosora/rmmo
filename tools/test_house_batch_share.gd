extends "res://tools/test_ground_batch_lifetime.gd"
func run()->void:
	var host:=Node3D.new();root.add_child(host);var batch:=Batch.new();host.add_child(batch)
	var nodes:Array=[];var shared:=BoxMesh.new()
	for house in 2:
		for floor_ in 2:
			for part in 3:
				var node:=MeshInstance3D.new();node.mesh=shared;node.name="h%d_f%d_p%d"%[house,floor_,part]
				node.position=Vector3(house*30+part,1+floor_*4,0)
				node.set_meta("ground_batch_record",{"uuid":str(node.name),"kind":"box","size":[1,1,1],"building":{"id":"h%d"%house,"floor":floor_,"part":str(node.name),"role":"wall"},"fixture":{"id":"window","kind":"window"}})
				host.add_child(node);nodes.append(node)
	batch.sync(nodes);batch.flush()
	var groups:Array=batch.groups.values();check(groups.size()==4,"house and floor groups remain independent")
	check(batch.building_mesh_hits==3,"equivalent groups share one immutable render mesh")
	var group:Dictionary=groups[0];var before:Transform3D=group.visual.global_transform
	for node in group.members:node.position.x+=2
	await process_frame;await process_frame
	check(group.visual.global_position.is_equal_approx(before.origin+Vector3(2,0,0)),"fixture movement updates through transform notification")
	check(groups[1].visual.global_transform!=group.visual.global_transform,"other group pose remains independent")
	for node in group.members:node.hide()
	check(not group.visual.visible and groups[1].visual.visible,"shared mesh retains independent floor visibility")
	var unchanged:Mesh=groups[1].visual.mesh
	var first:MeshInstance3D=groups[1].members[0];batch.release([str(first.name)])
	first.mesh=BoxMesh.new();first.mesh.size=Vector3(2,1,1)
	batch.sync(nodes);batch.flush()
	var changed:Dictionary=batch.groups[batch._member_groups[str(first.name)]]
	check(changed.visual.mesh!=unchanged,"one-house geometry edit does not mutate shared buffers")
	host.free();print("HOUSE_BATCH_SHARE_FINISHED failures=",failed);quit(1 if failed else 0)
