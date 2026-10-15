extends SceneTree
## Compare against a SHA-pinned pre-T1 solver, including complete diagnostics.
## Only counters may change. Fixtures stay in memory; no user map is opened.
const Support=preload("res://scripts/world_editor/residential_support.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const SOURCE="res://review_artifacts/editor_reliability/t1_support_reference/source.gd.txt"
const METADATA="res://review_artifacts/editor_reliability/t1_support_reference/metadata.json"
const SEED=6151037
var reference:GDScript
var checks:Array=[]
var failures:=0
var cases:=0
var metadata:Dictionary={}

class Document extends RefCounted:
	var records:Array=[]

func _init()->void:run.call_deferred()

func check(ok:bool,label:String,detail:Dictionary={})->void:
	checks.append({"ok":ok,"label":label,"detail":detail})
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func without_counts(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:
			if key!="counts":result[key]=without_counts(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item:Variant in value:result.append(without_counts(item))
		return result
	return value

func first_differences(a:Variant,b:Variant,path:String="",output:Array=[])->Array:
	if output.size()>=12:return output
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):output.append({"path":path+"."+str(key),"expected":a[key],"actual":"<missing>"})
			else:first_differences(a[key],b[key],path+"."+str(key),output)
		for key:Variant in b:
			if not a.has(key):output.append({"path":path+"."+str(key),"expected":"<missing>","actual":b[key]})
	elif a is Array and b is Array:
		if a.size()!=b.size():output.append({"path":path+".length","expected":a.size(),"actual":b.size()})
		for i in mini(a.size(),b.size()):first_differences(a[i],b[i],path+"[%d]"%i,output)
	elif a!=b:
		output.append({"path":path,"expected":a,"actual":b})
	return output

func field(id:String="ground",columns:int=64,rows:int=64,at:Vector3=Vector3.ZERO,yaw:float=0.,size:Vector3=Vector3(8,1,8))->Dictionary:
	var heights:Array=[];heights.resize((columns+1)*(rows+1));heights.fill(0.)
	var holes:Array=[];holes.resize(columns*rows);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[at.x,at.y,at.z],"rotation":[0.,yaw,0.],"size":[size.x,size.y,size.z],"collision":"walk","terrain_mesh":{"version":1,"columns":columns,"rows":rows,"floor":-8.,"heights":heights,"holes":holes}}

func residence()->Array:
	return [{"uuid":"floor","kind":"box","position":[0.,.3,0.],"rotation":[0,0,0],"size":[4.,.2,4.],"collision":"walk","building":{"part":"main/floor","floor":0,"floor_y":.3,"role":"floor"}},
		{"uuid":"base","kind":"box","position":[0.,-.4,0.],"rotation":[0,0,0],"size":[4.,1.2,4.],"collision":"walk","building":{"part":"main/floor/foundation","floor":0,"floor_y":.3,"role":"foundation"}}]

func compare(label:String,terrains:Array,polygon:Variant=null,position:Vector3=Vector3.ZERO,yaw:float=0.,expected_code:String="")->void:
	cases+=1
	var old_doc:=Document.new();old_doc.records=terrains.duplicate(true)
	var new_doc:=Document.new();new_doc.records=terrains.duplicate(true)
	var old_house:=residence();var new_house:=old_house.duplicate(true)
	var old_before:=var_to_bytes([old_doc.records,old_house]);var new_before:=var_to_bytes([new_doc.records,new_house])
	var expected:Dictionary;var actual:Dictionary
	if polygon==null:
		expected=reference.solve(old_doc,old_house,position,yaw,{"layout":"townhouse"},{"input_version":"differential"})
		actual=Support.solve(new_doc,new_house,position,yaw,{"layout":"townhouse"},{"input_version":"differential"})
	else:
		expected=reference.terrain_region(old_doc,polygon)
		actual=Support.terrain_region(new_doc,polygon)
	var a:Dictionary=without_counts(expected);var b:Dictionary=without_counts(actual)
	var equal:=a==b
	check(equal and old_before==var_to_bytes([old_doc.records,old_house]) and new_before==var_to_bytes([new_doc.records,new_house]),label,{"differences":[] if equal else first_differences(a,b,"",[]),"baseline_counts":expected.get("counts",expected.get("support",{}).get("counts",{})),"current_counts":actual.get("counts",actual.get("support",{}).get("counts",{})),"code":actual.get("code","ok")})
	if not expected_code.is_empty():check((expected.ok if expected_code=="ok" else expected.get("code","")==expected_code),label+" exercises intended outcome",{"expected_code":expected_code,"actual_code":expected.get("code","ok")})

func rectangle(x0:float,z0:float,x1:float,z1:float)->Array:
	return [[x0,z0],[x1,z0],[x1,z1],[x0,z1]]

func compare_region(label:String,terrains:Array,polygon:Array,origin:Vector3=Vector3.ZERO)->void:
	cases+=1
	var old_doc:=Document.new();old_doc.records=terrains.duplicate(true)
	var new_doc:=Document.new();new_doc.records=terrains.duplicate(true)
	var component:={"record_id":"raw_region","part":"access_strip","foundation_id":"","polygon":polygon,"bounds":reference.bounds(polygon),"area":reference.area(polygon),"floor_bottom":0.,"foundation_bottom":-1.}
	var old_counts:={"terrain_candidates":0,"cells_visited":0,"triangle_clips":0,"overlaps":0}
	var new_counts:Dictionary=old_counts.duplicate()
	var old_input:=[old_doc.records,component.duplicate(true)];var new_input:=[new_doc.records,component.duplicate(true)]
	var old_bytes:=var_to_bytes(old_input);var new_bytes:=var_to_bytes(new_input)
	var expected:Dictionary=reference.region(old_doc,old_input[1],origin,old_counts,true)
	var actual:Dictionary=Support.region(new_doc,new_input[1],origin,new_counts,true)
	var a:Dictionary=without_counts(expected);var b:Dictionary=without_counts(actual)
	var equal:=a==b
	check(equal and old_bytes==var_to_bytes(old_input) and new_bytes==var_to_bytes(new_input),label,{"differences":[] if equal else first_differences(a,b,"",[]),"baseline_counts":old_counts,"current_counts":new_counts,"piece_count":actual.get("pieces",[]).size(),"code":actual.get("code","ok")})

func run()->void:
	var started:=Time.get_ticks_usec()
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(METADATA))
	check(parsed is Dictionary,"reference metadata is readable")
	if not parsed is Dictionary:finish(started);return
	metadata=parsed
	check(FileAccess.get_sha256(SOURCE)==metadata.source_sha256,"reference source SHA matches the frozen baseline")
	reference=GDScript.new();reference.source_code=FileAccess.get_file_as_string(SOURCE)
	check(reference.reload()==OK,"frozen pre-T1 source compiles")
	if failures:finish(started);return
	var flat:=field()
	compare("flat support and exact elevation witnesses",[flat],null,Vector3.ZERO,0.,"ok")
	compare("grid-aligned one-cell corridor",[flat],rectangle(-2.,-2.,-1.875,-1.875),Vector3.ZERO,0.,"ok")
	compare("sub-cell offset across grid boundary",[flat],rectangle(-2.000001,-2.000001,-1.874999,-1.874999),Vector3.ZERO,0.,"ok")
	compare("first tile corner and boundary cells",[flat],rectangle(-4.,-4.,-3.8,-3.8),Vector3.ZERO,0.,"ok")
	compare("last tile corner and boundary cells",[flat],rectangle(3.8,3.8,4.,4.),Vector3.ZERO,0.,"ok")
	compare("partial support beyond tile border",[flat],rectangle(3.9,3.9,4.1,4.1),Vector3.ZERO,0.,"residential_support_coverage_gap")
	compare_region("raw Access pieces across a sub-cell grid boundary",[flat],rectangle(-2.000001,-2.000001,-1.874999,-1.874999))
	compare_region("raw Access pieces at the first tile boundary",[flat],rectangle(-4.,-4.,-3.8,-3.8))
	compare_region("raw Access pieces at the last tile boundary",[flat],rectangle(3.8,3.8,4.,4.))
	var narrow:=flat.duplicate(true);narrow.terrain_mesh.holes[18*64+18]=true
	compare("narrow interior hole with exact gap polygon and cell",[narrow],null,Vector3.ZERO,0.,"residential_support_coverage_gap")
	compare_region("raw Access local hole preserves failure and witness",[narrow],rectangle(-2.,-2.,2.,2.))
	var far_hole:=flat.duplicate(true);far_hole.terrain_mesh.holes[18*64+2]=true
	compare("far-X hole with intersecting Z preserves subtraction fragments",[far_hole],null,Vector3.ZERO,0.,"ok")
	compare_region("raw Access distant-hole pieces retain their exact order",[far_hole],rectangle(-2.,-2.,2.,2.))
	far_hole.terrain_mesh.holes[18*64+18]=true
	compare("far hole plus local hole preserve complete failure witness",[far_hole],null,Vector3.ZERO,0.,"residential_support_coverage_gap")
	var fragmented:=flat.duplicate(true)
	for z in 64:
		for x in 4:fragmented.terrain_mesh.holes[z*64+x]=true
	compare("all rows of distant holes preserve fragment order",[fragmented],null,Vector3.ZERO,0.,"ok")
	var empty:=flat.duplicate(true);empty.terrain_mesh.holes.fill(true)
	compare("all-hole tile remains invalid before spatial filtering",[empty],null,Vector3.ZERO,0.,"residential_support_invalid_terrain")
	var duplicate:=flat.duplicate(true);duplicate.uuid="overlap"
	compare("overlapping fields preserve unsupported error and area witness",[flat,duplicate],null,Vector3.ZERO,0.,"residential_support_unsupported")
	var hidden:=flat.duplicate(true);hidden.editor_hidden=true
	compare("hidden field remains unsupported",[hidden],null,Vector3.ZERO,0.,"residential_support_unsupported")
	var locked:=flat.duplicate(true);locked.editor_locked=true
	compare("locked field remains valid read-only support",[locked],null,Vector3.ZERO,0.,"ok")
	var invalid:=field("far_invalid",64,64,Vector3(100,0,100));invalid.terrain_mesh.heights[0]="invalid"
	compare("invalid far tile first is still rejected",[invalid,flat],null,Vector3.ZERO,0.,"residential_support_invalid_terrain")
	compare("invalid far tile after complete support is still rejected",[flat,invalid],null,Vector3.ZERO,0.,"residential_support_invalid_terrain")
	var left:=field("left",8,8,Vector3(-4,0,0));var right:=field("right",16,32,Vector3(4,.3,0))
	compare("mixed-grid seam preserves grade, jump and exact seam witness",[left,right],rectangle(-1.,-1.,1.,1.),Vector3.ZERO,0.,"ok")
	var rng:=RandomNumberGenerator.new();rng.seed=SEED
	for i in 8:
		var at:=Vector3(10000. if i%2==0 else -10000.,7.,-10000. if i%3==0 else -320.)
		var yaw:=rng.randf_range(-179.,179.)
		var tile:=field("seeded_%d"%i,32 if i%2 else 64,16 if i%3 else 64,at,yaw,Vector3(11.7,1.3,9.3))
		for z in int(tile.terrain_mesh.rows)+1:
			for x in int(tile.terrain_mesh.columns)+1:tile.terrain_mesh.heights[z*(int(tile.terrain_mesh.columns)+1)+x]=rng.randf_range(-.035,.035)
		compare("seeded far rotated rectangular field %d"%i,[tile],null,at,yaw+rng.randf_range(-12.,12.),"ok")
		if i<3:
			compare_region("raw Access far rotated pieces %d"%i,[tile],reference.box_polygon(residence()[0],yaw),at)
			var hole_index: int=(int(tile.terrain_mesh.rows)/2)*(int(tile.terrain_mesh.columns))+int(tile.terrain_mesh.columns)/2
			tile.terrain_mesh.holes[hole_index]=true
			compare("seeded far rotated narrow hole %d"%i,[tile],null,at,yaw,"residential_support_coverage_gap")
	var doc:=Doc.new();doc.records=[flat.duplicate(true)]
	var before:=doc.recovery_snapshot()
	doc.records[0].position=[100.,0.,100.];doc.commit_recovery_change(before)
	compare("moved tile does not reuse previous coverage",doc.records,null,Vector3.ZERO,0.,"residential_support_coverage_gap")
	check(doc.undo(),"fixture undo restores the prior terrain snapshot")
	compare("undo restores the original proof",doc.records,null,Vector3.ZERO,0.,"ok")
	check(doc.redo(),"fixture redo restores the moved terrain snapshot")
	compare("redo restores moved coverage failure",doc.records,null,Vector3.ZERO,0.,"residential_support_coverage_gap")
	doc.apply_recovery(before);doc.records.clear()
	compare("deleted tile cannot supply old coverage",doc.records,null,Vector3.ZERO,0.,"residential_support_coverage_gap")
	var reopened:=Doc.new();reopened.apply_recovery(before)
	reopened.records=JSON.parse_string(JSON.stringify(reopened.records))
	compare("new document JSON round-trip preserves reopen numeric representation",reopened.records,null,Vector3.ZERO,0.,"ok")
	finish(started)

func finish(started:int)->void:
	var output:="D:/code/rmmo_runtime/review_artifacts/editor_reliability/t1_support_differential"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var report:={"checks":checks,"cases":cases,"failures":failures,"seed":SEED,"baseline":metadata,"current_source_sha256":FileAccess.get_sha256("res://scripts/world_editor/residential_support.gd"),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.,"scope":"pure CPU differential geometry; only recursive counts fields excluded; JSON round-trip is not native save/reopen acceptance"}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("test_residential_support_differential: cases=%d checks=%d failures=%d"%[cases,checks.size(),failures])
	quit(1 if failures else 0)
