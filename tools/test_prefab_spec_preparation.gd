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
	printerr("Shared fixture only; run test_textured_prefab_spec_preparation.gd")
	quit(2)
