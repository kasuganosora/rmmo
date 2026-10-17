extends SceneTree
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const Baseline=preload("res://review_artifacts/material_lookup_20261017/library_baseline.gd")
const Roads=preload("res://scripts/world_editor/road_tools.gd")
const OldRoads=preload("res://review_artifacts/material_lookup_20261017/road_guarded_baseline.gd")
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/material_lookup_20261017/"
class Counted extends Library:
	var scans:=0
	func entries(content_root:String="")->Array:
		scans+=1
		return super.entries(content_root)
class Snapshot extends Counted:
	var rows:Array=[]
	func entries(_content_root:String="")->Array:
		scans+=1;return rows
var checks:Array=[]
var directory:String
var library:Counted
var baseline:RefCounted
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks.append({"ok":ok,"label":label_});print("PASS " if ok else "FAIL ",label_)
func write(path:String,value:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()
func material(label_:String="test")->Dictionary:return {"name":label_,"color":[1.,1.,1.,1.],"roughness":.8}
func compare(ids:Array,label_:String)->Dictionary:
	var expected:Dictionary={}
	for id:String in ids:
		var value:Dictionary=baseline.find(id)
		if not value.is_empty():expected[id]=value
	var before:=var_to_bytes(ids);var scans:=library.scans
	var actual:=library.find_many(ids)
	check(ids.all(func(id):return var_to_bytes(actual.get(id,{}))==var_to_bytes(expected.get(id,{}))) and actual.size()==expected.size(),label_+" exact materials and misses match frozen single lookup")
	check(library.scans-scans==(0 if ids.is_empty() else 1) and before==var_to_bytes(ids),label_+" one fresh catalog and input unchanged")
	return actual
func road_compare(args:Dictionary,label_:String)->void:
	var f:=Fixture.ordinary();f.layout.roads=Fixture.graph([[[-12.,0.,0.],[12.,0.,0.]]])
	var ctx:=Fixture.context(f);ctx._material_tool.library=library
	var now:=Roads.new();now.editor=ctx;var old:=OldRoads.new();old.editor=ctx
	var state:=var_to_bytes(Fixture.state(ctx));var before:=library.scans
	var actual:=now.prepare(args);var scans:=library.scans-before
	var expected:=old.prepare(args)
	check(var_to_bytes(actual)==var_to_bytes(expected),label_+" complete road success/error bytes match baseline")
	check(state==var_to_bytes(Fixture.state(ctx)),label_+" no author/history mutation")
	check(scans==(0 if args.get("material_id","").is_empty() and not args.get("kerb_enabled",false) else 1),label_+" expected catalog count")
	check(actual.ok==not ("missing" in args.values() or "texture" in args.values()),label_+" expected success or rejection")
	now.editor=null;old.editor=null;ctx._waterways.editor=null;ctx.free()
func run()->void:
	DirAccess.make_dir_recursive_absolute(Evidence)
	directory=Paths.cache_directory("lookup_batch_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var manager:=root.get_node("AssetManager");var original:String=manager.content_root_override
	manager.content_root_override=directory
	library=Counted.new(directory.path_join("local"));baseline=Baseline.new(library.directory)
	var pavement:=material("pavement");var kerb:=material("kerb")
	write(library.directory.path_join("pavement.json"),{"material":pavement})
	write(library.directory.path_join("kerb.json"),{"material":kerb})
	compare([],"empty");compare(["builtin:white","builtin:checker","pavement","kerb","missing","pavement"],"mixed and repeated IDs")
	var result:=compare(["pavement","kerb"],"detached result");result.pavement.color[0]=0.
	check(library.find_many(["pavement"]).pavement.color[0]==1.,"caller mutation never persists")
	for args:Dictionary in [{},{"material_id":"pavement"},{"kerb_enabled":true,"kerb_material_id":"kerb"},{"material_id":"pavement","kerb_enabled":true,"kerb_material_id":"kerb"},{"material_id":"pavement","kerb_enabled":true,"kerb_material_id":"pavement"},{"material_id":"missing","kerb_enabled":true,"kerb_material_id":"missing"},{"material_id":"pavement","kerb_enabled":true,"kerb_material_id":"missing"}]:road_compare(args,str(args))
	write(library.directory.path_join("pavement.json"),{"material":material("edited")})
	check(compare(["pavement","kerb"],"external replacement").pavement.name=="edited","descriptor changes visible on next call")
	var ctx:=Fixture.context(Fixture.local_terrain());ctx._material_tool.library=library
	var road:=Roads.new();road.editor=ctx
	var params:={"follow_terrain":true,"material_id":"pavement","kerb_enabled":true,"kerb_material_id":"kerb"}
	var first:=road.prepare(params)
	write(library.directory.path_join("pavement.json"),{"material":material("changed again")})
	var changed_preview:=road.prepare(params)
	check(first.ok and changed_preview.ok and first.plan_token!=changed_preview.plan_token,"same pavement ID with changed definition changes plan token")
	write(library.directory.path_join("kerb.json"),{"material":material("changed kerb")})
	var third:=road.prepare(params)
	check(third.ok and third.plan_token!=changed_preview.plan_token,"same kerb ID with changed definition changes plan token")
	road.editor=null;ctx._waterways.editor=null;ctx.free()
	DirAccess.remove_absolute(library.directory.path_join("kerb.json"));compare(["pavement","kerb"],"external deletion")
	write(library.directory.path_join("kerb.json"),{"material":kerb});compare(["kerb"],"external reappearance")
	var invalid:=kerb.duplicate(true);invalid.roughness=2.
	write(library.directory.path_join("invalid.json"),{"material":invalid});compare(["invalid","pavement"],"invalid schema")
	write(library.directory.path_join(".hidden/ignored.json"),{"material":kerb})
	var deep:="a/b/c/d/e/f/g/h/"
	write(library.directory.path_join(deep+"accepted.json"),{"material":kerb})
	write(library.directory.path_join(deep+"i/rejected.json"),{"material":kerb})
	compare([".hidden/ignored",deep+"accepted",deep+"i/rejected","../kerb","kerb.json","KERB"],"depth hidden traversal extension case")
	var pack:=directory.path_join("packs/default");write(pack.path_join("metadata.json"),{"id":"default","name":"default"})
	write(pack.path_join("assets/materials/nested/material.json"),{"material":material("shared")})
	var second:=directory.path_join("default");write(second.path_join("metadata.json"),{"id":"default","name":"default"})
	write(second.path_join("assets/materials/nested/material.json"),{"material":material("duplicate")})
	library.include_shared=true;baseline.include_shared=true
	compare(["pack:default:nested/material","pavement"],"duplicate shared identities preserve catalog winner")
	invalid=material("escape");invalid.texture_path="../../../../sources/escape.png"
	write(pack.path_join("assets/materials/escape.json"),{"material":invalid})
	compare(["pack:default:escape"],"shared pack texture confinement")
	write(pack.path_join("metadata.json"),{"id":"changed","name":"changed"})
	compare(["pack:default:nested/material","pack:changed:nested/material"],"pack identity changes visible")
	library.include_shared=false;baseline.include_shared=false
	compare(["pack:default:nested/material","pavement"],"shared switch visible")
	var png:=directory.path_join("texture.png");var image:=Image.create(2,2,false,Image.FORMAT_RGB8);image.fill(Color.WHITE);image.save_png(png)
	var textured:=material("textured");textured.texture_path=png
	write(library.directory.path_join("texture.json"),{"material":textured});compare(["texture"],"texture before deletion")
	DirAccess.remove_absolute(png)
	check(compare(["texture"],"missing file schema semantics").has("texture"),"lookup retains schema-only semantics for missing texture")
	road_compare({"kerb_enabled":true,"kerb_material_id":"texture"},"selected missing kerb texture rejected")
	manager.content_root_override=directory.path_join("different_root")
	compare(["pavement","kerb","builtin:white"],"resource root changes invalidate previous successes")
	manager.content_root_override=directory
	var linked:=library.directory.path_join("swapped");var target:=directory.path_join("link_target")
	write(linked.path_join("material.json"),{"material":kerb});write(target.path_join("material.json"),{"material":pavement})
	check(compare(["swapped/material"],"before path replacement").has("swapped/material"),"ordinary folder material resolves")
	DirAccess.remove_absolute(linked.path_join("material.json"));check(DirAccess.remove_absolute(linked)==OK,"remove only empty temporary link fixture directory")
	var output:Array=[]
	var command:="$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null"%[linked.replace("'","''"),target.replace("'","''")]
	var link_result:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],output,true,false)
	check(link_result==0,"create temporary junction without activating a window")
	if link_result==0:
		check(not compare(["swapped/material"],"folder replaced by junction").has("swapped/material"),"next call rejects formerly valid directory changed to junction")
		check(OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command","[IO.Directory]::Delete('%s')"%linked.replace("'","''")],output,true,false)==0,"unlink only temporary junction non-recursively")
	var snapshot:=Snapshot.new();snapshot.rows=[{"material_id":"same","material":pavement},{"material_id":"same","material":kerb}]
	check(snapshot.find_many(["same"]).same==pavement and snapshot.scans==1,"virtual catalogs and first duplicate remain supported")
	# Boundary fixture: entries stops before descending after 2048 valid rows,
	# including two builtins; it does not truncate the last directory mid-loop.
	library.directory=directory.path_join("cap");baseline.directory=library.directory
	for i in 2046:write(library.directory.path_join("%04d.json"%i),{"material":kerb})
	write(library.directory.path_join("later/hidden.json"),{"material":pavement})
	var capped:=compare(["2045","later/hidden","builtin:white"],"catalog cap")
	check(capped.has("2045") and not capped.has("later/hidden"),"catalog cap excludes later directory exactly as before")
	manager.content_root_override=original
	var failures:=checks.filter(func(c):return not c.ok).size()
	var file:=FileAccess.open(Evidence+"batch_tests.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":directory},"\t"));file.close()
	print("MATERIAL_LOOKUP_BATCH checks=",checks.size()," failures=",failures);quit(1 if failures else 0)
