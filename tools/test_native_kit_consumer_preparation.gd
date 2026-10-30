extends "res://tools/test_playtest_native_templates_cpu.gd"
## Real native readers and model queue; split upload remains the explicit CPU
## protocol stub. Actual GPU rendering/registration requires separate evidence.
const Dependencies=preload("res://scripts/world3d/record_asset_dependencies.gd")
const Kits=preload("res://scripts/world3d/auto_tile_kit.gd")
const LoadJob=preload("res://scripts/world_editor/load_job.gd")
const PrefabLibrary=preload("res://scripts/world_editor/prefab_library.gd")
var kit_observations:Array=[]

class KitDocument extends ProbeDocument:
	func build(effects:bool=true,templates:Dictionary={})->Node3D:
		var scene:Node3D=super.build(effects,templates)
		var visual:MeshInstance3D=scene.get_node_or_null(NodePath(asset_uuid))
		builds[-1].tile_error=visual.get_meta("tile_error","") if visual!=null else "missing"
		builds[-1].mesh_class=visual.mesh.get_class() if visual!=null and visual.mesh!=null else ""
		builds[-1].owner_ids=visual.mesh.get_meta("_compiled_resource_owners",[]).map(func(owner:PackedScene):return str(owner.get_instance_id())) if visual!=null and visual.mesh!=null else []
		return scene

class CountSession extends ProbeSession:
	var preparation_checks:=0
	func _preparation_current()->bool:
		preparation_checks+=1
		return super._preparation_current()

class BrokenFinalDocument extends KitDocument:
	func build(effects:bool=true,templates:Dictionary={})->Node3D:
		if builds.size()==1:records[-1].tile3d.options.kit.name=""
		return super.build(effects,templates)

func kit_document(first:String,second:String="")->KitDocument:
	var document:=KitDocument.new();document.add_box("ground",Vector3(0,-.1,0),Vector3(20,.2,20))
	document.asset_uuid=document.add_box("kit",Vector3(4,0,0),Vector3.ONE)
	document.records[-1].collision="none"
	var family:="stairs" if second.is_empty() else "cliff"
	var pieces:Dictionary={"default":first} if second.is_empty() else {"top":first,"edge":second}
	var options:Dictionary={"rise":1.0,"direction":0} if second.is_empty() else {}
	options.kit={"version":1,"family":family,"name":"native CPU kit","pieces":pieces}
	document.records[-1].tile3d={"version":1,"family":family,"cell":[4,0],"cell_size":1.0,"elevation":0.0,"mask":0,"neighbors":[],"attached":true,"options":options,"drops":[1,0,0,0]}
	return document

func load_job_case()->Array:
	var first:=fixture("load_kit_top",true);var second:=fixture("load_kit_edge",true)
	delete_authoring_source(first);delete_authoring_source(second)
	var document:=kit_document(first.path,second.path)
	var duplicate:Dictionary=document.records[-1].duplicate(true);duplicate.uuid="duplicate_kit";document.records.append(duplicate)
	var ordinary:=document.add_asset({"asset_path":first.path},Vector3(6,0,0));document.records[-1].collision="none"
	var editor:=TestEditor.new();editor._doc=document;root.add_child(editor)
	var job:=LoadJob.new();job.editor=editor;editor.add_child(job)
	job._timings.build={"units":{}}
	var pool:=ControlledPool.new();job.native_texture_pool=pool;job.native_texture_preparer=pixels
	job._begin_asset_lookahead(document.records)
	check(job._asset_paths.size()==2,"LoadJob deduplicates kit pieces and ordinary asset into two native requests")
	var published:Array[Node]=[];var owners:Array=[];var first_mesh:Mesh
	for record:Dictionary in document.records:
		var prepared:Dictionary=await job._prepare_asset(record)
		check(not prepared.get("cancelled",false) and not prepared.has("error"),"record dependencies finish before native construction")
		var visual:Node3D=document._asset(record,prepared) if record.kind=="asset" else job._prepared_mesh(document,record)
		if record.has("tile3d"):
			check(not prepared.has("scene") and not visual.has_meta("tile_error"),"kit publishes from READY templates without an extra initial scene")
			var retained:Array=visual.mesh.get_meta("_compiled_resource_owners",[])
			check(retained.size()==2,"each cliff retains precisely its top and edge native templates")
			for packed:PackedScene in retained:owners.append(weakref(packed));packed=null
			retained=[]
			if first_mesh==null:first_mesh=visual.mesh
			else:check(visual.mesh!=first_mesh and job._record_context.pieces.size()==2,"tile output meshes are distinct while source pieces are reused within operation")
		elif record.uuid==ordinary:check(not visual.has_meta("missing_asset"),"ordinary asset still instantiates after kit accepted the same template")
		published.append(visual)
		prepared.clear()
	check(job._timings.asset_lookahead.consumed==2,"actual queue consumes each native model exactly once")
	var loaded:Dictionary={"ok":true,"records":document.records.duplicate(true),"building_instances":{}}
	check(PrefabLibrary.preview_dependencies(loaded)==Dependencies.paths(document.records),"prefab UI shared entry requests actual kit pieces and ordinary asset once")
	var prefab:Node3D=PrefabLibrary.preview_prepared(loaded,job._record_context.templates)
	check(prefab!=null and prefab.get_node(NodePath(document.asset_uuid)).mesh is ArrayMesh,"prepared prefab constructs actual native kit geometry")
	if prefab!=null:prefab.free()
	var incomplete:Node3D=PrefabLibrary.preview_prepared(loaded,{first.path:job._record_context.templates[first.path]})
	check(incomplete==null,"prefab rejects a missing prepared kit piece instead of publishing a placeholder")
	if incomplete!=null:incomplete.free()
	var ledger:RefCounted=job._preparation.ledger
	kit_observations.append({"label":"load_job","planned":job._asset_paths.duplicate(),"timings":job._timings.asset_lookahead.duplicate(true)})
	job._clear_asset_lookahead()
	check(job._record_context==null,"LoadJob completion clears operation context")
	# Existing LoadJob policy publishes document templates to the normal cache.
	# Explicit eviction here models that existing cache owner's final release.
	Assets.evict_cached_scene(first.path);Assets.evict_cached_scene(second.path)
	check(owners.all(func(owner:WeakRef):return owner.get_ref()!=null),"published tiles retain source templates after operation/cache owner release")
	first_mesh=null
	for visual:Node in published:visual.free()
	published.clear();job.free();editor.free()
	await settle(ledger,pool)
	return owners

func playtest_case(two_pieces:bool,invalid:bool=false)->void:
	var first:=fixture("play_kit_top_"+str(two_pieces)+str(invalid),true);delete_authoring_source(first)
	var second:Dictionary={}
	if two_pieces:second=fixture("play_kit_edge",true);delete_authoring_source(second)
	var document:=kit_document(first.path,second.get("path",""))
	if invalid:document.records[-1].tile3d.options.kit.pieces.default=content_root.path_join("missing_piece.glb")
	var editor:=TestEditor.new();editor._doc=document;root.add_child(editor)
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var session:=CountSession.new();session.editor=editor;editor.add_child(session)
	var clone:=KitDocument.new();clone.apply_recovery(document.recovery_snapshot());clone.asset_uuid=document.asset_uuid
	var before:=document.recovery_snapshot()
	session.phase="preparing";session._generation=1;session.spawn=Vector3.ZERO;session.source_path=editor._path
	session._source_document=weakref(document);session._source_revision=document.authoring_revision
	await run_preparation(session,clone)
	if invalid:
		check(not session.entered and session.phase=="failed" and clone.builds.is_empty(),"missing kit product fails before any probe/runtime placeholder publication")
	else:
		check(session.entered and clone.builds.size()==2 and clone.builds.all(func(row:Dictionary):return row.tile_error.is_empty() and row.mesh_class=="ArrayMesh"),"playtest builds both actual native kit roots without GLB")
		check(clone.builds[0].owner_ids==clone.builds[1].owner_ids and clone.builds[0].owner_ids.size()==(2 if two_pieces else 1),"two fresh playtest roots share exactly the necessary model owners")
		check(service.profile.producers==(2 if two_pieces else 1) and session.preparation_checks==3,"one producer per piece and current checks only at build/physics/enter boundaries")
		check(session._asset_handles.is_empty() and session._asset_templates.is_empty(),"playtest hands model ownership to final tile meshes")
		var visual:MeshInstance3D=session.play_scene.get_node(NodePath(document.asset_uuid))
		var spec:Dictionary=Stream._spec(visual);session.play_scene.free();session.play_scene=null
		check(session.native_owners.all(func(reference:WeakRef):return reference.get_ref()!=null),"stream spec retains kit templates after scene and handle release")
		spec.clear()
	check(document.recovery_snapshot()==before and not Assets._scenes.has(first.path),"playtest preserves source records and does not populate global scene cache")
	kit_observations.append({"label":"playtest","two_pieces":two_pieces,"invalid":invalid,"builds":clone.builds.duplicate(true),"profile":service.profile.duplicate(),"preparation_checks":session.preparation_checks})
	var refs:Array=session.native_owners.duplicate();session.free();await quiet(service,pool)
	await retired(PublishedGeometry.for_tree(self),refs)
	check(refs.all(expired),"playtest final native graph owners retire")
	service.close();editor.free();await process_frame

func failure_boundary_case(final_build:bool,cancelled:bool=false)->void:
	var model:=fixture("kit_boundary_"+str(final_build)+str(cancelled),true);delete_authoring_source(model)
	var document:=kit_document(model.path)
	var editor:=TestEditor.new();editor._doc=document;root.add_child(editor)
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var session:=CountSession.new();session.editor=editor;editor.add_child(session)
	var clone:KitDocument=BrokenFinalDocument.new() if final_build else KitDocument.new()
	clone.apply_recovery(document.recovery_snapshot());clone.asset_uuid=document.asset_uuid
	if not final_build and not cancelled:clone.records[-1].tile3d.options.kit.name=""
	var before:=document.recovery_snapshot()
	session.phase="preparing";session._generation=1;session.spawn=Vector3.ZERO;session.source_path=editor._path
	session._source_document=weakref(document);session._source_revision=document.authoring_revision
	if cancelled:
		session._prepare(clone,{},1)
		check(session._asset_request>0,"kit cancellation has a real shared preparation request")
		session.stop()
		for i in 8:await process_frame
		check(not session.entered and clone.builds.is_empty() and session._asset_request==0,"cancelled kit preparation cannot construct or enter late")
	else:
		await run_preparation(session,clone)
		check(not session.entered and session.phase=="failed" and clone.builds.size()==(2 if final_build else 1),"both probe and final construction reject malformed kit placeholders")
		check(session._stage==null and session._asset_handles.is_empty(),"failed kit construction releases its probe and preparation owners")
	check(document.recovery_snapshot()==before and not Assets._scenes.has(model.path),"kit failure/cancellation preserves authoring data and global cache")
	kit_observations.append({"label":"boundary","final_build":final_build,"cancelled":cancelled,"builds":clone.builds.duplicate(true),"error":session.last_error})
	session.free();await quiet(service,pool)
	service.close();editor.free();await process_frame

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(80).timeout.connect(func():printerr("NATIVE_KIT_CONSUMER_CPU watchdog");quit(2))
	var owners:Array=await load_job_case()
	await retired(PublishedGeometry.for_tree(self),owners)
	check(owners.all(expired),"last tile/ordinary instance release retires every native template")
	await playtest_case(false);await playtest_case(true);await playtest_case(false,true)
	await failure_boundary_case(false);await failure_boundary_case(true);await failure_boundary_case(false,true)
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"cases":kit_observations,"scope":"CPU protocol stubs for texture upload; no GPU or MapLoader claim"},"\t"))
	print("NATIVE_KIT_CONSUMER_CPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
