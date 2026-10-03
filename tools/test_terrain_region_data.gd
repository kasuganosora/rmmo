extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Tools=preload("res://scripts/world_editor/terrain_region_tools.gd")
const Data=preload("res://scripts/world3d/terrain_regions.gd")
var failed:=0
func _initialize() -> void:
	var doc:=Doc.new(); var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var id: String=doc.add_box("grass",Vector3(20,0,30),Vector3(32,1,32))
	var r: Dictionary=doc._find(id); r.rotation=[0,90,0]
	var heights: Array=[]; heights.resize(9); heights.fill(0.); r.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-8.,"heights":heights,"holes":[false,false,false,false]}
	var args:={"id":"garden","terrain_ids":[id],"polygon":[[10,20],[30,20],[30,40],[10,40]],"material_id":"builtin:white","feather":2.}
	var ready:=Tools.prepare(doc.records,args,library,func(_r):return true)
	check(ready.ok,"rotated terrain accepts world region")
	if not ready.ok: quit(1); return
	doc.records=ready.records; var mask:=Data.mask(doc.records[0]); check(mask.get_pixel(128,128).r>.99 and mask.get_pixel(0,0).r<.01,"translated/rotated coverage lands at intended location")
	doc.records=JSON.parse_string(JSON.stringify(doc.records))
	var second:=Tools.prepare(doc.records,args.merged({"id":"second","polygon":[[11,21],[18,21],[18,27],[11,27]]},true),library,func(_r):return true)
	check(second.ok and second.records[0].terrain_regions.materials.size()==1,"JSON float indices reuse the same material slot")
	doc.records=second.records
	var before:=doc.records.duplicate(true)
	var copied:=preload("res://scripts/world_editor/selection_geometry.gd").duplicate_records(doc,before,Vector3(100,0,100),"Copy")
	var copy: Dictionary=doc._find(copied[0]); check(copy.terrain_regions.regions[0].id!=before[0].terrain_regions.regions[0].id and copy.terrain_regions.regions[0].polygon==before[0].terrain_regions.regions[0].polygon,"copy isolates region identity and preserves local coverage")
	var a:=Data.mask(copy); check(a.get_data()==mask.get_data() or a.get_pixel(128,128).r>.99,"copy retains painted coverage")
	var records: Array=[]; var ids: Array=[]
	for i in 34:
		var big: Dictionary=before[0].duplicate(true); big.uuid="t_%d"%i; big.size=[200,1,200]; big.position=[i*200,0,0]; big.rotation=[0,0,0]; big.erase("terrain_regions"); records.append(big); ids.append(big.uuid)
	var originals:=records.duplicate(true)
	var budget:=Tools.prepare(records,{"id":"huge","terrain_ids":ids,"polygon":[[-100,-100],[6800,-100],[6800,100],[-100,100]],"material_id":"builtin:white"},library,func(_r):return true)
	check(not budget.ok and budget.error.contains("计算量") and originals==records,"work budget rejects entire large stroke without changing input")
	print("TERRAIN_REGION_DATA_FINISHED failures=",failed); quit(1 if failed else 0)
func check(ok: bool,label_: String) -> void:
	print(("PASS " if ok else "FAIL ")+label_)
	if not ok: failed+=1
