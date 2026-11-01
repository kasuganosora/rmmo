extends SceneTree
## Real residency preparation/admission with one full oracle. Plain runs
## explicitly skip uninstrumented loop-work assertions. --require-work-ledger
## requires the external counted overlay; missing counts never mean zero work.
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class ObservedBatch extends "res://scripts/world3d/ground_batcher.gd":
	var observed_drops:=0
	var observed_admissions:=0
	func _drop(group:Dictionary,restore_sources:bool=true,retiring:Dictionary={},suspended:Dictionary={})->void:
		observed_drops+=1
		super._drop(group,restore_sources,retiring,suspended)
	func _admit_group(key:String,group:Dictionary,state:Dictionary,copy_raw:bool=false)->void:
		var existed:=groups.has(key)
		super._admit_group(key,group,state,copy_raw)
		if not existed and groups.has(key):observed_admissions+=1

var failures:Array=[]
var skipped_work:Array=[]
var checks:=0
var cases:Array=[]
var output:=""
var require_work_ledger:=false
var ledger_checked:=false
var work_ledger_available:=false

func _initialize()->void:run.call_deferred()

func check(ok:bool,label_:String,kind:String="correctness")->void:
	checks+=1
	print("PASS " if ok else "FAIL ",kind," ",label_)
	if not ok:failures.append({"kind":kind,"label":label_})

func mesh(material:Material,vertices:int=3,variation:float=0.5)->Mesh:
	var result:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var points:=PackedVector3Array();points.resize(vertices)
	points[0]=Vector3.ZERO;points[1]=Vector3.RIGHT*variation;points[2]=Vector3.FORWARD
	arrays[Mesh.ARRAY_VERTEX]=points;result.surfaces=[arrays]
	result.materials=[material];result.bounds=AABB(Vector3.ZERO,Vector3.ONE)
	return result

func source(parent:Node3D,geometry:Mesh,id:String,position_:Vector3,fort:bool=false)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=id;node.mesh=geometry;node.position=position_
	var record:={"uuid":id,"kind":"box","surface_id":"ground","size":[1,1,1]}
	if fort:record.fortification={}
	node.set_meta("ground_batch_record",record);parent.add_child(node);return node

func fixture(cells:int=64)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var batch:=ObservedBatch.new();host.add_child(batch);batch.set_process(false)
	if not ledger_checked:
		work_ledger_available=batch.get("finalization_probe") is Dictionary
		ledger_checked=true
		if require_work_ledger:check(work_ledger_available,"strict mode requires an actual work ledger","fixture")
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false)
	var material:=StandardMaterial3D.new();var geometry:=mesh(material)
	var f:={"host":host,"batch":batch,"oracle":oracle,"material":material,"mesh":geometry,"roots":[],"nodes":[]}
	for cell:int in cells:
		var imported:=Node3D.new();imported.name="root_%02d"%cell;host.add_child(imported)
		var parts:Array=[]
		for part:int in 4:
			var node:=source(imported,geometry,"m_%02d_%02d"%[cell,part],Vector3(cell*512+part*.1,0,0))
			parts.append(node);f.nodes.append(node)
		imported.set_meta("model_component_batch_sources",parts);f.roots.append(imported)
	return f

func add(f:Dictionary,id:String,cell:int,geometry:Mesh=null,fort:bool=false)->MeshInstance3D:
	var node:=source(f.host,f.mesh if geometry==null else geometry,id,Vector3(cell*512+.5,0,0),fort)
	f.roots.append(node);f.nodes.append(node);return node

func drain(batch:Node)->void:
	var turns:=0
	while not batch._preparation.is_empty() and turns<10000:batch._prepare_step(0);turns+=1
	check(batch._preparation.is_empty() and batch._next_residency.is_empty(),"same requested snapshot completes")

func request(f:Dictionary,draw:bool=false,excluded:Array=[])->void:
	f.batch.request_residency_sync(f.roots,excluded,true);drain(f.batch)
	if draw:f.batch.flush()

func snapshot(batch:Node)->Dictionary:
	var rows:Dictionary={}
	for key:String in batch.groups:
		var group:Dictionary=batch.groups[key];var names:Array=[]
		for node:Node in group.members:names.append(str(node.name))
		rows[key]={"members":names,"vertices":group.vertices,"keys":group.keys,"signature":group.signature,"origin":group.origin,"category":group.category,"merge_base":group.merge_base}
	return rows

func compare(f:Dictionary,label_:String,excluded:Array=[])->void:
	# Explicit sync clears descriptors: a full oracle must not reuse the same
	# stale metadata/geometry cache whose invalidation is being tested.
	f.oracle.clear(false);f.oracle.sync(f.roots,excluded);drain(f.oracle)
	check(snapshot(f.batch)==snapshot(f.oracle),label_+": exact ordered members/signatures/material keys/origins/capacity match full sync")
	var safe:=true
	for group:Dictionary in f.batch._residency_bins.get("desired",{}).values():
		for field:String in ["generation","visual","exit_callback","visible_callback","pose_watcher","cpu","data"]:
			safe=safe and not group.has(field)
	check(safe,label_+": reusable raw membership has no live group/render owner fields")

func owners(batch:Node)->Dictionary:
	var result:Dictionary={}
	for key:String in batch.groups:
		var group:Dictionary=batch.groups[key];var visual:Variant=group.get("visual")
		result[key]={"generation":group.generation,"visual":visual.get_instance_id() if is_instance_valid(visual) else 0}
	return result

func preserve(f:Dictionary,before:Dictionary,changed:Array,label_:String)->void:
	var after:=owners(f.batch);var identical:=true;var actual_draws:=0
	for key:String in before:
		if key in changed:continue
		identical=identical and after.get(key)==before[key]
		if before[key].visual!=0:actual_draws+=1
	check(identical,label_+": unrelated group generations and actual renderer Node owners survive")
	check(actual_draws>0,label_+": preservation exercises real committed draws","fixture")

func sample(batch:Node)->Dictionary:
	# These observations count actual super calls even without diagnostics.
	# No preparation, eligibility, group owner or scheduler behavior is mocked.
	var result:={"actual_drops":batch.observed_drops,"admissions":batch.observed_admissions}
	var measured:Variant=batch.get("finalization_probe")
	if measured is Dictionary:
		for field:String in ["order_rows","order_copies","unique","filter","drop","add","audit_key_rows"]:
			if measured.has(field):result[field]=int(measured[field])
	return result

func delta(before:Dictionary,after:Dictionary)->Dictionary:
	var values:Dictionary={}
	for key:String in after:values[key]=int(after[key])-int(before.get(key,0))
	return values

func bounded_visits(actual:Dictionary,limit:Dictionary,label_:String)->void:
	for stage:String in limit:
		if not actual.has(stage):
			var reason:=label_+": "+stage+" work limit requires external loop instrumentation"
			print("SKIP work ",reason);skipped_work.append(reason)
			continue
		check(int(actual[stage])<=int(limit[stage]),label_+": actual "+stage+" visits "+str(actual[stage])+" <= "+str(limit[stage]),"work")

func finish(f:Dictionary)->void:
	f.batch.clear(false);f.oracle.clear(false);f.host.free()

func local_append()->void:
	var f:=fixture();request(f,true);compare(f,"64 initial independent cells")
	var old:=owners(f.batch);var key:String=f.batch._member_groups[str(f.nodes[0].name)]
	var before:Dictionary=sample(f.batch).duplicate();var syncs:int=f.batch.sync_count
	add(f,"z_existing_a",0);add(f,"z_existing_b",0);add(f,"z_new_a",80);add(f,"z_new_b",80)
	request(f,true);compare(f,"two changed bases append")
	var counts:=delta(before,sample(f.batch))
	preserve(f,old,[key],"local append")
	check(f.batch.sync_count==syncs+1,"fixed request cadence stays one checkpoint","work")
	check(counts.actual_drops==1 and counts.admissions==2,"one existing membership replaced and one new group admitted")
	bounded_visits(counts,{"order_rows":2,"order_copies":2,"unique":2,"filter":2,"drop":1,"add":2},"local append")
	cases.append({"case":"local_append_64_cells","counts":counts,"groups":f.batch.groups.size(),"request_count":f.batch.sync_count-syncs})
	finish(f)

func canonical_vertex_order()->void:
	var f:=fixture(4);request(f,true)
	for i:int in 4:add(f,"m_cap_%02d"%i,99,mesh(f.material,30000 if i%2==0 else 33000))
	request(f);compare(f,"initial vertex-capped base")
	var before:Dictionary=sample(f.batch).duplicate();var packed:int=f.batch.packed_source_visits
	add(f,"a_earlier_cap",99,mesh(f.material,18000));request(f)
	compare(f,"lexically earlier vertex-limited member")
	var counts:=delta(before,sample(f.batch))
	check(f.batch.packed_source_visits-packed==5,"canonical capacity change legitimately repacks its five-member base","work")
	bounded_visits(counts,{"order_rows":3,"order_copies":3,"unique":3,"filter":3,"drop":2,"add":2},"vertex cap")
	cases.append({"case":"earlier_vertex_cap","counts":counts,"packed_delta":f.batch.packed_source_visits-packed});finish(f)

func fortification_cohort()->void:
	var f:=fixture(0);var first:MeshInstance3D
	for i:int in 258:
		var node:=add(f,"m_fort_A_%03d"%i,0,mesh(f.material,3,.2+i*.001),true)
		if i==0:first=node
	for i:int in 12:add(f,"m_fort_B_%03d"%i,1,mesh(f.material,3,.3+i*.001),true)
	request(f,true);compare(f,"two singleton merge cohorts")
	var old:=owners(f.batch);var affected:Array=[]
	for key:String in f.batch.groups:
		if str(f.batch.groups[key].members[0].name).contains("fort_A"):affected.append(key)
	var before:Dictionary=sample(f.batch).duplicate()
	# One former singleton leaves the unique cohort; an earlier different raw
	# base enters it. The256-member canonical boundary must still be identical.
	add(f,"z_fort_A_repeat",0,first.mesh,true)
	add(f,"a_fort_A_earliest",0,mesh(f.material,3,.75),true)
	request(f,true);compare(f,"singleton-to-repeated and earlier cohort member")
	var counts:=delta(before,sample(f.batch))
	preserve(f,old,affected,"unaffected fortification cohort")
	bounded_visits(counts,{"order_rows":259,"order_copies":259,"unique":259,"filter":3,"drop":2,"add":3},"fortification cohort")
	cases.append({"case":"fortification_canonical_cohort","counts":counts,"groups":f.batch.groups.size()});finish(f)

func explicit_fallbacks()->void:
	var f:=fixture(4);request(f,true)
	var node:MeshInstance3D=f.nodes[0]
	for change:String in ["geometry","material","metadata","pose"]:
		match change:
			"geometry":node.mesh=mesh(f.material,6,.7)
			"material":
				var material:=StandardMaterial3D.new();material.albedo_color=Color(.3,.7,.4);node.material_override=material
			"metadata":node.get_meta("ground_batch_record").fortification={}
			"pose":node.position.x+=513
		f.batch.invalidate_source(node);request(f);compare(f,"explicit mutable "+change)
	request(f,false,[str(f.nodes[1].name)]);compare(f,"exclusion fallback",[str(f.nodes[1].name)])
	request(f);compare(f,"exclusion restoration")
	var removed:Node=f.nodes[2];f.batch.retire_sources([removed]);removed.free()
	request(f);compare(f,"announced nested retirement")
	f.batch.enabled=false;request(f);check(f.batch.groups.is_empty(),"enabled change removes all groups")
	f.batch.enabled=true;request(f);compare(f,"enabled restoration")
	cases.append({"case":"explicit_fallbacks","counts":sample(f.batch).duplicate()});finish(f)

func destruction_during_finalization()->void:
	var f:=fixture(8);request(f,true)
	add(f,"z_trigger_a",90);add(f,"z_trigger_b",90)
	f.batch.request_residency_sync(f.roots,[],true)
	var turns:=0
	while not f.batch._preparation.is_empty() and f.batch._preparation.phase!="unique" and turns<10000:
		f.batch._prepare_step(1);turns+=1
	check(not f.batch._preparation.is_empty() and f.batch._preparation.phase=="unique","pause at real finalization before an unrelated nested exit","fixture")
	add(f,"z_queued_a",92);add(f,"z_queued_b",92)
	f.batch.request_residency_sync(f.roots,[],true)
	check(not f.batch._next_residency.is_empty(),"newer request really waits behind active finalization","fixture")
	var removed:Node=f.nodes[0];var key:String=f.batch._member_groups[str(removed.name)]
	removed.free()
	check(not f.batch.groups.has(key),"unexpected deletion immediately revokes its real draw")
	drain(f.batch)
	check(f.batch._member_groups.has("z_queued_a") and f.batch._member_groups.has("z_queued_b"),"owner-loss fallback retains the latest queued snapshot")
	# Imported-root identities stay unchanged despite a dead nested component.
	# The next unrelated append must not revive a falsely immutable final plan.
	add(f,"z_next_a",91);add(f,"z_next_b",91);request(f)
	compare(f,"append after nested loss during finalization")
	cases.append({"case":"nested_loss_during_finalization","counts":sample(f.batch).duplicate()});finish(f)

func same_uuid_new_owner()->void:
	var f:=fixture(4);request(f,true);compare(f,"initial replacement fixture")
	var old:MeshInstance3D=f.nodes[0];var id:=str(old.name);var identity:=old.get_instance_id()
	var key:String=f.batch._member_groups[id];var previous:=owners(f.batch)
	f.batch.retire_sources([old]);old.free()
	var replacement:=add(f,id,0,mesh(f.material,6,.8))
	check(str(replacement.name)==id and replacement.get_instance_id()!=identity,"same UUID is a genuinely new source owner","fixture")
	request(f,true);compare(f,"same UUID replacement")
	var new_key:String=f.batch._member_groups[id]
	check(f.batch.groups[new_key].generation!=previous[key].generation,"new owner cannot reuse the former group generation")
	preserve(f,previous,[key],"replacement fallback preserves unrelated draws")
	cases.append({"case":"same_uuid_new_owner","counts":sample(f.batch).duplicate()});finish(f)

func reentrant_source_exit()->void:
	var f:=fixture(4);request(f,true)
	var affected:String=f.batch._member_groups[str(f.nodes[0].name)]
	var victim:MeshInstance3D=f.nodes[4]
	var visual:Node=f.batch.groups[affected].visual
	var receipt:={"fired":false,"invalid_mark_seen":false}
	# Actual Node.free emits this synchronously from inside the existing _drop.
	# The callback represents a scene observer; it does not override scheduling.
	visual.tree_exited.connect(func():
		receipt.fired=true
		victim.free()
		receipt.invalid_mark_seen=bool(f.batch._preparation.get("finalization_invalid",false))
	,CONNECT_ONE_SHOT)
	add(f,"z_reentrant_append",0)
	f.batch.request_residency_sync(f.roots,[],true)
	# Unlimited synchronous preparation is the existing flush/sync contract.
	# It also ensures the active slice reaches completion after the callback.
	drain(f.batch)
	check(receipt.fired and receipt.invalid_mark_seen,"real visual exit marks the active preparation invalid inside the same slice","fixture")
	f.batch.request_residency_sync(f.roots,[],true);drain(f.batch)
	compare(f,"same-prefix request after reentrant nested owner loss")
	cases.append({"case":"reentrant_source_exit","signal":receipt,"counts":sample(f.batch)})
	finish(f)

func run()->void:
	require_work_ledger="--require-work-ledger" in OS.get_cmdline_user_args()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):
		printerr("Requires isolated external output");quit(2);return
	if "--reentrant-only" in OS.get_cmdline_user_args():reentrant_source_exit()
	else:
		local_append();canonical_vertex_order();fortification_cohort();explicit_fallbacks();destruction_during_finalization();same_uuid_new_owner();reentrant_source_exit()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"skipped_work":skipped_work,"work_ledger_available":work_ledger_available,"strict_work_ledger":require_work_ledger,
		"scope":"real component finalization and headless renderer owners; no GPU frame timing or map total claim"}))
	quit(0 if failures.is_empty() else 1)
