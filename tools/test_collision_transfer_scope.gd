extends "res://tools/test_deferred_collision_publication.gd"
## CPU-only transaction scope and recovery gates. Real Deferred owns tickets;
## the source adapter is a test double, while ordinary physics stamps are real.
const Stream=preload("res://scripts/world3d/world_stream.gd")
class QuietWorld extends "res://scripts/world3d/world_3d.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
class Player extends CharacterBody3D:
	var input_locked:=false
class Cover extends CanvasLayer:
	var message:=""
	func update_progress(value:String)->void:message=value

func setup()->Dictionary:
	var world:=QuietWorld.new();root.add_child(world)
	var map:=Node3D.new();world.add_child(map);world._map_root=map
	map.set_meta("collision_first_loading",true);map.set_meta("stream_chunk",Vector2i.ZERO)
	map.set_meta("stream_collision_index",{});map.set_meta("stream_bodies",{})
	map.set_meta("stream_append_pending",[]);map.set_meta("extras",{"rmmo_records":[]})
	var player:=Player.new();world.add_child(player);world._player=player
	var rows:Array=[]
	for at:int in 2:
		var row:=item("source" if at==0 else "destination","model%d.glb"%at,at*300.)
		row.native_reference=false
		row.reference_entry={"record_index":at,"asset_path":row.path,"compact_record":{"uuid":row.record.uuid,"rmmo_ref":{"sha256":str(at).repeat(64)}}}
		rows.append(row)
	var queue:=Deferred.new();queue.pending=rows;map.add_child(queue);queue.activate(world)
	queue._admission.worker_limit=0;queue._active=false;queue.set_process(false)
	var loader:=CollisionLoader.new();map.add_child(loader)
	for row:Dictionary in rows:loader.states[row.record.uuid]=row.reference_entry.duplicate(true)
	var source:=AABB(Vector3(-2,-100000,-2),Vector3(4,200000,4))
	var target:=AABB(Vector3(298,-100000,-2),Vector3(4,200000,4))
	queue.ensure_collision(source,"player_collision");queue.ensure_collision(source,"manual_traversal")
	queue.set_demand_scope(["old_nav","player_collision","manual_traversal"])
	var context:Dictionary={"map":map,"deferred":queue,"original":{},"origin_id":"origin","target_id":"target","demand_id":"transfer:1","committed":false}
	return {"world":world,"map":map,"player":player,"queue":queue,"loader":loader,"source":source,"target":target,"context":context,"rows":rows}

func start_target(f:Dictionary)->void:
	f.world._begin_local_transfer_scope(f.context)
	f.queue.ensure_collision(f.target,f.context.demand_id)

func held(history:Array,id:String)->bool:
	for keys:Array in history:
		if not keys.has(id):return false
	return true

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old:=Deferred.collision_first_enabled;Deferred.collision_first_enabled=true
	success_scope();await failure_readiness();terminal_failure();default_scope()
	Deferred.collision_first_enabled=old
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_TRANSFER_SCOPE passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)

func success_scope()->void:
	var f:=setup();f.loader.history.clear();start_target(f)
	check(f.queue.get_demand_scope()==["transfer:1"],"target dispatch remains exclusive while origin collision tickets are retained")
	check(f.loader.tickets.has("player_collision") and f.loader.tickets.has("manual_traversal") and held(f.loader.history,"player_collision"),"starting target preparation never releases the existing player/camera lease")
	check(f.context.original.collision_tickets==["player_collision","manual_traversal"],"transaction records only the pre-existing source movement leases")
	# Exercise a restricted saved scope that no longer includes player itself.
	f.context.original.deferred_scope=["old_nav"]
	f.player.global_position=Vector3(300,.9,0);f.context.committed=true
	f.loader.history.clear();f.world._release_local_transfer_sources(f.context)
	check(f.queue.get_demand_scope()==["old_nav","player_collision"],"restricted prior scope explicitly permits the replacement player lease")
	check(f.loader.tickets.keys()==["player_collision"] and f.loader.tickets.player_collision==[f.rows[1].reference_entry],"successful handoff releases the stale origin sweep and target transaction after player owns destination")
	check(f.loader.history.size()==3 and f.loader.history[0].has("transfer:1") and f.loader.history[0].has("player_collision") and f.loader.history[1].has("transfer:1"),"destination transaction survives both scope restoration and replacement acquisition")
	f.world.free()

func failure_readiness()->void:
	var f:=setup();start_target(f)
	f.queue.release_demand(f.context.demand_id)
	f.context.original.deferred_scope=["old_nav"]
	f.loader.history.clear();f.world._restore_local_transfer_demand_scope(f.context)
	check(f.queue.get_demand_scope()==["old_nav","player_collision"] and f.loader.tickets.has("manual_traversal") and held(f.loader.history,"player_collision"),"cancel restoration keeps source tickets and admits exact recovery queries before dropping cover")
	f.loader.states.erase("source")
	check(f.world._transfer_residency_ready(Vector3.ZERO) and not f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"ordinary Stream empty-index readiness cannot bypass missing collision-only dependency proof")
	f.loader.states.source=f.rows[0].reference_entry.duplicate(true)
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,.5,2)
	var body:=StaticBody3D.new();f.map.add_child(body)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=mesh.size;shape.shape=box;body.add_child(shape)
	var spec:Dictionary={"uuid":"ordinary_floor","mesh":mesh,"transform":Transform3D.IDENTITY,"extras":{"rmmo_collision":"walk"}}
	f.map.set_meta("stream_collision_index",{Vector2i.ZERO:[spec]});f.map.set_meta("stream_bodies",{"ordinary_floor":body})
	body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	check(not f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"same physics tick ordinary-body publication keeps recovery blocked")
	await physics_frame;await process_frame
	check(f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"recovery accepts verified collision dependencies only after real physics synchronization")
	body.collision_layer=0
	check(not f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"removed collision layer invalidates recovery immediately")
	body.collision_layer=1;f.queue.instance_errors.source="source changed"
	check(not f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"source failure prevents recovery despite live ordinary bodies")
	f.queue.instance_errors.clear();f.map.set_meta("stream_chunk",Vector2i(9,0))
	check(not f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"original stream residency requirement remains mandatory")
	var other:=Node3D.new();f.world.add_child(other);f.context.map=other
	check(not f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"obsolete map context cannot authorize recovery")
	f.world.free()

func terminal_failure()->void:
	var f:=setup();start_target(f)
	var cover:=Cover.new();f.world.add_child(cover);f.context.cover=cover
	f.player.set_physics_process(true);f.player.velocity=Vector3.ONE
	var owners:Dictionary=f.loader.tickets.duplicate(true)
	check(not f.world._hold_local_transfer_recovery(f.context,"source unavailable"),"unrecoverable source has a bounded failed terminal result")
	check(f.player.input_locked and not f.player.is_physics_processing() and f.player.velocity==Vector3.ZERO,"failed recovery never reenables player physics or input")
	check(cover.visible and cover.message=="source unavailable" and cover.get_child_count()==1 and f.loader.tickets==owners,"failure retains cover and source ownership with an explicit return action")
	check(f.world.get_meta("transfer_loading_profile").recovery_failed and f.context.recovery_failed,"failure diagnostics distinguish failed recovery from an activated destination")
	f.world.free()

func default_scope()->void:
	var f:=setup();f.map.set_meta("collision_first_loading",false)
	f.world._begin_local_transfer_scope(f.context)
	check(f.context.original.collision_tickets.is_empty(),"default nonexperimental loading creates no additional collision retention")
	f.world._restore_local_transfer_demand_scope(f.context)
	check(f.queue.get_demand_scope()==f.context.original.deferred_scope and f.world._local_transfer_origin_ready(f.context,Vector3.ZERO),"default scope and ordinary readiness behavior are unchanged")
	f.world.free()
