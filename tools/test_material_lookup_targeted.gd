extends SceneTree
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const Baseline=preload("res://review_artifacts/material_targeted_20261017/surface_material_library_baseline.gd")
const Roads=preload("res://scripts/world_editor/road_tools.gd")
const OldRoads=preload("res://review_artifacts/material_targeted_20261017/road_tools_baseline.gd")
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/material_targeted_20261017/"
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
var skipped:Array=[]
var directory:String
var library:Library
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
	var before:=var_to_bytes(ids)
	var actual:=library.find_many(ids)
	check(ids.all(func(id):return var_to_bytes(actual.get(id,{}))==var_to_bytes(expected.get(id,{}))) and actual.size()==expected.size(),label_+" exact materials and misses match frozen single lookup")
	check(before==var_to_bytes(ids) and var_to_bytes(actual)==var_to_bytes(baseline.find_many(ids)),label_+" exact dictionary order and input unchanged")
	return actual
func road_compare(args:Dictionary,label_:String)->void:
	var f:=Fixture.ordinary();f.layout.roads=Fixture.graph([[[-12.,0.,0.],[12.,0.,0.]]])
	var ctx:=Fixture.context(f);ctx._material_tool.library=library
	var now:=Roads.new();now.editor=ctx;var old:=OldRoads.new();old.editor=ctx
	var state:=var_to_bytes(Fixture.state(ctx))
	var actual:=now.prepare(args)
	ctx._material_tool.library=baseline
	var expected:=old.prepare(args)
	check(var_to_bytes(actual)==var_to_bytes(expected),label_+" complete road success/error bytes match baseline")
	check(state==var_to_bytes(Fixture.state(ctx)),label_+" no author/history mutation")
	check(actual.ok==not ("missing" in args.values() or "texture" in args.values()),label_+" expected success or rejection")
	now.editor=null;old.editor=null;ctx._waterways.editor=null;ctx.free()
func run()->void:
	DirAccess.make_dir_recursive_absolute(Evidence)
	directory=Paths.cache_directory("lookup_targeted_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var manager:=root.get_node("AssetManager");var original:String=manager.content_root_override
	manager.content_root_override=directory
	library=Library.new(directory.path_join("local"));baseline=Baseline.new(library.directory)
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
	var depth_ids:=[".hidden/ignored",deep+"accepted",deep+"i/rejected","../kerb","kerb.json","KERB"]
	var deep_found:=library.find_many(depth_ids)
	check(deep_found.size()==2 and deep_found.has(deep+"accepted") and deep_found.has(deep+"i/rejected"),"deep entries remain visible while hidden and invalid IDs stay excluded")
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
	# Boundary fixture: old listing silently skipped the later directory after
	# 2048 valid rows. All valid IDs must remain available to both consumers.
	library.directory=directory.path_join("cap");baseline.directory=library.directory
	for i in 2046:write(library.directory.path_join("%04d.json"%i),{"material":kerb})
	write(library.directory.path_join("later/hidden.json"),{"material":pavement})
	var uncapped:=library.find_many(["2045","later/hidden","builtin:white"])
	check(uncapped.has("2045") and uncapped.has("later/hidden") and uncapped.has("builtin:white"),"all catalog entries remain visible beyond the old cap")
	await extra_cases()
	manager.content_root_override=original
	var failures:=checks.filter(func(c):return not c.ok).size()
	var file:=FileAccess.open(Evidence+"targeted_tests.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"skipped":skipped,"fixture":directory},"\t"));file.close()
	print("MATERIAL_LOOKUP_TARGETED checks=",checks.size()," failures=",failures);quit(1 if failures else 0)

func extra_cases()->void:
	var bounded:=library._lookup_candidates(["2045","later/hidden"],directory)
	check(bounded.complete and bounded.count==2049 and bounded.paths.size()==2,"targeted lookup covers all candidates beyond the old cap")
	# Many invalid descriptors must not hide a later valid descriptor.
	library.directory=directory.path_join("invalid_cap");baseline.directory=library.directory
	for i in 2046:write(library.directory.path_join("%04d.json"%i),{"material":{"name":"invalid"}})
	write(library.directory.path_join("later/valid.json"),{"material":material()})
	check(compare(["later/valid"],"invalid candidates force exact fallback").has("later/valid"),"invalid rows never consume the actual catalog limit")
	library.directory=directory.path_join("wide");baseline.directory=library.directory
	for i in 257:DirAccess.make_dir_recursive_absolute(library.directory.path_join("d%03d"%i))
	write(library.directory.path_join("d256/valid.json"),{"material":material()})
	check(library._lookup_candidates(["d256/valid"],directory).complete,"targeted lookup completes beyond 256 directories")
	check(compare(["d256/valid"],"wide catalog fallback").has("d256/valid"),"fallback resolves beyond speculative directory budget")
	library.directory=directory.path_join("small");baseline.directory=library.directory
	for i in 25:write(library.directory.path_join("unused_%02d.json"%i),{"material":material("unused")})
	write(library.directory.path_join("chosen.json"),{"material":material("chosen")})
	var narrow:=library._lookup_candidates(["chosen","missing"],directory)
	check(narrow.complete and narrow.count==28 and narrow.paths.size()==1,"native fast path bounds 26 descriptors and only selects the requested one")
	compare(["chosen","missing","builtin:checker"],"native targeted path")
	check(var_to_bytes(library.entries())==var_to_bytes(baseline.entries()),"refactored listing retains all full entry bytes and order")
	# Exercise file links when Windows permits their creation. Directory
	# junction rejection is required and checked separately above.
	var target:=directory.path_join("file_target.json");write(target,{"material":material("target")})
	var leaf:=library.directory.path_join("linked.json")
	var output:Array=[]
	var command:="$ErrorActionPreference='Stop'; New-Item -ItemType SymbolicLink -Path '%s' -Target '%s' | Out-Null"%[leaf.replace("'","''"),target.replace("'","''")]
	var code:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],output,true,false)
	if code==0:
		check(not compare(["linked"],"file symlink").has("linked"),"file symlink cannot become a selected definition")
		DirAccess.remove_absolute(leaf)
	else:
		skipped.append({"case":"file symlink rejection","reason":"Windows fixture creation unavailable","exit_code":code,"output":output})
		print("SKIP file symlink fixture creation unavailable: ",output)
	# Literal IDs are compared with enumerated names; no path is assembled
	# from client input, even for separators, colon-bearing prefixes or NUL.
	compare(["../file_target","chosen/../chosen","chosen\\..\\chosen","C:/chosen","res://chosen","chosen\u0000","","chosen"],"untrusted IDs")
	library.include_shared=true;baseline.include_shared=true
	var local_dir:=library.directory
	var pack:=directory.path_join("packs/default/assets/materials")
	var first_pack:=directory.path_join("default/assets/materials")
	write(first_pack.path_join("duplicate.json"),{"material":{"name":"invalid"}})
	write(pack.path_join("duplicate.json"),{"material":material("later valid")})
	write(directory.path_join("packs/default/metadata.json"),{"id":"default","name":"default"})
	compare(["pack:default:duplicate","chosen"],"duplicate invalid first candidate")
	check(var_to_bytes(library.entries())==var_to_bytes(baseline.entries()),"pack and local listing remain byte-identical")
	# Configuration changes never reuse paths from the previous directory.
	library.directory=directory.path_join("switched");baseline.directory=library.directory
	write(library.directory.path_join("chosen.json"),{"material":material("other directory")})
	check(compare(["chosen"],"directory switch").chosen.name=="other directory","selected directory is evaluated on every request")
	library.directory=local_dir;baseline.directory=local_dir
