extends SceneTree
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
class CountedCpu extends Cpu:
	var uploads:=0
	func restore()->Mesh:
		uploads+=1
		return BoxMesh.new()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(count:int)->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	# Sources published later than the batch service exit first in Godot.
	var batch:=Batch.new();map.add_child(batch);batch.set_process(false)
	var meshes:Array=[];var nodes:Array=[]
	for at:int in count:
		var mesh:=CountedCpu.new();meshes.append(mesh)
		var node:=MeshInstance3D.new();node.name="row%d"%at;node.mesh=mesh;map.add_child(node);nodes.append(node)
	for at:int in range(0,count,16):
		var key:=str(at);var group:={"members":nodes.slice(at,mini(at+16,count)),"category":"ground","generation":at+1}
		batch.groups[key]=group;batch._watch_group(key,group)
		for node:Node in group.members:batch._member_groups[str(node.name)]=key
	return {"map":map,"batch":batch,"meshes":meshes,"nodes":nodes}
func uploads(meshes:Array)->int:
	var result:=0
	for mesh:Mesh in meshes:result+=mesh.uploads
	return result
func run()->void:
	var results:Array=[]
	for permanent:bool in [false,true,true,false]:
		var f:=fixture(2048);var began:=Time.get_ticks_usec()
		if permanent:preload("res://scripts/world3d/world_stream.gd").prepare_map_disposal(f.map,self)
		else:f.batch.retire_workers(self)
		f.map.free()
		results.append({"permanent":permanent,"uploads":uploads(f.meshes),"us":Time.get_ticks_usec()-began})
		check(uploads(f.meshes)==(0 if permanent else 2048),"permanent cleanup avoids all uploads; legacy callbacks reproduce one per dying source")
	var f:=fixture(16);f.nodes[0].free()
	check(uploads(f.meshes)==16,"ordinary single-source removal still restores every unbatched survivor")
	f.map.free()
	f=fixture(16);root.remove_child(f.map);root.add_child(f.map)
	check(uploads(f.meshes)==16 and f.nodes.all(func(node):return not node.mesh is Cpu),"temporary detach/re-entry preserves standalone visibility")
	f.map.free()
	print("MAP_BATCH_DISPOSAL ",JSON.stringify({"trials":results,"failures":failures}));quit(1 if failures else 0)
