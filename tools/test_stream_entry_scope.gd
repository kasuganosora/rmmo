extends SceneTree
## Temporary CPU/headless fixtures; no source maps, imports or GPU captures.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func box(id:String,at:Vector3,size:Vector3=Vector3.ONE,building:String="")->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=size
	var bounds:=AABB(at-size*.5,size)
	var spec:={"uuid":id,"position":at,"rotation":Vector3.ZERO,"transform":Transform3D(Basis.IDENTITY,at),"mesh":mesh,"collision_mesh":mesh,"extras":{},"chunk":Stream.chunk_key(at),"chunk_min":Stream.chunk_key(bounds.position),"chunk_max":Stream.chunk_key(bounds.end)}
	if not building.is_empty():spec.ground_batch_record={"building":{"id":building}}
	return spec
func scene(specs:Array)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map);map.set_meta("stream_library",specs)
	var index:=Index.build(specs)
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_children",0)
	return {"host":host,"map":map}
func ids(specs:Array)->Array:
	var result:Array=[]
	for spec:Dictionary in specs:result.append(spec.uuid)
	result.sort();return result
func run()->void:
	var clip:=AABB(Vector3(0,-5,0),Vector3(10,10,10))
	var crossing:=box("crossing",Vector3(40,0,4),Vector3(64,2,2))
	var core:=box("core",Vector3(4,0,4))
	var same_cell:=box("same_cell_outside",Vector3(20,0,20))
	var near_part:=box("near_part",Vector3(8,0,8),Vector3.ONE,"wide_house")
	var far_part:=box("far_part",Vector3(70,0,8),Vector3.ONE,"wide_house")
	var far_building:=box("far_building",Vector3(450,0,4),Vector3.ONE,"far_house")
	var far_land:=box("far_land",Vector3(500,0,4),Vector3(8,1,8))
	far_land.ground_batch_record={"kind":"box","surface_id":"ground","size":[8,1,8]}
	var world:=scene([core,same_cell,crossing,near_part,far_part,far_building,far_land,box("touching",Vector3(10.5,0,4))])
	check(Stream.set_entry_scope(world.map,clip),"finite horizontal scope is accepted")
	check(not Stream.entry_scope_ready(world.map),"scope is not ready before first stream synchronization")
	var revision:int=world.map.get_meta("stream_source_revision")
	check(Stream.set_entry_scope(world.map,clip) and world.map.get_meta("stream_source_revision")==revision,"same scope is idempotent")
	check(not Stream.set_entry_scope(world.map,AABB(Vector3.ZERO,Vector3(-1,1,1))) and world.map.get_meta("entry_stream_clip")==clip,"invalid scope fails without mutation")
	check(not Stream.set_entry_scope(world.map,AABB(Vector3(INF,0,0),Vector3.ONE)),"nonfinite scope fails")
	var area:Dictionary=Stream._source_ring(world.map,Vector2i(40,40),Stream.COLLISION_RADIUS)
	check(area.entry_clip==clip and area.low==Vector2i.ZERO and area.high==Vector2i.ZERO,"scope replaces player radius even if player target differs")
	var wanted:Array=["core","crossing","near_part","touching"]
	check(ids(Stream._candidates(world.map,Vector2i.ZERO,{},{}))==wanted,"only true overlapping specs are selected, including outside centers and boundary contacts")
	check(not Stream._draws(far_building,area) and not Stream._draws(far_part,area) and not Stream._draws(far_land,area),"kilometre building/support ranges cannot expand entry")
	check(Stream._draws(crossing,area) and Stream._overlaps(crossing,area),"cross-boundary visual and collision remain required")
	var fixture:=same_cell.duplicate();fixture.extras={"fixture":{}}
	check(Stream._in_entry_scope(fixture,clip),"fixture uses conservative swept index bounds instead of its current mesh pose")
	var fallback:={"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ONE}
	check(Stream._in_entry_scope(fallback,clip),"older geometry-free index rows retain conservative chunk fallback")
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(ids(world.map.get_meta("stream_meshes").keys().map(func(id):return {"uuid":id}))==wanted,"actual stream publishes only scoped visuals")
	check(world.map.get_meta("stream_bodies").size()==wanted.size() and Stream.entry_scope_ready(world.map),"scoped real collision nodes satisfy entry gate")
	check(Stream.can_retire_specs(world.map,["same_cell_outside"]).error=="entry_scope","masked demand never allows retirement during entry")
	var batcher=world.map.get_node("GroundRenderBatches")
	batcher.pending.append("unrelated_pending_group")
	check(Stream.entry_scope_ready(world.map),"unrelated unfinished render batch is not an entry requirement")
	batcher.pending.clear()
	var visible:MeshInstance3D=world.map.get_meta("stream_meshes").core
	var original:Mesh=visible.mesh
	var cpu:=Cpu.new();cpu.bounds=AABB(-Vector3.ONE*.5,Vector3.ONE);visible.mesh=cpu
	check(not Stream.entry_scope_ready(world.map),"CPU-only source without its own published batch is not visually ready")
	var visual:=Node3D.new();batcher.add_child(visual)
	batcher._member_groups.core="own_batch";batcher.groups.own_batch={"members":[visible],"visual":visual}
	check(Stream.entry_scope_ready(world.map),"published batch for the required source satisfies visual readiness")
	batcher.groups.clear();batcher._member_groups.clear();visual.free();visible.mesh=original
	var body:Node=world.map.get_meta("stream_bodies").core
	world.map.get_meta("stream_bodies").erase("core")
	world.map.set_meta("fortification_collision_sources",{"core":core})
	check(not Stream.entry_scope_ready(world.map),"queued fortification source is not mistaken for an attached collision body")
	world.map.get_meta("stream_bodies").core=body;world.map.get_meta("fortification_collision_sources").clear()
	var appended:=Stream.append_specs(world.map,[box("late_core",Vector3(5,0,5)),box("late_far",Vector3(500,0,15))])
	check(appended.ok and not Stream.entry_scope_ready(world.map),"new required spec invalidates readiness immediately")
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(Stream.entry_scope_ready(world.map) and world.map.get_meta("stream_meshes").has("late_core") and not world.map.get_meta("stream_meshes").has("late_far"),"append prepares required source while remote addition stays dormant")
	var core_mesh:Node=world.map.get_meta("stream_meshes").core
	Stream.clear_entry_scope(world.map)
	check(not world.map.has_meta("entry_stream_clip") and world.map.get_meta("stream_source_revision")>revision,"clear requests a normal replan without requiring player motion")
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(world.map.get_meta("stream_meshes").has("far_building") and world.map.get_meta("stream_meshes").has("far_land") and world.map.get_meta("stream_meshes").has("far_part"),"clear restores kilometre building and landscape draws")
	check(world.map.get_meta("stream_bodies").has("same_cell_outside") and world.map.get_meta("stream_meshes").core==core_mesh and world.map.get_meta("stream_bodies").core==body,"normal collision radius returns without replacing required live objects")
	var clear_revision:int=world.map.get_meta("stream_source_revision")
	Stream.clear_entry_scope(world.map)
	check(world.map.get_meta("stream_source_revision")==clear_revision,"clearing inactive scope is idempotent")
	world.host.free()
	preserved_sources(clip)
	print("STREAM_ENTRY_SCOPE_FINISHED checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func preserved_sources(clip:AABB)->void:
	var world:=scene([box("origin",Vector3(2004,0,4)),box("target",Vector3(4,0,4)),box("unprepared_ticket",Vector3(4004,0,4))])
	Stream.sync(world.map,world.host,Vector3(2004,0,4))
	var mesh:Node=world.map.get_meta("stream_meshes").origin
	var body:Node=world.map.get_meta("stream_bodies").origin
	Stream.pin_source(world.map,"origin_ticket",Vector3(2004,0,4))
	Stream.pin_source(world.map,"future_ticket",Vector3(4004,0,4))
	var tickets:Dictionary=world.map.get_meta("stream_sources").duplicate()
	Stream.set_entry_scope(world.map,clip)
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(world.map.get_meta("stream_meshes").origin==mesh and world.map.get_meta("stream_bodies").origin==body,"scope preserves already attached distant source and collision identity")
	check(world.map.get_meta("stream_sources")==tickets and not world.map.get_meta("stream_bodies").has("unprepared_ticket"),"tickets remain intact without preparing unrelated remote demand")
	check(Stream.entry_scope_ready(world.map),"remote source demand does not delay prepared target")
	Stream.clear_entry_scope(world.map)
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(world.map.get_meta("stream_bodies").has("unprepared_ticket") and world.map.get_meta("stream_bodies").origin==body and world.map.get_meta("stream_sources")==tickets,"release restores all retained tickets and keeps existing collisions")
	world.host.free()
