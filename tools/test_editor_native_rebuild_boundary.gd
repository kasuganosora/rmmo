extends "res://tools/test_editor_native_sequential_requests.gd"
## Real editor rebuild and custom kit consumers. Native/table reads are real;
## split texture upload alone uses the existing explicit CPU protocol fixture.
const Kit=preload("res://scripts/world3d/auto_tile_kit.gd")

func private_view(document:RefCounted,path:String,reference:WeakRef)->Node3D:
	var packed:PackedScene=reference.get_ref()
	return document.build(true,{path:packed})

func install_cache(path:String,reference:WeakRef)->bool:
	var candidate:=Assets.native_candidate(path,content_root)
	return Assets.cache_packed(path,reference.get_ref(),candidate.source_sha,candidate)

func context_for(path:String,reference:WeakRef)->RefCounted:
	return preload("res://scripts/world3d/prepared_record_context.gd").new({path:reference.get_ref()})

func finished_build(editor:Node3D)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while editor._asset_operations.snapshot().pending>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._asset_operations.snapshot().pending==0,"private rebuild completes within the bounded test wait")

func observe_view(editor:Node3D,id:String)->Dictionary:
	var holder:Node=editor._view.get_node_or_null(NodePath(id))
	var model:Node=holder.get_child(0) if holder!=null and holder.get_child_count()>0 else null
	return {"missing":holder==null or holder.get_meta("missing_asset",false),"paint_error":holder.get_meta("paint_error","") if holder!=null else "no holder","ready":model!=null and Ready.scene_ready(model),"body_count":editor._bodies_by_uuid.get(id,[]).size()}

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(90).timeout.connect(func():printerr("REBUILD_BOUNDARY watchdog");quit(2))
	var model:=fixture("rebuild_boundary",true)
	check(not FileAccess.file_exists(model.path),"fixture has native products and no GLB source")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	var editor:Node3D=load("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=content_root.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false
	var service:Node=load(ServicePath).for_consumer(editor)
	var pool:=ControlledPool.new();configure(service,pool)
	var first:=await capture_scene(service,editor,editor,model.path)
	await quiet(service,pool)
	check(first.get("ok",false) and expired(first.handle),"real service completes and releases its request handle")
	var id:String=editor._doc.add_asset({"asset_path":model.path},Vector3.ZERO)
	editor._view.free();editor._view=private_view(editor._doc,model.path,first.packed);editor.add_child(editor._view)
	editor._add_bodies(editor._view)
	Drainer.dispose_scene(first.scene);first.scene=null;await quiet(service,pool)
	var before:=observe_view(editor,id)
	check(before.ready and not before.missing and not Assets._scenes.has(model.path),"actual editor view owns a private READY split model with no global cache")
	var authored:Array=editor._doc.records.duplicate(true)
	var view_before:int=editor._view.get_instance_id()
	var history_before:Array=[editor._doc._undo.size(),editor._doc._redo.size(),editor._doc._next,editor._dirty]
	Trace.start();var pending:Dictionary=editor._rebuild()
	check(pending.get("pending",false) and editor._view.get_instance_id()==view_before,"rebuild retains the old view while preparing READY dependencies")
	await finished_build(editor);var reads:=native_reads(Trace.stop())
	var after:=observe_view(editor,id)
	check(after.ready and not after.missing,"whole-view rebuild preserves the existing READY split model")
	check(reads==0,"whole-view rebuild reuses the existing allocation without reading raw geometry again")
	check(editor._doc.records==authored,"rebuild does not mutate authored records")
	check(history_before==[editor._doc._undo.size(),editor._doc._redo.size(),editor._doc._next,editor._dirty],"view-only rebuild preserves history, UUID allocation and dirty state")
	observations.append({"case":"actual_editor_rebuild","before":before,"after":after,"native_reads":reads,"service":service.snapshot()})
	# A concurrent authored change invalidates the in-flight view rebuild. The
	# presentation must converge onto the authored records afterwards instead of
	# keeping the pre-rebuild view indefinitely.
	var interrupted_view:int=editor._view.get_instance_id()
	var revision_before:int=editor._doc.authoring_revision
	var interrupted:Dictionary=editor._rebuild()
	check(interrupted.get("pending",false),"a model-bearing whole-view rebuild starts asynchronously")
	editor._doc.authoring_revision+=1
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if editor._view.get_instance_id()!=interrupted_view and editor._asset_operations.snapshot().pending==0:break
	var converged:=observe_view(editor,id)
	check(editor._view.get_instance_id()!=interrupted_view and converged.ready and not converged.missing,"interrupted view rebuild retries and keeps the READY model visible")
	check(editor._doc.authoring_revision!=revision_before,"interrupted rebuild never rewrites authored revision")
	observations.append({"case":"interrupted_rebuild","converged":converged,"view_changed":true,"pending":editor._asset_operations.snapshot().pending})
	var second:=await capture_scene(service,editor,editor,model.path);await quiet(service,pool)
	check(second.get("ok",false) and not Assets._scenes.has(model.path),"custom kit probe also starts with a live private READY allocation")
	var prepared:Mesh=Kit._piece_from_scene(second.scene)
	check(prepared!=null and prepared.get_surface_count()==1 and prepared.surface_get_material(0).albedo_texture!=null,"same prepared model has valid textured kit geometry")
	var context:RefCounted=context_for(model.path,second.packed)
	Trace.start();var cold:Mesh=Kit.piece_mesh(model.path,context);var kit_reads:=native_reads(Trace.stop())
	check(cold!=null,"custom kit resolves the same private READY split dependency")
	observations.append({"case":"custom_kit","private_piece_available":cold!=null,"native_reads":kit_reads,"prepared_piece_available":prepared!=null})
	check(install_cache(model.path,second.packed),"legacy global-cache control accepts the same READY allocation")
	var cached:Mesh=Kit.piece_mesh(model.path)
	check(cached!=null and cached.surface_get_material(0).albedo_texture==prepared.surface_get_material(0).albedo_texture,"global-cache control succeeds with identical texture ownership")
	prepared=null;cold=null;cached=null;context=null;Assets._scenes.clear()
	check(Kit._meshes.values().all(func(reference):return reference is WeakRef and reference.get_ref()==null),"kit index leaves no strong derived mesh owner without a manual cache clear")
	Drainer.dispose_scene(second.scene);second.scene=null
	var refs:Array=[first.packed,first.mesh,second.packed,second.mesh]
	var ledger:RefCounted=service.ledger
	service.close();editor.free();editor=null;session.world3d_editor_doc=null;session.world3d_editor_path=""
	await settle(ledger,pool);await retired(PublishedGeometry.for_tree(self),refs)
	check(refs.all(func(reference:WeakRef):return expired(reference)) and ledger.count()==0,"all native owners and temporary reservations retire")
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	print("REBUILD_BOUNDARY checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
