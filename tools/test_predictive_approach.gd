extends SceneTree
const Approach=preload("res://scripts/world3d/approach_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class ModelStub extends Node3D:
	var action:="idle"
class NavigationStub extends Node:
	var version:=1
	var ready_for_queries:=true
class PlayerProbe extends "res://scripts/world3d/world_player.gd":
	var stick:=Vector2.ZERO
	func _ready()->void:set_physics_process(false)
	func _stick()->Vector2:return stick
	func _camera_yaw()->float:return 0.
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func covered(queue:Node,point:Vector3)->bool:
	return queue._demands.values().any(func(d):return d.clip.has_point(point))
func item(id:String,x:float,z:float)->Dictionary:
	return {"record":{"uuid":id},"path":"reference:"+id,"bounds":AABB(Vector3(x,0,z),Vector3.ONE),"native_reference":true}
func run()->void:
	var queue:=Deferred.new();var predictor:=Approach.new()
	queue.prioritize(Vector3.ZERO);queue.release_demand("player")
	predictor.update(queue,Vector3.ZERO,Vector3(4,0,0),PackedVector3Array(),1000)
	check(covered(queue,Vector3(160,0,0)) and covered(queue,Vector3(64,0,0)),"continuous lead covers both intervening cells and beyond the live ring")
	check(not covered(queue,Vector3(-96,0,0)),"forward prediction excludes the opposite direction")
	check(queue._demands.size()==1,"straight prediction uses one exact corridor instead of overlapping cell scans")
	var revision:int=queue._demand_revision
	predictor.update(queue,Vector3(.1,0,0),Vector3(4,0,0),PackedVector3Array(),1250)
	check(queue._demand_revision==revision,"sub-cell movement keeps demand membership stable")
	queue.pending=[item("far",175,0),item("near",150,0),item("side",0,180)]
	queue._index_pending();queue._refresh_demanded()
	check(queue._demanded.size()==2 and queue._demanded[0].record.uuid=="near","ordinary props are prefetched and ordered from player, not from far ticket centres")
	queue.set_demand("safety",AABB(Vector3(0,-1,179),Vector3(3,3,3)),-2);queue._refresh_demanded()
	check(queue._demanded[0].record.uuid=="side","urgent actual geometry stays ahead of speculation")
	queue.set_demand_scope(["safety"]);queue._refresh_demanded()
	check(queue._demanded.size()==1,"prediction cannot broaden a transfer or building-entry scope")
	queue.set_demand_scope([]);queue.release_demand("safety")
	predictor.update(queue,Vector3.ZERO,Vector3(-4,0,0),PackedVector3Array(),1500)
	check(covered(queue,Vector3(-160,0,0)) and not covered(queue,Vector3(160,0,0)),"reversal replaces stale forward requests immediately")
	predictor.update(queue,Vector3.ZERO,Vector3(0,0,4),PackedVector3Array(),1750)
	check(covered(queue,Vector3(0,0,160)) and not covered(queue,Vector3(-160,0,0)),"right-angle turn does not wait for velocity smoothing")
	predictor.update(queue,Vector3.ZERO,Vector3.ZERO,PackedVector3Array(),2000)
	check(predictor.profile.active,"short pauses retain useful prepared demand")
	predictor.update(queue,Vector3.ZERO,Vector3.ZERO,PackedVector3Array(),3250)
	check(queue._demands.is_empty(),"stationary prediction expires after its bounded hold")
	queue.profile.preparation_p90_seconds=100.
	var route:=PackedVector3Array([Vector3(128,0,0),Vector3(128,0,128)])
	predictor.update(queue,Vector3.ZERO,Vector3(12,0,0),route,3500)
	check(covered(queue,Vector3(128,0,112)) and not covered(queue,Vector3(0,0,128)),"known route follows the corner rather than the goal chord")
	check(queue._demands.size()==2,"corner coalescing keeps two exact legs without filling the bend")
	check(predictor.profile.distance_m==256. and queue._demands.size()<=Approach.MAX_TICKETS,"slow loading and fast travel cannot expand the distance or ticket cap")
	check(not covered(queue,Vector3(128,0,224)),"prediction ends at the known route destination")
	predictor.update(queue,Vector3(2048,0,0),Vector3(4,0,0),PackedVector3Array(),3750)
	check(predictor.profile.teleports==1 and not covered(queue,Vector3(128,0,0)),"teleport discards all old-position predictions")
	var other:=Deferred.new()
	predictor.update(other,Vector3.ZERO,Vector3(4,0,0),PackedVector3Array(),4000)
	check(queue._demands.is_empty() and not other._demands.is_empty(),"map replacement releases the previous queue's tickets")
	predictor.update(other,Vector3.INF,Vector3(4,0,0),PackedVector3Array(),4250)
	check(other._demands.is_empty(),"invalid positions release speculation without spawning work")
	# Actual job feedback must be bounded and count a shared job only once.
	for i:int in 40:
		other._jobs["sample"]={"dispatch_us":Time.get_ticks_usec()-2000000}
		other._note_preparation_latency([{"path":"sample"},{"path":"sample"}])
	other._jobs.clear()
	check(other._preparation_seconds.size()==32 and other.profile.preparation_latency_samples==40 and other.profile.preparation_p90_seconds>=2.,"latency feedback has 32 samples and no per-instance double counting")
	var started:=Time.get_ticks_usec()
	for i:int in 10000:
		predictor.update(other,Vector3(i*.1,0,0),Vector3(4,0,0),PackedVector3Array(),4500+i*250)
	var stress_us:=Time.get_ticks_usec()-started
	check(other._demands.size()<=Approach.MAX_TICKETS and other._jobs.is_empty() and other._admission.reserved_bytes==0,"ten thousand predictions do not accumulate tickets or bypass shared admission")
	Approach.enabled=false;predictor.update(other,Vector3.ZERO,Vector3(4,0,0));Approach.enabled=true
	check(other._demands.is_empty(),"disabling prediction releases all owned tickets")
	var player:=PlayerProbe.new();var model:=ModelStub.new();model.name="CharacterModel3D";player.add_child(model);root.add_child(player)
	player.stick=Vector2(1,0);player.velocity=Vector3.ZERO;player.geometry_blocked=true
	check(player.streaming_intent().velocity==Vector3.ZERO,"UI input lock suppresses speculation")
	check(player.streaming_intent(true).velocity.x>0 and player.velocity==Vector3.ZERO,"geometry wait retains desired keyboard movement without moving the body")
	player.stick=Vector2.ZERO;player.input_locked=false
	var navigation:=NavigationStub.new();player.add_child(navigation);player.navigation=navigation
	player._route_navigation_id=navigation.get_instance_id();player._route_version=navigation.version
	player.click_target=Vector3(128,0,0);player._route=PackedVector3Array([Vector3(128,0,128)])
	var intent:Dictionary=player.streaming_intent()
	check(intent.route==route and player._route.size()==1 and player.click_target==route[0],"known navigation route is copied without consuming movement waypoints")
	navigation.version+=1
	check(player.streaming_intent().route.is_empty(),"stale navigation route cannot predict an unapproved goal chord")
	navigation.version-=1;model.action="sit_ground"
	check(player.streaming_intent().velocity==Vector3.ZERO,"rest animation suppresses movement prediction")
	player.free()
	queue.free();other.free()
	print("PREDICTIVE_APPROACH ",JSON.stringify({"checks":checks,"failures":failures,"stress_10000_ms":stress_us/1000.,"profile":predictor.profile}));quit(1 if failures else 0)
