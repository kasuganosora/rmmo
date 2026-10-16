extends SceneTree
## CPU-only generic building contract coverage; all author/source files temporary.
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Membership=preload("res://scripts/world3d/building_membership.gd")
const Authority=preload("res://scripts/world3d/local_entry_authority.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Format=preload("res://scripts/world3d/world_location.gd")
const ModelFixture=preload("res://tools/test_asset_bounds_manifest.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
var passed:=0
var failures:=0
var folder:=""
var content_root:=""
var created:Array[String]=[]
class Directory:
	extends Node
	var _reference_index:Dictionary={}
class RejectedLibrary:
	extends "res://scripts/world_editor/asset_library.gd"
	var save_calls:=0
	var proposed_entries:Array=[]
	func save()->Error:
		save_calls+=1;proposed_entries=entries.duplicate(true)
		return ERR_CANT_CREATE

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func map_file(records:Array,name_:String)->Dictionary:
	var path:=folder.path_join(name_+".gltf")
	var saved:Dictionary=Store.write_records(records,path,content_root)
	if not saved.ok:return saved
	var meta:Dictionary={"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_unit":"m","rmmo_records":saved.records,"rmmo_resource_dependencies":saved.dependencies}
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":meta}]}
	write(path,JSON.stringify(data).to_utf8_buffer());created.append(path);created.append(Index.cache_path(path,content_root))
	for uri:String in saved.dependencies:created.append(folder.path_join(uri))
	return {"ok":true,"path":path,"extras":meta}

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	content_root=Paths.external_root();folder=Paths.cache_directory("imported_membership_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var source_path:=folder.path_join("fixture.glb");created.append(source_path)
	var maker:=ModelFixture.new();var data:Dictionary=maker.data()
	# Exact native-style paths and source annotations; complete building is two
	# real mesh members, never a fabricated author record for each surface.
	data.nodes[0].name="Interior";data.nodes[0].children=[1,2]
	data.nodes[1].name="Floor";data.nodes.append({"name":"Door","mesh":0})
	var regions:Array=[{"id":"inside","floor":0,"min":[8.2,2.0,-1.8],"max":[11.8,6.0,1.8]}]
	var floor_part:Dictionary={"floor":0,"floor_y":2.0,"role":"floor","part":"floor"}
	var door_part:Dictionary={"floor":0,"floor_y":2.0,"role":"door","part":"door"}
	data.nodes[0].extras={"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":regions}}
	data.nodes[1].extras={"uuid":"floor_mesh","rmmo_part":floor_part}
	data.nodes[2].extras={"uuid":"door_mesh","rmmo_part":door_part,"rmmo_hinge":{"id":"entry","pivot":[0,0,0],"angle":90,"open":0.0}}
	maker.write(source_path,data);maker.free()
	var descriptor:Dictionary={"version":1,"regions":regions,"members":{"floor_mesh":floor_part,"door_mesh":door_part},"fixtures":{"entry":0.0},"source_sha":FileAccess.get_sha256(source_path)}
	var record:Dictionary={"uuid":"imported_house","kind":"asset","position":[100,4,50],"rotation":[0,35,0],"size":[2,1.5,.8],"asset_path":source_path,"model_building":descriptor,"model_building_states":{"entry":0.0}}
	var meta:Dictionary={"rmmo_records":[record]}
	var pose:=Transform3D(Basis.from_euler(Vector3(0,deg_to_rad(35),0)).scaled_local(Vector3(2,1.5,.8)),Vector3(100,4,50))
	check(Imported.valid_record(record) and Imported.frame(record).is_equal_approx(pose),"explicit import contract and rotated nonuniform local scale")
	var built:=Membership.build(meta)
	check(built.ok and built.buildings.size()==1,"single author asset registers one complete native building")
	if not built.ok:print(built);cleanup();quit(1);return
	var b:Dictionary=built.buildings.imported_house
	check(b.members==["imported_house__door_mesh","imported_house__floor_mesh"],"readiness names every exact stable source mesh UUID, not asset locator")
	var inside:Vector3=pose*Vector3(10,2.1,0)
	check(Membership.locate(built,inside).get("instance_id")==record.uuid,"rotated room interior grants its building identity")
	check(Membership.locate(built,pose*Vector3(10,2.1,2.1)).membership=="outdoor","exterior porch inside geometry envelope does not become room")
	check(Membership.locate(built,pose*Vector3(10,6.1,0)).membership=="outdoor","roof space above declared room is outdoors")
	check(Membership.sweep(built,AABB(inside-Vector3.ONE*.2,Vector3.ONE*.4)).buildings.has(record.uuid),"capsule sweep demands complete imported building")
	var changed:=record.duplicate(true);changed.model_building_states.entry=1.0
	var moved:=Membership.build({"rmmo_records":[changed]})
	check(moved.ok and moved.buildings.imported_house.structure_revision==b.structure_revision and moved.buildings.imported_house.fixtures.entry==1.0,"fixture state is ordered mutable state, not a different structural identity")
	changed=record.duplicate(true);changed.position[0]+=2
	moved=Membership.build({"rmmo_records":[changed]})
	check(moved.ok and moved.buildings.imported_house.pose_revision!=b.pose_revision and moved.buildings.imported_house.structure_revision==b.structure_revision,"moving a whole asset changes pose revision only")
	changed=record.duplicate(true);changed.size[0]+=1
	moved=Membership.build({"rmmo_records":[changed]})
	check(moved.ok and moved.buildings.imported_house.structure_revision!=b.structure_revision,"scale changes structural readiness revision")
	for mutation:String in ["sha","missing_source","foreign_state","invalid_amount","old_state","duplicate_source_identity","foreign_owner","no_door","invented_region","dropped_member"]:
		changed=record.duplicate(true)
		match mutation:
			"sha":changed.model_building.source_sha="0".repeat(64)
			"missing_source":changed.erase("asset_path")
			"foreign_state":changed.model_building_states.foreign=.5
			"invalid_amount":changed.model_building_states.entry=2.0
			"old_state":changed.model_component_states={"entry":0.0}
			"duplicate_source_identity":changed.model_building.members["bad/id"]=door_part
			"foreign_owner":changed.building={"id":"other","part":"x"}
			"no_door":changed.model_building.members["door_mesh"].role="body"
			"invented_region":changed.model_building.regions[0].max[0]+=40
			"dropped_member":changed.model_building.members.erase("door_mesh")
		var denied:=Membership.build({"rmmo_records":[changed]})
		check(not denied.ok or Membership.locate(denied,inside).membership=="unresolved","invalid or incomplete imported contract denied: "+mutation)
	var legacy:=record.duplicate(true);legacy.erase("model_building");legacy.erase("model_building_states")
	var unknown:=Membership.build({"rmmo_records":[legacy]},{legacy.uuid:pose*AABB(Vector3(8,2,-2),Vector3(4,4,4))})
	check(unknown.ok and Membership.locate(unknown,inside).membership=="unresolved","unannotated assets remain conservative unknown structures")
	var shadow:Dictionary={"uuid":b.members[0],"kind":"box","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	check(not Membership.build({"rmmo_records":[record,shadow]}).ok,"independent author record cannot steal a native mesh readiness identity")
	var authority:=Authority.new()
	check(authority.register_map("map","revision",meta).ok,"authority registers SHA-bound generic building")
	var issued:=authority.begin("session","world","map","revision",inside)
	check(issued.ok and issued.snapshot.membership=="indoor" and issued.required_members==b.members and issued.required_group=="building:imported_house","authority ticket includes exact imported dependency group and mesh set")
	check(not authority.update_fixture("map","revision",record.uuid,"foreign",1,0).ok,"authority cannot create a fixture absent from native descriptor")
	check(authority.update_fixture("map","revision",record.uuid,"entry",1,0).ok and not authority.update_fixture("map","revision",record.uuid,"entry",0,0).ok,"imported fixture updates use sequence conflict protection")
	var fixture:=map_file([record],"map")
	check(fixture.ok,"generic contract saves as normal single compact asset")
	if not fixture.ok:print(fixture);cleanup();quit(1);return
	var index:=Index.build(fixture.path,content_root,[record])
	check(index.ok,"dependency directory accepts actual source-bound generic contract")
	if not index.ok:print(index);cleanup();quit(1);return
	var invented:=record.duplicate(true);invented.model_building.regions[0].max[0]+=40
	var forged:=map_file([invented],"invented_room")
	check(forged.ok and not Index.build(forged.path,content_root,[invented]).ok,"same source SHA cannot certify an invented saved room descriptor")
	for mutation:String in ["sha","region"]:
		var duplicate:=record.duplicate(true);duplicate.uuid="second_house";duplicate.position[0]+=50
		if mutation=="sha":duplicate.model_building.source_sha="0".repeat(64)
		else:duplicate.model_building.regions[0].max[0]+=40
		var pair:Array=[record,duplicate]
		check(not Membership.build({"rmmo_records":pair}).ok,"shared source path does not bypass second-instance authority "+mutation+" check")
		var pair_map:=map_file(pair,"shared_path_"+mutation)
		check(pair_map.ok and not Index.build(pair_map.path,content_root,pair).ok,"shared path cache does not certify different second-instance "+mutation)
	check(index.rows.size()==1 and index.rows[0].group_id=="building:imported_house" and index.rows[0].classification=="group" and index.groups["building:imported_house"].members==[0],"directory groups original asset atomically without synthetic author records")
	var read:=Index.read(fixture.path,content_root)
	check(read.ok,"generic dependency group roundtrips on disk")
	var selected:=Index.select(read,[AABB(inside-Vector3.ONE,Vector3.ONE*2)])
	check(selected.ok and selected.record_indices==[0] and selected.selected_groups==["building:imported_house"],"room demand selects its entire original asset group")
	var hydrated:=Cursor.hydrate_references(selected.extras,fixture.path,content_root)
	var verified:=Index.validate_selected(read,hydrated.extras.rmmo_records)
	check(hydrated.ok and verified.ok and verified.validation_extras.building_instances.is_empty(),"selected imported group validates without inventing Blueprint registry")
	var damaged:Array=hydrated.extras.rmmo_records.duplicate(true);damaged[0].model_building.members.erase("door_mesh")
	check(not Index.validate_selected(read,damaged).ok,"selected subset cannot silently remove a native mesh member")
	var world:=Node3D.new();root.add_child(world)
	world.set_meta("author_reference_extras",read.extras);world.set_meta("runtime_record_subset",true)
	var directory:=Directory.new();directory.name="DeferredAssets";directory._reference_index=read;world.add_child(directory)
	check(authority.register_root("compact","revision",world).ok and authority.begin("compact_session","world","compact","revision",inside).snapshot.membership=="indoor","compact authority uses verified immutable source path and avoids unknown duplicate bounds")
	world.queue_free()
	var hydrated_world:=Node3D.new();root.add_child(hydrated_world)
	hydrated_world.set_meta("extras",meta)
	var member_specs:Array=[]
	for member:String in b.members:
		member_specs.append({"uuid":member,"mesh":BoxMesh.new(),"transform":pose,"extras":{"uuid":member,"kind":"asset","asset_path":source_path,"building":{"id":record.uuid}}})
	hydrated_world.set_meta("stream_library",member_specs)
	check(authority.register_root("hydrated","revision",hydrated_world).ok and authority.begin("hydrated_session","world","hydrated","revision",inside).snapshot.membership=="indoor","full hydrated root aggregates actual mesh bounds without making native rooms unknown")
	hydrated_world.queue_free()
	var original:=FileAccess.get_file_as_bytes(source_path);var replaced:=original.duplicate();replaced[-1]^=1;write(source_path,replaced)
	check(not Index.read(fixture.path,content_root).ok and not authority.register_map("changed","revision",meta).ok,"same accessor JSON but changed binary bytes invalidates directory and authority")
	write(source_path,original)
	await save_races_and_library_upgrade(record,source_path,original,replaced)
	await evidence(issued.snapshot)
	cleanup()
	print("IMPORTED_BUILDING_MEMBERSHIP passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)

func save_races_and_library_upgrade(record:Dictionary,source_path:String,original:PackedByteArray,replaced:PackedByteArray)->void:
	var document:=Document.new();document.records=[record.duplicate(true)]
	var validation:Dictionary={};var before:=document.records.duplicate(true)
	check(document.validate_save_record(document.records[0],{},validation)==OK and validation.has(source_path),"save first pass verifies actual source contract")
	write(source_path,replaced)
	check(document.validate_save_asset_paths(validation)==ERR_FILE_CORRUPT,"save final pass rejects source BIN changed after preflight yield")
	check(document.records==before,"failed final publication validation leaves author records unchanged")
	write(source_path,original)
	check(document.validate_save_asset_paths(validation)==OK,"unchanged restored source passes final publication validation")
	var library_folder:=folder.path_join("upgrade_library");DirAccess.make_dir_recursive_absolute(library_folder)
	var target:=library_folder.path_join(FileAccess.get_sha256(source_path)+".glb");write(target,original)
	var previous:Dictionary={"label":"existing imported fixture","category":"test","asset_path":target}
	var catalog:=library_folder.path_join("library.json");write(catalog,JSON.stringify([previous]).to_utf8_buffer())
	var catalog_sha:=FileAccess.get_sha256(catalog);var source_sha:=FileAccess.get_sha256(target)
	var library:=RejectedLibrary.new(library_folder)
	var result:=library.import_file(target)
	check(not result.get("ok",true) and library.save_calls==1,"existing entry upgrades contract and thumbnail in one failed transaction")
	check(library.proposed_entries.size()==1 and library.proposed_entries[0].has("model_building") and library.proposed_entries[0].has("thumbnail_path"),"single attempted transaction contains both new fields")
	check(library.entries==[previous] and FileAccess.get_sha256(catalog)==catalog_sha,"failed upgrade restores exact memory entry and immutable on-disk catalog")
	check(FileAccess.get_sha256(target)==source_sha and DirAccess.get_files_at(library_folder).size()==2,"failed upgrade preserves source and removes staging without derived publication")
	DirAccess.remove_absolute(target);DirAccess.remove_absolute(catalog);DirAccess.remove_absolute(library_folder)

func evidence(snapshot:Dictionary)->void:
	var world:=Node3D.new();root.add_child(world)
	var specs:Array=[];var meshes:Dictionary={};var bodies:Dictionary={}
	for uuid:String in snapshot.building.member_ids:
		var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();world.add_child(mesh);meshes[uuid]=mesh
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();body.add_child(shape);world.add_child(body);bodies[uuid]=body
		body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
		var r:Dictionary={"uuid":uuid,"building":{"id":snapshot.building.instance_id},"rmmo_collision":"walk"}
		if uuid.ends_with("door_mesh"):r.fixture={"id":"entry","kind":"door","pivot":[0,0,0],"angle":90,"open":0.0}
		specs.append({"uuid":uuid,"extras":r,"transform":Transform3D.IDENTITY,"closed_transform":Transform3D.IDENTITY})
	world.set_meta("stream_library",specs);world.set_meta("stream_meshes",meshes);world.set_meta("stream_bodies",bodies)
	var publication:=Engine.get_physics_frames();await physics_frame;await physics_frame
	var authority:=Authority.new()
	check(authority.inspect_root(snapshot,world,Engine.get_physics_frames(),publication).ok,"every exact native member with render, published collision and fixture pose passes")
	var removed:Dictionary=specs.pop_back()
	check(not authority.inspect_root(snapshot,world,Engine.get_physics_frames(),publication).structure_ready,"missing actual member denies readiness despite complete author descriptor")
	specs.append(removed)
	specs.append({"uuid":"unlisted","extras":{"uuid":"unlisted","building":{"id":snapshot.building.instance_id}}})
	check(not authority.inspect_root(snapshot,world,Engine.get_physics_frames(),publication).structure_ready,"extra unlisted geometry cannot borrow the building's exact-member receipt")
	specs.pop_back()
	for spec:Dictionary in specs:
		if spec.extras.has("fixture"):spec.extras.fixture.open=1.0
	check(not authority.inspect_root(snapshot,world,Engine.get_physics_frames(),publication).interactions_bound,"door scalar changes without real transformed geometry fail readiness")
	world.queue_free()

func cleanup()->void:
	# Every path is explicitly generated under this fixture/cache directory.
	for path:String in created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	if not folder.is_empty():DirAccess.remove_absolute(folder)
