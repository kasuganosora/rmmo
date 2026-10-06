extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var sources:Variant=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/town_props_20261006/manifest.json"))
	if not sources is Array:quit(1);return
	var verification:Variant=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/town_props_20261006/validation.json"))
	if not verification is Dictionary or verification.get("failures",-1)!=0 or verification.get("assets",[]).size()!=sources.size():
		push_error("Complete passing runtime validation is required before publication");quit(1);return
	var library:=Library.new(BASE+"/packs/default/assets")
	var doc:=Doc.new();var published:Array=[]
	var floor_id:=doc.add_box("ground",Vector3(0,-.15,0),Vector3(70,.3,70))
	doc._find(floor_id).label="街景道具展示地面"
	for i in sources.size():
		var spec:Dictionary=sources[i];var label:=label_for(spec.id)
		var validated:Array=verification.assets.filter(func(r):return r.id==spec.id)
		if validated.size()!=1:quit(1);return
		var entry:Dictionary=validated[0].entry.duplicate(true)
		var verified_source:String=entry.asset_path
		var hash:=FileAccess.get_sha256(verified_source)
		if hash!=verified_source.get_file().get_basename():push_error("Validated immutable asset changed");quit(1);return
		var target:=library.directory.path_join(hash+".glb")
		if not FileAccess.file_exists(target) and DirAccess.copy_absolute(verified_source,target)!=OK:quit(1);return
		if FileAccess.get_sha256(target)!=hash:quit(1);return
		entry.asset_path=target;entry.thumbnail_path=library.directory.path_join("thumbnails/"+hash+".png")
		entry.label=label;entry.category="街景道具·20261006"
		if not library.entries.any(func(e):return e.get("asset_path","")==target):library.entries.append(entry)
		if library.save()!=OK:quit(1);return
		var source:=Doc.new();var id:=source.add_asset(entry,Vector3.ZERO)
		if spec.id.ends_with("bunting"):source._find(id).collision="none"
		library.entries=library.entries.filter(func(e):return not (e.get("label","")==label and e.has("prefab_path")))
		var prefab:=Prefabs.capture(source.records,library,label)
		if not prefab.ok:push_error(str(prefab));quit(1);return
		library.entries=library.entries.filter(func(e):return not (e.get("asset_path","")==entry.asset_path and e.get("label","")==label))
		if library.save()!=OK:quit(1);return
		var at:=Vector3((i%6-2.5)*8,0,(i/6-2)*8)
		var placed:=Prefabs.place(doc,prefab.entry,at)
		if not placed.ok:push_error(str(placed));quit(1);return
		published.append({"id":spec.id,"label":label,"entry":prefab.entry,"position":[at.x,at.y,at.z],"source_sha256":FileAccess.get_sha256(spec.file)})
	var folder:=BASE+"/maps/town_props_showcase_20261006"
	DirAccess.make_dir_recursive_absolute(folder)
	var metadata:=FileAccess.open(folder+"/metadata.json",FileAccess.WRITE);metadata.store_string(JSON.stringify({"id":"town_props_showcase_20261006","name":"写实街景道具展示"}));metadata.close()
	var path:=folder+"/map.gltf"
	# Dedicated asset showcase; never replace a pre-existing user-edited map.
	if FileAccess.file_exists(path):push_error("Showcase already exists; preserve it");quit(1);return
	if doc.save(path)!=OK:push_error("Showcase save failed");quit(1);return
	var reopened=Doc.open_file(path)
	if reopened==null or not reopened.missing_assets().is_empty():push_error("Showcase reopen failed");quit(1);return
	var report:={"count":published.size(),"items":published,"showcase":path,"town_map_modified":false,"reopened_records":reopened.records.size()}
	DirAccess.make_dir_recursive_absolute(BASE+"/review_artifacts/town_props_20261006")
	var f:=FileAccess.open(BASE+"/review_artifacts/town_props_20261006/published.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("TOWN_PROPS_PUBLISHED ",published.size());quit()
func label_for(id:String)->String:
	var labels={"01_wall_hedge":"浅石长花池","02_window_flowers":"窗下花池","03_corner_garden":"浅石L形花池","04_octagon_flowers":"八角花池","05_brick_leaf_border":"暖砖长花池","06_brick_leaf_corner":"暖砖L形花池","07_tall_hedge_corner":"高款L形花池","08_tall_plant_straight":"高灌木长花池","09_tall_plant_corner":"高灌木L形花池","01_short_straight":"短木围挡","02_long_straight":"长木围挡","03_corner":"L形木围挡","POST_blue":"蓝色金丝带彩柱","POST_red":"红色金丝带彩柱","POST_natural":"原木金丝带彩柱","bunting":"跨街布彩旗","01_blue_grey_vendor":"空货台布棚","02_plum_vendor":"陶器摊棚","03_potion_vendor":"魔法药水摊棚","04_scroll_vendor":"卷轴摊棚","05_ore_vendor":"矿石摊棚","02_rock_bank_3m":"自然岩岸段","03_river_boulder_large":"河岸大石","04_river_boulder_small":"河岸小石","08_low_garden_wall":"低矮院墙","09_garden_gate_pier":"院门石柱","10_laundry_line":"晾衣绳架","12_natural_boxwood_shrub":"写实黄杨灌木","13_shoulder_pole_and_bundle":"搬运杆与布包","small_wall_lantern":"门旁暖光小壁灯"}
	for key in labels:
		if id.ends_with(key):return labels[key]
	return id
