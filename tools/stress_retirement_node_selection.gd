extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Probe=preload("res://scripts/world3d/retirement_node_selection.gd")
var failures:=0
class Batcher extends RefCounted:
	var observed:Array=[]
	func retire_sources(nodes:Array)->void:
		for node:Node in nodes:observed.append(node.get_instance_id())
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func retire(ids:Array,meshes:Dictionary,bodies:Dictionary,batcher:Batcher,fused:bool)->int:
	var calls:=0
	if fused:
		var selected:=Probe.collect(ids,meshes,bodies)
		batcher.retire_sources(selected.nodes)
		for id:String in selected.ids:
			if meshes.has(id):Stream._drop(meshes,id,meshes.get(id));calls+=1
			if bodies.has(id):Stream._drop(bodies,id,bodies.get(id));calls+=1
	else:
		var nodes:Array=[]
		for id:String in ids:
			if is_instance_valid(meshes.get(id)):nodes.append(meshes[id])
		batcher.retire_sources(nodes)
		for id:String in ids:
			Stream._drop(meshes,id,meshes.get(id));Stream._drop(bodies,id,bodies.get(id));calls+=2
	return calls
func trial(ids:Array,fused:bool)->Dictionary:
	var elapsed:=0;var calls:=0;var released:=0
	for repeat:int in 32:
		var meshes:Dictionary={};var bodies:Dictionary={};var watches:Array=[];var expected:Array=[]
		# Most selected sources already lost their active draw/physics nodes on
		# departure. Null entries still belong to the dictionaries and must erase.
		for i:int in 10:
			var node:=Node3D.new();meshes[ids[i]]=node;expected.append(node.get_instance_id());watches.append(weakref(node))
		for i:int in 5:
			var node:=StaticBody3D.new();bodies[ids[i]]=node;watches.append(weakref(node))
		meshes[ids[20]]=null;bodies[ids[21]]=null
		var survivor:=Node3D.new();var survivor_body:=StaticBody3D.new()
		meshes.keep=survivor;bodies.keep=survivor_body
		var batcher:=Batcher.new();var began:=Time.get_ticks_usec()
		calls+=retire(ids,meshes,bodies,batcher,fused)
		elapsed+=Time.get_ticks_usec()-began
		if meshes!={"keep":survivor} or bodies!={"keep":survivor_body} or batcher.observed!=expected or not watches.all(func(w):return w.get_ref()==null):failures+=1
		released+=watches.size();survivor.free();survivor_body.free()
	return {"fused":fused,"us":elapsed,"selected_ids":ids.size()*32,"drop_calls":calls,"released_nodes":released}
func run()->void:
	var ids:Array=[]
	for i:int in 2200:ids.append("guild__part%d"%i)
	var trials:Array=[]
	for fused:bool in [false,true,true,false]:trials.append(trial(ids,fused))
	check(failures==0,"same 2200 selected IDs, live-node order, survivors, null cleanup and final node release")
	check(trials[0].drop_calls==140800 and trials[1].drop_calls==544,"only existing owner slots reach node destruction")
	var empty:=Probe.collect([],{},{});check(empty=={"ids":[],"nodes":[]},"empty retirement stays empty")
	var report:={"failures":failures,"trials":trials}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RETIREMENT_NODE_SELECTION ",JSON.stringify(report));quit(1 if failures else 0)
