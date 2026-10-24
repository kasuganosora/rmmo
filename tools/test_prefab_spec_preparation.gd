extends "res://tools/test_house_geometry_identity_reuse.gd"
## The oracle executes the real document -> Prefab.visual -> Node projection.
## --legacy-projection keeps that old candidate to demonstrate temporary work.
const Legacy=preload("res://scripts/world3d/instance_spec_preparation.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017"
var direct:Script
var legacy:=false
var document:RefCounted
var trials:Array=[]

func old_projection(value:Dictionary,order:int,budget:int=1)->RefCounted:
	var holder:MeshInstance3D=document._mesh(value,true)
	var cursor:=Legacy.new();cursor.begin(holder,false,order)
	while not cursor.advance(budget):pass
	return cursor

func projection(value:Dictionary,entry:Dictionary,order:int)->RefCounted:
	if legacy:return old_projection(value,order)
	var cursor:RefCounted=direct.new();cursor.begin(value,entry,order)
	while not cursor.advance(1):pass
	return cursor

func prepared(value:Dictionary)->Dictionary:
	check(House.publish_prepared(value,House.prepare_cpu(value)),"prepare native CPU fixture "+str(value.uuid))
	return House.geometry(value)

func compare(value:Dictionary,entry:Dictionary,label:String)->void:
	var before:=value.duplicate(true)
	var expected:=old_projection(value,317)
	var candidate:=projection(value,entry,317)
	check(expected.specs.size()==1 and candidate.specs==expected.specs,label+" exact real-node oracle (every field)")
	if candidate.specs!=expected.specs:
		for key:Variant in expected.specs[0]:
			if candidate.specs[0].get(key)!=expected.specs[0][key] or typeof(candidate.specs[0].get(key))!=typeof(expected.specs[0][key]):print("FIELD_MISMATCH ",label," ",key," old=",expected.specs[0][key]," new=",candidate.specs[0].get(key)," types=",typeof(expected.specs[0][key]),"/",typeof(candidate.specs[0].get(key)))
	var actual:Dictionary=candidate.specs[0]
	check(is_same(actual.ground_batch_record,value) and actual.mesh==entry.mesh,label+" preserves record and CPU mesh owners")
	check(actual.surface_overrides.size()==entry.mesh.surfaces.size() and actual.surface_overrides.all(func(m):return m==null and typeof(m)==TYPE_OBJECT),label+" exact native null material slots")
	check(value==before and actual.uuid==value.uuid and actual.map_draw_order==317,label+" unchanged input, UUID and draw order")
	check(expected.profile.nodes_visited==1 and expected.profile.nodes_freed==1 and expected.profile.meshes_projected==1,label+" old route actually creates/projects/frees a temporary node")
	check(candidate.profile.get("nodes_visited",0)==0 and candidate.profile.get("nodes_freed",0)==0,label+" direct projection eliminates temporary node work")
	if value.has("fixture"):
		check(actual.has("closed_transform") and actual.extras.fixture==value.fixture and not is_same(actual.extras.fixture,value.fixture),label+" moving leaf retains independent fixture state")
		actual.extras.fixture.pivot[0]+=7.;actual.extras.fixture.open=.17
		check(value==before and expected.specs[0].extras.fixture==value.fixture,label+" runtime leaf edits cannot alter authored record or siblings")
	if value.has("building"):
		actual.extras.building.floor=99
		check(value==before,label+" floor metadata is privately owned")
	expected.dispose();candidate.dispose()

func benchmark(value:Dictionary,entry:Dictionary,use_legacy:bool,count:int)->Dictionary:
	var started:=Time.get_ticks_usec();var visits:=0;var frees:=0;var rows:=0
	for i:int in count:
		var cursor:RefCounted
		if use_legacy:cursor=old_projection(value,i,0)
		else:
			cursor=direct.new();cursor.begin(value,entry,i);cursor.advance(0)
		visits+=int(cursor.profile.get("nodes_visited",0));frees+=int(cursor.profile.get("nodes_freed",0));rows+=int(cursor.profile.get("meshes_projected",0))
		cursor.dispose()
	return {"legacy":use_legacy,"instances":count,"elapsed_us":Time.get_ticks_usec()-started,"nodes_visited":visits,"nodes_freed":frees,"meshes_projected":rows}

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	legacy="--legacy-projection" in OS.get_cmdline_user_args()
	if not legacy:direct=load("res://scripts/world3d/prefab_spec_preparation.gd")
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	preload("res://scripts/world3d/prefab_binary_cache.gd").enabled=false
	Controls.enable_white_materials();Controls.discard_map_textures=true
	document=Doc.new();document.load_immutable_records=true;document.load_texture_checks={}
	var data:=fixture();var shared:=record(encode(data),"native_shared")
	shared.position=[31.999,-2.25,-32.001];shared.rotation=[13.,-33.,7.];shared.size=[9.,3.,5.]
	shared.building={"id":"native_house","floor":2,"floor_y":6.,"role":"roof_tiles","part":"wing/baked_roof"}
	var shared_entry:=prepared(shared)
	compare(shared,shared_entry,"shared source/render rotated roof")
	var split:=data.duplicate(true);split.materials.append({"values":{"albedo_color":Color(.2,.3,.7),"cull_mode":BaseMaterial3D.CULL_DISABLED}})
	var second:Array=split.meshes[0].surfaces[0].duplicate(true)
	second[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,2,0),Vector3(3,2,0),Vector3(0,2,-4)])
	split.meshes[0].surfaces.append(second);split.meshes[0].materials.append(1)
	split.meshes[0].bounds=AABB(Vector3(0,0,-4),Vector3(3,2,4))
	split.meshes.append(data.meshes[0].duplicate(true));split.entries[0][1]=[0,1]
	var separate:=record(encode(split),"native_separate");separate.position=[-64.,.5,31.];separate.rotation=[-17.,127.,32.]
	separate.fortification={"id":"wall","part":"tower/cap","floor":3}
	var separate_entry:=prepared(separate)
	compare(separate,separate_entry,"separate collision and multi-material slots")
	for mode:String in ["none","walk","block"]:
		var leaf:=shared.duplicate(true);leaf.uuid="leaf_"+mode;leaf.collision=mode
		leaf.fixture={"id":"door","kind":"door","pivot":[-.7,.3,.2],"angle":-97.,"open":.625}
		compare(leaf,shared_entry,"moving leaf "+mode)
	for amount:float in [0.,1.]:
		var leaf:=separate.duplicate(true);leaf.uuid="shutter_"+str(amount)
		leaf.fixture={"id":"shutter","kind":"shutter","pivot":[1.3,-.2,-.6],"angle":180.,"open":amount}
		compare(leaf,separate_entry,"shutter endpoint "+str(amount))
	var render_only:=separate.duplicate(true);render_only.uuid="render_only";render_only.collision="none"
	compare(render_only,separate_entry,"render-only prefab")
	if not legacy:boundaries(shared,shared_entry)
	if not legacy:
		for old:bool in [true,false,false,true]:trials.append(benchmark(shared,shared_entry,old,2048))
	else:trials.append(benchmark(shared,shared_entry,true,2048))
	print("PREFAB_SPEC_PREPARATION ",JSON.stringify({"legacy":legacy,"checks":checks,"failures":failures,"trials":trials}))
	var report:=FileAccess.open(OUT.path_join("prefab_spec_178_"+("red" if legacy else "green")+".json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"legacy":legacy,"checks":checks,"failures":failures,"trials":trials},"\t"));report.close()
	quit(1 if failures else 0)

func boundaries(value:Dictionary,entry:Dictionary)->void:
	check(direct.supports(value,entry),"prepared white box is eligible")
	check(not direct.supports(value,entry,true),"local-collision collector keeps original root exclusion semantics")
	var unsupported:=value.duplicate(true);unsupported.kind="asset"
	check(not direct.supports(unsupported,entry),"asset scale setter stays on original path")
	unsupported=value.duplicate(true);unsupported.surface_paint=[{"face":0}]
	check(not direct.supports(unsupported,entry),"painted geometry stays on its original preparation path")
	unsupported=value.duplicate(true);unsupported.erase("house_prefab")
	check(not direct.supports(unsupported,entry),"ordinary records cannot bypass their geometry adapter")
	check(not direct.supports(value,{}),"missing prepared CPU owners cannot become empty specs")
	Controls.discard_map_textures=false
	check(not direct.supports(value,entry),"textured loading is outside this candidate")
	Controls.discard_map_textures=true;Controls.white_materials=false
	check(not direct.supports(value,entry),"ordinary material mode is outside this candidate")
	Controls.white_materials=true
	var box:=Cpu.new();box.box_size=Vector3.ONE
	check(not direct.supports(value,{"mesh":entry.mesh,"source":box}),"unprepared primitive collider cannot create resources in CPU projection")
	var cursor:RefCounted=direct.new();cursor.begin(value,entry,9);cursor.dispose()
	check(cursor.specs.is_empty() and cursor.advance(0) and cursor.profile.meshes_projected==0,"cancel before projection publishes nothing")
	cursor=direct.new();cursor.begin(value,entry,9);cursor.advance(0)
	var handed:Array=cursor.specs;cursor.specs=[];cursor.dispose()
	check(handed.size()==1 and handed[0].mesh==entry.mesh and cursor.specs.is_empty(),"cancel/dispose retains no output but transferred specs keep owners")
	var worker:=Thread.new();var started:=worker.start(func():var c:RefCounted=direct.new();c.begin(value,entry,23);c.advance(0);return c.specs)
	check(started==OK,"CPU projection can execute without the scene thread")
	var expected:=old_projection(value,23)
	check(worker.wait_to_finish()==expected.specs,"worker result equals real scene-thread projection")
	var fields:Dictionary=direct.project_fields(value,entry.mesh.bounds,23)
	check(not fields.has("mesh") and not fields.has("collision_mesh") and not fields.has("surface_overrides"),"pure record/bounds stage has no geometry-resource bindings")
	check(direct.bind_geometry(fields,entry)==expected.specs[0],"separate canonical owner binding retains the exact legacy output")
	var bounds:AABB=entry.mesh.bounds
	worker=Thread.new();worker.start(func():return direct.project_fields(value,bounds,23))
	var cpu_fields:Dictionary=worker.wait_to_finish()
	check(direct.bind_geometry(cpu_fields,entry)==expected.specs[0],"worker record/bounds-only packet binds exact main-thread shared owners")
	expected.dispose()
