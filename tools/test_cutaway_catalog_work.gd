extends SceneTree
const Cutaway=preload("res://scripts/world3d/building_cutaway.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
class CountCutaway extends Cutaway:
	var catalogs:=0
	var cell_removals:=0
	func _instances(scene:Node)->Dictionary:
		catalogs+=1;return super._instances(scene)
	func _remove_cells(id:String)->void:
		cell_removals+=1;super._remove_cells(id)
var checks:=0
var failures:Array=[]
var output:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture()->Dictionary:
	var rows:Array=[]
	for i in 10000:
		var state:Dictionary={}
		for j in 32:state["unchanged_%d"%j]=j
		rows.append({"uuid":"prop_%d"%i,"kind":"asset","rmmo_state":state})
	var members:Dictionary={}
	for i in 2048:members["Part_%d"%i]={"floor":0,"floor_y":0.,"role":"floor","part":"floor/%d"%i}
	var descriptor:={"version":1,"source_sha":"a".repeat(64),"members":members,"fixtures":{},"regions":[{"id":"room","floor":0,"min":[-4.,0.,-4.],"max":[4.,3.,4.]}]}
	var source:={"uuid":"house","kind":"asset","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"model_building":descriptor}
	rows.append(source)
	var part:={"uuid":"house__ceiling","position":[0.,3.,0.],"size":[8.,.2,8.],"building":{"id":"house","floor":1,"role":"ceiling","part":"roof/ceiling"}}
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("source_map_sha256","fixture");map.set_meta("author_reference_extras",{"rmmo_records":rows})
	map.set_meta("extras",{"rmmo_records":[part]})
	map.set_meta("stream_library",[{"uuid":part.uuid,"ground_batch_record":part}])
	return {"map":map,"source":source,"rows":rows,"part":part}
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var f:=fixture();var observer:=CountCutaway.new();var started:=Time.get_ticks_usec();observer.bind(f.map)
	var bind_us:=Time.get_ticks_usec()-started
	check(observer.catalogs==1,"bind discovers the author catalog once for records and loaded members")
	check(observer.locate(Vector3.ZERO).get("id","")=="house" and observer.buildings.house.parts.has(f.part.uuid),"initial room and already loaded ceiling are available immediately")
	var before:=observer.cell_removals
	f.source.model_building.members.Part_0.part="different_unrelated_member_name"
	observer.append_records(f.map,[f.part])
	check(observer.cell_removals==before,"unrelated descriptor members do not rebuild room cells")
	check(observer.locate(Vector3.ZERO).get("id","")=="house","member-only metadata change preserves room lookup")
	f.source.model_building.regions[0].max=[6.,3.,4.]
	observer.append_records(f.map,[f.part])
	check(observer.cell_removals>before and observer.locate(Vector3(5,0,0)).get("id","")=="house","changed authored region updates cells and room bounds immediately")
	f.source.rmmo_state={"position":[30.,0.,0.]}
	observer.append_records(f.map,[f.part])
	check(observer.locate(Vector3.ZERO).is_empty() and observer.locate(Vector3(30,0,0)).get("id","")=="house","mutable authored state remains observable after prior binding")
	started=Time.get_ticks_usec()
	for i in 40:observer.append_records(f.map,[f.part])
	var append_us:=Time.get_ticks_usec()-started
	check(f.rows[0].rmmo_state.size()==32 and f.source.model_building.members.size()==2048,"catalog work never mutates borrowed metadata")
	var foreign:=Node3D.new();root.add_child(foreign);observer.append_records(foreign,[f.part])
	check(observer.map_root==f.map,"unrelated map publication cannot replace current membership")
	observer.bind(null);check(observer.buildings.is_empty() and observer.index.is_empty(),"map unbind revokes every room immediately")
	# An unmounted caller still gets the original descriptor validation.
	f.map.remove_meta("source_map_sha256");f.source.model_building.regions[0].max=[-9.,3.,4.]
	observer.bind(f.map);check(observer.buildings.is_empty(),"malformed unmounted fixture cannot invent a room")
	f.map.set_meta("source_map_sha256","fixture");var previous_policy:bool=Policy.verify_packages;Policy.verify_packages=true
	observer.bind(f.map);check(observer.buildings.is_empty(),"explicit package audit retains descriptor validation even on a mounted map")
	Policy.verify_packages=previous_policy
	f.map.free();foreign.free()
	var report:={"checks":checks,"failures":failures,"bind_us":bind_us,"append_40_us":append_us,"authored_rows":10001,"descriptor_members":2048}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
