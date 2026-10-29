extends SceneTree
## CPU accounting/ownership protocol fixture. Native registration is separately
## verified by test_streamed_budget_handoff_gpu; these fake textures do no GPU IO.
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var checks:=0
var failures:=0

class FakeTexture extends Texture2D:
	var registered:=true
	func _get_width()->int:return 4
	func _get_height()->int:return 4

class ControlledPool extends Pool:
	var budget_enabled:=true
	var cancel_during_validation:=""
	func _streamed_handoff_enabled()->bool:return budget_enabled
	func _streamed_handoff_texture_valid(texture:Texture2D)->bool:
		if not cancel_during_validation.is_empty():cancel(cancel_during_validation)
		return texture is FakeTexture and texture.registered
	func _load_stream(_plan:Dictionary,_digest:String)->Texture2D:
		var texture:=FakeTexture.new();texture.registered=budget_enabled;return texture

class NativeGatePool extends Pool:
	func _streamed_handoff_enabled()->bool:return true
	func _load_stream(_plan:Dictionary,_digest:String)->Texture2D:return FakeTexture.new()

class Scope extends RefCounted:
	var calls:=0
	var watched:Array=[]
	var aliases:Array=[]
	var released_on_main:=false
	var released_after_aliases:=false
	func release_now()->void:
		calls+=1
		released_on_main=Thread.is_main_thread()
		released_after_aliases=watched.all(func(w:WeakRef):return w.get_ref()==null) and aliases.all(func(p:Dictionary):return p.is_empty())
		watched.clear();aliases.clear()

class FinishedWorker extends RefCounted:
	var packet:Dictionary={}
	func is_started()->bool:return true
	func wait_to_finish()->Dictionary:return packet

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func plan(count:int=2)->Dictionary:
	var rows:Dictionary={}
	for i:int in count:
		var key:="pixel_"+str(i)
		rows[key]={"path":key,"width":4,"height":4,"source_bytes":64,"output_bytes":64,"extension":"stex","product":key,"representation":"stex:"+key}
	return {"rows":rows,"output_bytes":64*count,"estimated_bytes":128*count+64}

func admit(pool:RefCounted,id:String,planned:Dictionary)->Dictionary:
	var offer:Dictionary=pool.offer(planned)
	check(pool.admission.reserve_bundle(id,{"estimated_bytes":64,"exclusive":false},offer.retained),"reserve "+id+" under one ledger")
	pool.commit(id,offer);pool.admission.park(id)
	return offer

func loaded(pool:RefCounted,id:String,planned:Dictionary)->void:
	for key:String in planned.rows:check(pool.load_stream(id,key,"immutable",planned.rows[key]),"produce "+key+" once")
	pool.admission.release(id)

func state(pool:RefCounted)->Dictionary:
	return {"reserved":pool.admission.reserved_bytes,"entries":pool.admission._entries.duplicate(true),"profile":pool.snapshot(),"rows":pool._entries.duplicate()}

func handoff(pool:RefCounted,id:String,owners:Dictionary)->bool:
	return pool.handoff_streamed(id,owners) if pool.has_method("handoff_streamed") else false

func accounting()->void:
	var pool:=ControlledPool.new();pool.admission=Admission.new();pool.admission.byte_limit=1024
	var planned:=plan();var first:=admit(pool,"first",planned);admit(pool,"follower",planned)
	loaded(pool,"first",planned);pool.admission.release("follower")
	var owners:Dictionary=pool.textures("first")
	check(pool.admission.reserved_bytes==256 and owners.size()==2,"completed outputs retain one complete conservative shared charge")
	check(not pool.admission.can_admit("exclusive",{"estimated_bytes":2048,"exclusive":true}),"completed native outputs reproduce exclusive-production blockage")
	var before:=state(pool)
	var missing:=owners.duplicate();missing.erase("pixel_1")
	check(not handoff(pool,"first",missing) and state(pool)==before,"missing second owner cannot partially hand off the first")
	var wrong:=owners.duplicate();wrong.pixel_1=FakeTexture.new()
	check(not handoff(pool,"first",wrong) and state(pool)==before,"different owner fails without reservation mutation")
	pool.budget_enabled=false
	check(not handoff(pool,"first",owners) and state(pool)==before,"disabled engine budget retains the complete original charge")
	pool.budget_enabled=true
	check(handoff(pool,"first",owners),"completed native owners transfer their temporary charge")
	check(pool.admission.reserved_bytes==0 and pool.admission.can_admit("exclusive",{"estimated_bytes":2048,"exclusive":true}),"completed native owners no longer block the next exclusive task")
	if pool.has_method("handoff_streamed"):
		check(pool.snapshot().retained_bytes==0 and pool.snapshot().handoff_full_chain_bytes==256 and pool.snapshot().handoff_outputs==2,"handoff reports conservative full-chain bytes separately from queue bytes")
		before=state(pool)
		check(handoff(pool,"first",owners) and handoff(pool,"follower",owners) and state(pool)==before,"duplicate and follower handoffs do not release twice")
		var later:=pool.offer(planned)
		check(later.retained.is_empty() and later.leaders.is_empty() and pool.textures("follower")==owners,"handoff preserves shared ready outputs for later consumers")
		var key:String=first.bindings.values()[0]
		check(pool.admission.reserve(key,{"estimated_bytes":17,"exclusive":false}),"a later independent reservation may reuse a released key")
		pool.admission.park(key)
		pool.release("first");pool.release("follower")
		check(pool.admission.reserved_bytes==17 and pool.admission._entries.has(key),"late pool retirement cannot release a later same-key reservation")
		pool.admission.release(key)
	else:
		pool.release("first");pool.release("follower")
	owners.clear();missing.clear();wrong.clear();before.clear()
	check(pool.admission.reserved_bytes==0 and pool.snapshot().outputs==0,"final shared retirement clears all entries")

func negatives()->void:
	if not Pool.new().has_method("handoff_streamed"):return
	var pool:=NativeGatePool.new();pool.admission=Admission.new();var planned:=plan(1)
	admit(pool,"fake",planned);loaded(pool,"fake",planned)
	var owners:Dictionary=pool.textures("fake");var before:=state(pool)
	check(not handoff(pool,"fake",owners) and state(pool)==before,"production native gate rejects a fake Texture2D")
	pool.release("fake");owners.clear();before.clear()
	var controlled:=ControlledPool.new();controlled.admission=Admission.new()
	admit(controlled,"pending",planned);before=state(controlled)
	check(not handoff(controlled,"pending",{}) and state(controlled)==before,"uncompleted production cannot transfer charge")
	loaded(controlled,"pending",planned);owners=controlled.textures("pending");controlled.cancel("pending");before=state(controlled)
	check(not handoff(controlled,"pending",owners) and state(controlled)==before,"cancelled consumer cannot hand off ready output")
	controlled.release("pending");owners.clear();before.clear()
	admit(controlled,"image",planned)
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	check(controlled.publish("image","pixel_0","immutable",image),"ordinary CPU image still publishes")
	before=state(controlled)
	check(not handoff(controlled,"image",{"pixel_0":FakeTexture.new()}) and state(controlled)==before,"ordinary CPU image remains fully charged")
	controlled.release("image");controlled.admission.release("image");image=null;before.clear()
	check(controlled.admission.reserved_bytes==0,"negative cases preserve ordinary final release")
	admit(controlled,"race",planned);loaded(controlled,"race",planned)
	owners=controlled.textures("race");var charged:int=controlled.admission.reserved_bytes
	controlled.cancel_during_validation="race"
	check(not handoff(controlled,"race",owners) and controlled.admission.reserved_bytes==charged and controlled.snapshot().handoff_outputs==0,"cancellation during unlocked native validation cannot partially transfer")
	owners.clear();controlled.release("race")
	var disabled:=ControlledPool.new();disabled.admission=Admission.new();disabled.budget_enabled=false
	admit(disabled,"unmanaged",planned);loaded(disabled,"unmanaged",planned);owners=disabled.textures("unmanaged");disabled.budget_enabled=true
	before=state(disabled)
	check(not handoff(disabled,"unmanaged",owners) and state(disabled)==before,"enabling budget after native creation cannot retroactively transfer an unmanaged output")
	owners.clear();disabled.release("unmanaged")

func drainer_edge()->void:
	var scope:=Scope.new();var borrowed:=Scope.new()
	var resource:=Resource.new();scope.watched.append(weakref(resource))
	var first:Dictionary={"packed":resource,"native_texture_scope":scope}
	var second:Dictionary={"retained_resources":[resource],"native_texture_scope":scope}
	var author:Dictionary={"native_texture_scope":borrowed,"keep":[1,2,3]}
	var packet:Dictionary={"native_texture_scope":scope,"retained_resources":[first,second],"records":[author]}
	scope.aliases=[packet,first,second];resource=null
	Drainer.dispose_result(packet)
	check(scope.calls==1 and scope.released_on_main,"drainer invokes each explicit scope once on main")
	check(scope.released_after_aliases and packet.is_empty() and first.is_empty() and second.is_empty(),"scope retirement follows every owned packet alias")
	check(borrowed.calls==0 and author.keep==[1,2,3],"borrowed author dictionaries cannot enroll a scope callback")
	var token:=Drainer.CancelToken.new();scope=Scope.new();resource=Resource.new();scope.watched=[weakref(resource)]
	packet={"native_texture_scope":scope,"retained_resources":[resource]};scope.aliases=[packet];resource=null
	token.set_meta("prefab_continuation_result",packet)
	Drainer.release_shared(token)
	check(scope.calls==1 and scope.released_after_aliases and not token.has_meta("prefab_continuation_result"),"cancelled continuation uses the same explicit disposal edge")
	scope=Scope.new();token=Drainer.CancelToken.new();resource=Resource.new();scope.watched=[weakref(resource)]
	packet={"native_texture_scope":scope,"retained_resources":[resource]};scope.aliases=[packet]
	token.set_meta("prefab_continuation_result",packet);token.set_meta("native_texture_scope",scope);token.set_meta("prefab_texture_tickets",{"owner":resource});resource=null
	Drainer.release_shared(token)
	check(scope.calls==1 and scope.released_after_aliases and not token.has_meta("native_texture_scope"),"token and continuation coalesce their scope after every metadata owner releases")
	scope=Scope.new();token=Drainer.CancelToken.new();token.set_meta("native_texture_scope",scope)
	Drainer.release_shared(token)
	check(scope.calls==1 and not token.has_meta("native_texture_scope"),"cancelled token releases its metadata-only native scope")
	scope=Scope.new();token=Drainer.CancelToken.new();resource=Resource.new();scope.watched=[weakref(resource)]
	packet={"native_texture_scope":scope,"retained_resources":[resource]};scope.aliases=[packet]
	var worker:=FinishedWorker.new();worker.packet=packet
	token.set_meta("native_texture_scope",scope);token.set_meta("prefab_texture_tickets",{"owner":resource});resource=null
	Drainer._dispose_result(worker,token)
	check(scope.calls==1 and scope.released_after_aliases,"joined worker result and token retire one shared scope after all aliases")

func handoff_subset(pool:RefCounted,consumer:String,owners:Dictionary,keys:Variant)->bool:
	for method:Dictionary in pool.get_method_list():
		if method.name=="handoff_streamed" and method.args.size()>=3:return bool(pool.call("handoff_streamed",consumer,owners,keys))
	return false

func mixed_outputs()->void:
	var pool:=ControlledPool.new();pool.admission=Admission.new();var planned:=plan()
	admit(pool,"mixed",planned)
	check(pool.load_stream("mixed","pixel_0","immutable",planned.rows.pixel_0),"mixed consumer prepares one native output")
	var pixels:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	check(pool.publish("mixed","pixel_1","immutable",pixels),"same consumer keeps one ordinary Image output")
	pool.admission.release("mixed");var owners:Dictionary=pool.textures("mixed");var before:=state(pool)
	check(not handoff(pool,"mixed",owners) and state(pool)==before,"default all-output transfer cannot discard an ordinary Image lease")
	check(not handoff_subset(pool,"mixed",owners,["pixel_0","unknown"]) and state(pool)==before,"foreign subset key causes no partial transfer")
	check(not handoff_subset(pool,"mixed",owners,["pixel_0","pixel_1"]) and state(pool)==before,"mixed invalid subset preserves every original charge")
	check(not handoff_subset(pool,"mixed",owners,[0]) and state(pool)==before,"non-string subset key is rejected without mutation")
	check(handoff_subset(pool,"mixed",owners,[]) and state(pool)==before,"explicit empty subset is a no-op")
	check(handoff_subset(pool,"mixed",owners,["pixel_0","pixel_0"]) and pool.admission.reserved_bytes==128 and pool.snapshot().retained_bytes==128 and pool.snapshot().handoff_outputs==1,"native subset transfers once while ordinary pixels keep their full lease")
	before=state(pool)
	check(handoff_subset(pool,"mixed",owners,PackedStringArray(["pixel_0"])) and state(pool)==before,"repeated native subset cannot release twice")
	owners.clear();before.clear();pixels=null;pool.release("mixed")
	check(pool.admission.reserved_bytes==0 and pool._entries.is_empty(),"mixed consumer final release retires remaining ordinary charge")

func run()->void:
	accounting();negatives();drainer_edge();mixed_outputs()
	print("STREAMED_BUDGET_HANDOFF checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
