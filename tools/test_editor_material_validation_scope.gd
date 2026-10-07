extends SceneTree
const Ops=preload("res://scripts/world_editor/mcp_ops.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label_: String) -> void:
	print("PASS: " if value else "FAIL: ",label_)
	if not value: failed+=1
func run() -> void:
	var directory:=Paths.cache_directory("editor_validation_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("test.png")
	var image:=Image.create(1,1,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE); image.save_png(path)
	var material:={"name":"shared","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":path,"normal_path":path}
	var paint:={"mesh":"","geometry":"box-v1","surface":0,"face":0,"scale":[1.,1.],"offset":[0.,0.],"rotation":0.,"mapping":"uv","material":material}
	var record:={"uuid":"first","kind":"box","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[2.,2.,2.],"surface_id":"block","surface_paint":[paint]}
	var repeated: Array=[]
	for i in 128:
		var copy: Dictionary=record.duplicate(true); copy.uuid="record_%d"%i; repeated.append(copy)
	var ops:=Ops.new()
	var before: Array=repeated.duplicate(true)
	check(ops.validate_assets(repeated).is_empty() and repeated==before,"repeated valid materials pass without record mutations")
	var bad: Dictionary=record.duplicate(true); bad.surface_paint[0].material.roughness=2.
	check(not ops.validate_assets([record,bad]).is_empty(),"invalid definition after valid cache entry is rejected")
	bad=record.duplicate(true); bad.surface_paint[0].offset=[101.,0.]
	check(not ops.validate_assets([record,bad]).is_empty(),"paint parameters are part of cache identity")
	bad=record.duplicate(true); bad.surface_paint[0].material.texture_path="D:/outside_allowed_root.png"
	check(not ops.validate_assets([record,bad]).is_empty(),"escaping texture after valid material is rejected")
	bad=record.duplicate(true); bad.surface_paint[0].material.texture_path=directory.path_join("invalid.exe")
	check(not ops.validate_assets([record,bad]).is_empty(),"invalid texture extension is rejected")
	var alpha: Dictionary=record.duplicate(true); alpha.surface_paint[0].material.color[3]=.5
	bad=alpha.duplicate(true); bad.bank_wetness={"water_level":0.,"wet_height":1.}
	check(ops.validate_assets([alpha]).is_empty() and not ops.validate_assets([alpha,bad]).is_empty(),"bank opacity constraint survives identical paint cache content")
	# Root permission changes between calls must not reuse successful definitions.
	var manager=root.get_node("AssetManager"); var prior: String=manager.content_root_override
	var other:=directory.path_join("other_root"); DirAccess.make_dir_recursive_absolute(other)
	manager.content_root_override=other
	var restricted: String=ops.validate_assets(repeated)
	manager.content_root_override=prior
	check(not restricted.is_empty() and ops.validate_assets(repeated).is_empty(),"same Ops instance rechecks resource root on every validation")
	check(Paint.texture(material)!=null,"fixture texture loads before removal")
	DirAccess.remove_absolute(path)
	check(ops.validate_assets(repeated).is_empty() and Paint.valid(record),"missing file retains existing schema-only validation semantics")
	check(Paint.texture(material)==null,"deleted texture is still rejected by texture loading despite its texture cache")
	image.save_png(path)
	bad=record.duplicate(true); bad.surface_paint[0].material.normal_format="invalid"
	check(not ops.validate_assets([bad]).is_empty() and ops.validate_assets([record]).is_empty(),"invalid subsequent edit is rejected and later repair revalidates")
	var raw:={"nodes":[{"extras":{"rmmo_records":[record]}},{"extras":{"rmmo_records":[bad]}}]}
	check(not ops.validate_map_data(directory.path_join("map.gltf"),raw).is_empty(),"invalid material in later glTF node is not hidden by previous validation")
	var start:=Time.get_ticks_usec()
	for value in repeated: Paint.valid(value)
	var uncached:=Time.get_ticks_usec()-start
	var cache: Dictionary={}; start=Time.get_ticks_usec()
	for value in repeated: Paint.valid(value,false,"",cache)
	print("PAINT_VALIDATION_128_MS uncached=",uncached/1000.," cached=",(Time.get_ticks_usec()-start)/1000.," entries=",cache.size())
	print("EDITOR_MATERIAL_VALIDATION_FAILED=",failed); quit(1 if failed else 0)
