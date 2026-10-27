extends "res://tools/test_requeue_membership_delta.gd"
## Reproduces clean internal reads incorrectly forcing all-ticket invalidation.
## No timing assertions, no GPU, no changes to the real map or package.

func private_materialize_then_requeue()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var old_borrow:Array=q.pending;var old_contents:Array=old_borrow.duplicate()
	var retired:Dictionary=q._pending_by_record_id.outside_0
	retired.published=true;q._remove_published_demand([retired])
	check(q._pending_snapshot_dirty,"publication detaches the public Array before private materialization")
	check(q._demand_membership.has("road_render") and q._demand_membership.road_render.get("requeue_typed_full",false),"road ticket is eligible for existing typed-cache proof")
	var cached:Dictionary=q._demand_membership.road_render
	# Trusted internal use only: this is NOT the public pending getter.
	var private_array:Array=q._materialize_pending_snapshot()
	check(not q._pending_snapshot_dirty and is_same(private_array,q._pending_snapshot),"internal materialization installs the current clean Array")
	q._reference_index.groups={"building:source_0":{"bounds":q._pending_by_record_id.source_0.bounds}}
	check(not q.group_is_published("building:source_0"),"internal read sees a live pending building member")
	var before_revision:int=q._demand_revision
	var before_preserved:int=q.profile.get("requeue_memberships_preserved",0)
	var before_direct:int=q.profile.get("requeue_direct_pending_items",0)
	check(q.requeue_references([f.entries.outside_0])==1 and q._demand_revision==before_revision+1,"clean private requeue accepts one item and advances revision")
	check(q._demand_membership.has("road_render") and is_same(q._demand_membership.road_render,cached) and int(q.profile.get("requeue_memberships_preserved",0))>before_preserved,"unrelated clean private requeue preserves the proven typed membership")
	check(is_same(private_array,q._pending_snapshot) and private_array.back().record.uuid=="outside_0" and is_same(private_array.back(),q._pending_by_record_id.outside_0),"clean private requeue appends to the current Array and live owner index")
	check(int(q.profile.get("requeue_direct_pending_items",0))==before_direct,"clean private path never claims dirty-only skip-append")
	check(old_borrow==old_contents and is_same(old_borrow[0],old_contents[0]),"borrowed pre-publication Array remains unchanged")
	q._refresh_demanded();exact_full_scan_oracle(q,"clean private requeue")
	q.free();f.map.free()

func exposed_read_then_requeue(replace_owner:bool)->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var old:Dictionary=q._pending_by_record_id.outside_1;old.published=true;q._remove_published_demand([old])
	q._materialize_pending_snapshot() # trusted internal reader
	check(q._demand_membership.has("road_render") and q._demand_membership.road_render.get("requeue_typed_full",false),"public-borrow fixture starts with eligible typed membership")
	var exposed:Array=q.pending # public mutable borrow must revoke the proof
	var old_size:=exposed.size();var replaced:Dictionary={}
	if replace_owner:
		replaced=exposed[0].duplicate(true);exposed[0]=replaced # same UUID/count, different owner
	var before_direct:int=q.profile.get("requeue_direct_pending_items",0)
	check(q.requeue_references([f.entries.outside_1])==1,"exposed Array accepts the unrelated requeue")
	check(q._demand_membership.is_empty(),"public mutable borrow takes conservative membership fallback")
	check(exposed.size()==old_size+1 and exposed.back().record.uuid=="outside_1","borrower observes append to the same current Array")
	check(int(q.profile.get("requeue_direct_pending_items",0))==before_direct,"public mutable borrow does not use dirty skip-append")
	if replace_owner:check(is_same(exposed[0],replaced),"fallback does not replace or hide the caller's same-size owner edit")
	# The baseline does not detect arbitrary same-size edits to its private index.
	# This case asserts conservative fallback and Array behavior only; it does not
	# claim that pre-existing external edits are repaired by unrelated requeue.
	q.free();f.map.free()

func setter_alias_then_requeue()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	# Public setter may install an Array still owned by its caller. Size equality
	# with the private UUID index does not make that alias a private snapshot.
	var external:Array=q._pending_snapshot
	q.pending=external
	check(q._demand_membership.has("road_render") and q._demand_membership.road_render.get("requeue_typed_full",false),"setter-alias fixture starts with eligible typed membership")
	var old_size:=external.size()
	var entry:Dictionary={"compact_record":{"uuid":"fresh_private_test"},"record_index":5000,"bounds":AABB(Vector3(30000,0,0),Vector3.ONE),"asset_path":"","group_id":"","reason":"native_road"}
	var before_direct:int=q.profile.get("requeue_direct_pending_items",0)
	check(q.requeue_references([entry])==1,"public setter alias accepts a new unrelated owner")
	check(q._demand_membership.is_empty(),"public setter alias never grants private membership preservation")
	check(external.size()==old_size+1 and external.back().record.uuid=="fresh_private_test","setter caller observes the normal append in its Array")
	check(int(q.profile.get("requeue_direct_pending_items",0))==before_direct,"setter alias does not use dirty skip-append")
	q.free();f.map.free()

func observation_without_borrow()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var old:Dictionary=q._pending_by_record_id.outside_2;old.published=true;q._remove_published_demand([old])
	var expected:int=q._pending_by_record_id.values().filter(func(row):return q._demanded_by_id.has(row.record.uuid)).size()
	var materializations:int=q.profile.get("pending_snapshot_materializations",0)
	check(q.pending_demanded_count()==expected and q._pending_snapshot_dirty,"scalar observation counts demanded pending rows without materializing")
	check(int(q.profile.get("pending_snapshot_materializations",0))==materializations,"scalar observation creates no pending snapshot")
	q._materialize_pending_snapshot()
	check(q.pending_demanded_count()==expected and q._pending_snapshot_private,"scalar observation retains internal ownership of a clean snapshot")
	var exposed:Array=q.pending
	check(not q._pending_snapshot_private,"public getter revokes private Array ownership")
	exposed[0]={"record":{"uuid":"not_demanded"}}
	check(q.pending_demanded_count()==exposed.filter(func(row):return q._demanded_by_id.has(row.record.uuid)).size(),"same-count public replacement uses actual Array observer semantics")
	exposed.append(exposed[1])
	check(q.pending_demanded_count()==exposed.filter(func(row):return q._demanded_by_id.has(row.record.uuid)).size(),"duplicate public UUID counts twice as the former filter did")
	q.free();f.map.free()

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	private_materialize_then_requeue();exposed_read_then_requeue(false);exposed_read_then_requeue(true);setter_alias_then_requeue();observation_without_borrow()
	# Retain the existing live registration/support, scope/group, collision,
	# errors, token/byte lease, alias and nonincremental fallback contracts.
	_registration_case();_support_requeue_case();_scope_and_group_cases();_ownership_and_retry_case();_alias_and_current_position_cases();_fallback_case()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	print("CLEAN_PRIVATE_MEMBERSHIP ",JSON.stringify({"passed":passed,"failures":failed,"errors":logger.errors}))
	quit(1 if failed else 0)
