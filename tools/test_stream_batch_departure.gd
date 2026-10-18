extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var checks:=0
var failures:=0
class CountedCpu extends Cpu:
	var uploads:=0
	func restore()->Mesh:
		uploads+=1
		return BoxMesh.new()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(keep:int=-1)->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var batch:=Batch.new();batch.name="GroundRenderBatches";map.add_child(batch);batch.set_process(false)
	var nodes:Array=[];var rows:Array=[];var meshes:Dictionary={};var by_id:Dictionary={};var cpus:Array=[]
	for i:int in 3:
		var cpu:=CountedCpu.new();cpus.append(cpu)
		var node:=MeshInstance3D.new();node.name="part%d"%i;node.mesh=cpu;map.add_child(node);nodes.append(node);meshes[str(node.name)]=node
		var cell:=Vector2i.ZERO if i==keep else Vector2i(100,100)
		var row:Dictionary={"uuid":str(node.name),"chunk":cell,"chunk_min":cell,"chunk_max":cell,"mesh":cpu,"transform":Transform3D.IDENTITY,"extras":{"rmmo_collision":"none"}}
		rows.append(row);by_id[row.uuid]=row;batch._member_groups[row.uuid]="group"
	var visual:=Node3D.new();batch.add_child(visual)
	batch.groups.group={"members":nodes,"member_ids":meshes.keys(),"visual":visual}
	map.set_meta("stream_by_id",by_id)
	return {"map":map,"batch":batch,"nodes":nodes,"rows":rows,"meshes":meshes,"bodies":{},"cpus":cpus}
func uploads(f:Dictionary)->int:
	var count:=0
	for cpu:CountedCpu in f.cpus:count+=cpu.uploads
	return count
func run()->void:
	var away:=Stream._ring_at(Vector2i.ZERO,Stream.RENDER_RADIUS)
	var back:=Stream._ring_at(Vector2i(100,100),Stream.RENDER_RADIUS)
	var f:=fixture()
	Stream._apply(f.map,f.map,f.rows[0],away,away,f.meshes,f.bodies)
	check(uploads(f)==0,"first departing member never uploads the other members that are also outside demand")
	check(f.batch.groups.is_empty() and f.meshes.size()==2,"old batch is invalidated immediately; node destruction stays incremental")
	check(Stream._needs_work(f.rows[1],back,back,f.meshes,f.bodies),"returning before deletion schedules suspended CPU member for restoration")
	Stream._apply(f.map,f.map,f.rows[1],back,back,f.meshes,f.bodies)
	check(f.cpus[1].uploads==1 and not f.nodes[1].mesh is Cpu,"interrupted departure restores the retained node exactly once on return")
	Stream._apply(f.map,f.map,f.rows[2],away,away,f.meshes,f.bodies)
	check(f.cpus[2].uploads==0,"completing departure destroys pending source without an upload")
	f.map.free()
	f=fixture(1)
	Stream._apply(f.map,f.map,f.rows[0],away,away,f.meshes,f.bodies)
	check(f.cpus[1].uploads==1 and f.cpus[2].uploads==0,"mixed batch restores the still-demanded member and skips only the departing one")
	f.map.free()
	f=fixture();f.map.get_meta("stream_by_id").erase("part1")
	Stream._apply(f.map,f.map,f.rows[0],away,away,f.meshes,f.bodies)
	check(f.cpus[1].uploads==1,"unknown source ownership conservatively restores the member")
	f.map.free()
	f=fixture();f.rows[1].native_visual=true
	Stream._apply(f.map,f.map,f.rows[0],away,away,f.meshes,f.bodies)
	check(f.cpus[1].uploads==1,"native owner outside the draw ring still restores because streaming never destroys it")
	f.map.free()
	f=fixture();f.meshes.erase("part1")
	Stream._apply(f.map,f.map,f.rows[0],away,away,f.meshes,f.bodies)
	check(f.cpus[1].uploads==1,"a batch member outside this exact residency registry is never suspended")
	f.map.free()
	f=fixture();f.batch.retire_sources([f.nodes[0]])
	check(f.cpus[0].uploads==0 and f.cpus[1].uploads==1 and f.cpus[2].uploads==1,"ordinary explicit retirement still restores every surviving member")
	f.map.free()
	print("STREAM_BATCH_DEPARTURE checks=",checks," failures=",failures);quit(1 if failures else 0)
