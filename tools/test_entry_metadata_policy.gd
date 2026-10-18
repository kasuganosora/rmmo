extends SceneTree
const Memory=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Embedded=preload("res://scripts/world3d/embedded_glb.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func policies(value:Dictionary)->Array:
	return [Memory._bounded_plain(value),Bounds._extension_safe(value),Embedded._plain(value),Bounds.has_native_identity(value)]
func deep(depth:int,tail:Variant)->Dictionary:
	var result:Dictionary={};var cursor:Dictionary=result
	for i in depth-1:
		var child:Dictionary={};cursor.next=child;cursor=child
	cursor.next=tail
	return result
func run()->void:
	check(policies({"numbers":[1,2,3],"nested":[{"name":"ok","flag":true} ]})==[true,true,true,false],"ordinary scalar leaves and containers accepted")
	for tail:Variant in [{"uri":"remote"},{"extras":[{"uri":"remote"}]}]:
		var value:Dictionary=deep(5,tail)
		check(policies(value).slice(0,3)==[false,false,false],"unknown URI rejected through nested arrays and dictionaries")
	for marker:String in ["rmmo_format","rmmo_records","rmmo_storage","rmmo_resource_dependencies"]:
		var value:Dictionary=deep(7,{marker:[]})
		check(policies(value)==[false,true,true,true],"native identity remains distinct from embedded encoding policy: "+marker)
	var supported:={"materials":[{"extensions":{"KHR_materials_unlit":{}}}],"extensionsUsed":["KHR_materials_unlit"]}
	check(policies(supported)==[true,true,true,false],"supported optional material extensions remain accepted")
	supported.extensionsRequired=["KHR_materials_unlit"]
	check(policies(supported)==[true,false,false,false],"memory estimate and strict importer preserve different required-extension contracts")
	check(policies({"extensionsUsed":null,"extensionsRequired":null})==[true,true,true,false],"null declarations remain supported")
	check(policies({"nodes":[{"extensions":{"KHR_materials_unlit":{}}}]})==[true,false,false,false],"known extension in node scope remains rejected by static importer")
	check(policies({"extras":{"extensionsUsed":["KHR_materials_unlit"]}})==[true,false,false,false],"nested root declarations cannot masquerade as top-level contracts")
	check(policies({"materials":[{"extensions":{"UNKNOWN":{}}}]})==[false,false,false,false],"unknown extension remains rejected")
	check(policies({"materials":[{"extensions":{"KHR_materials_unlit":{"uri":"remote"}}}]})==[false,false,false,false],"URI inside permitted extension payload remains rejected")
	check(Memory._bounded_plain(deep(32,1)),"scalar at depth 32 accepted")
	check(not Memory._bounded_plain(deep(33,1)),"scalar at depth 33 rejected even without a work item")
	check(Memory._bounded_plain(deep(32,{})),"empty container at depth 32 accepted")
	check(not Memory._bounded_plain(deep(33,{})),"empty container at depth 33 rejected")
	var wide:Dictionary={}
	for i in 199999:wide[str(i)]=i
	check(Memory._bounded_plain(wide),"exact 200000 total values accepted")
	wide.last=0
	check(not Memory._bounded_plain(wide),"all scalar leaves still count against total traversal limit")
	var array:Array=[];array.resize(Memory.MAX_ITEMS+1)
	check(not Memory._bounded_plain({"wide":array}),"per-array count limit remains enforced")
	var cyclic:Dictionary={};cyclic.self=cyclic
	check(not Memory._bounded_plain(cyclic),"cyclic metadata terminates at depth limit");cyclic.erase("self")
	print("METADATA_POLICY checks=",checks," failures=",failures);quit(0 if failures==0 else 1)
