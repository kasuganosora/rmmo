extends "res://tools/test_ground_batch_lifetime.gd"
func run()->void:
	var host:=Node3D.new();host.name="asset_one";root.add_child(host)
	var other:=Node3D.new();other.name="asset_two";root.add_child(other)
	var first:=sources(host);var second:=sources(other)
	for i in second.size():second[i].name="second_part%d"%i
	host.set_meta("model_component_batch_sources",first)
	other.set_meta("model_component_batch_sources",second)
	var batch:=Batch.new();root.add_child(batch);batch.set_process(false)
	batch.sync([host,other]);batch.flush()
	check(batch.groups.size()>0,"nested imported sources batch through holder contract")
	batch.sync_selection([host,other],["asset_one"])
	for node in first:check(not node.mesh is Cpu,"whole-model selection immediately restores every child")
	batch.flush()
	for group:Dictionary in batch.groups.values():
		check(group.members.all(func(n):return n in second),"selected model excluded without excluding another instance")
	batch.sync([host,other]);batch.flush();batch.release_sources([host])
	check(batch.groups.is_empty(),"parent replacement releases affected combined groups immediately")
	batch.sync([host,other]);batch.flush();host.free()
	check(batch.groups.is_empty(),"parent deletion leaves no stale combined draw")
	batch.sync([other]);batch.flush();check(batch.groups.size()==1,"surviving model regroups after another instance disappears")
	batch.clear();other.free();batch.free()
	print("IMPORTED_MODEL_BATCHES failures=",failed);quit(0 if failed==0 else 1)
