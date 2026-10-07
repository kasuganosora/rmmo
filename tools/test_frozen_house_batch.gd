extends "res://tools/test_ground_batch_lifetime.gd"
const Candidate=preload("res://review_artifacts/frozen_house_batch_candidate_20261007/batcher.gd")

func settle_batch(batch:Node)->void:
	await process_frame
	await process_frame
	while not batch._preparation.is_empty():batch._prepare_step(0)
	batch.flush()

func frozen_sources(host:Node3D)->Array:
	var nodes:=sources(host)
	for node in nodes:
		var record:Dictionary=node.get_meta("ground_batch_record")
		record.house_prefab={};record.building.role="shell";record.building.floor_y=0.
	return nodes

func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	var host:=Node3D.new();root.add_child(host)
	var batch:=Candidate.new();host.add_child(batch);batch.set_process(false)
	var nodes:=frozen_sources(host)
	batch.sync(nodes);batch.flush()
	check(batch.groups.is_empty(),"frozen candidate stays opt-in")
	batch.frozen_houses_enabled=true
	batch.sync(nodes);batch.flush()
	check(batch.groups.size()==1 and batch.groups.values()[0].members.size()==3,"same semantic partition merges")
	for index in 3:
		var old:Node=batch.groups.values()[0].visual
		nodes[index].hide()
		check(not is_instance_valid(old) and batch.groups.is_empty(),"hide any member removes batch immediately")
		check(nodes.all(func(node):return not node.mesh is Cpu),"all original meshes restored without changing visible flags")
		await settle_batch(batch)
		check(batch.groups.size()==1 and batch.groups.values()[0].members.size()==2,"hidden member excluded from automatic rebuild")
		nodes[index].show();await settle_batch(batch)
		check(batch.groups.size()==1 and batch.groups.values()[0].members.size()==3,"show automatically restores full membership")
	nodes[0].hide();nodes[1].hide();await settle_batch(batch)
	check(batch.groups.is_empty(),"singleton remains a direct draw")
	nodes[1].show();await settle_batch(batch)
	check(batch.groups.size()==1,"singleton keeps show subscription")
	nodes[0].show();await settle_batch(batch)
	# Hide after prepare has collected members; the old snapshot must not add them.
	batch.clear();batch.request_sync(nodes)
	while not batch._preparation.is_empty() and batch._preparation.phase!="add":batch._prepare_step(1)
	nodes[1].hide();await settle_batch(batch)
	check(batch.groups.size()==1 and batch.groups.values()[0].members.size()==2,"visibility invalidates pending membership snapshot")
	nodes[1].show();await settle_batch(batch)
	batch.clear();batch._building_meshes.clear();batch.sync(nodes);batch._build_next(true)
	check(batch._workers.size()==1,"frozen worker build starts")
	nodes[1].hide();batch._finish_worker(0)
	check(batch.groups.is_empty(),"hidden member prevents stale worker publication")
	await settle_batch(batch);nodes[1].show();await settle_batch(batch)
	var baseline:Dictionary=nodes[0].get_meta("ground_batch_record").duplicate(true)
	for field in ["fixture","fortification","event","seat"]:
		var rejected:=baseline.duplicate(true);rejected[field]={}
		check(not Candidate.Geometry.frozen_house_candidate(rejected),"reject dynamic/foreign semantic "+field)
	for role in ["roof","ceiling"]:
		var rejected:=baseline.duplicate(true);rejected.building.role=role
		check(not Candidate.Geometry.frozen_house_candidate(rejected),"reject role "+role)
	var ceiling:=baseline.duplicate(true);ceiling.building.part="roof/headhouse/ceiling"
	check(not Candidate.Geometry.frozen_house_candidate(ceiling),"headhouse ceiling remains independent")
	for field in ["id","floor","floor_y","role"]:
		batch.release([str(nodes[1].name)])
		var changed:=baseline.duplicate(true);changed.uuid=str(nodes[1].name)
		changed.building[field]={"id":"other","floor":1,"floor_y":3.,"role":"floor"}[field]
		nodes[1].set_meta("ground_batch_record",changed);batch.sync(nodes);batch.flush()
		check(batch.groups.size()==1 and batch.groups.values()[0].members.size()==2,"partition retains "+field)
		changed=baseline.duplicate(true);changed.uuid=str(nodes[1].name);nodes[1].set_meta("ground_batch_record",changed)
		batch.sync(nodes);batch.flush()
	batch.clear()
	check(batch._frozen_watched.is_empty(),"clear removes retained visibility subscriptions")
	nodes[0].hide();await process_frame
	check(batch.groups.is_empty() and batch._preparation.is_empty(),"clear cannot resurrect batches")
	host.free();print("FROZEN_HOUSE_BATCH_FAILED=",failed);quit(1 if failed else 0)
