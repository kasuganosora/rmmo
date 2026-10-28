extends SceneTree
## A real native streamed product must enter the existing synchronous material
## scope without reconstructing a full Image or reviving an older representation.
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Prefab = preload("res://scripts/world3d/house_prefab.gd")
const Product = preload("res://scripts/world3d/streamed_texture_product.gd")
var output := ""
var checks: Array[Dictionary] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.substr(9)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"pass": ok, "label": label})
	print("PASS " if ok else "FAIL ", label)

func prepared_texture(image: Image, native_path: String, digest: String, representation: String) -> Texture2D:
	var file := FileAccess.open(native_path, FileAccess.WRITE)
	check(Product.write(file, image) == OK, "write native product from already prepared pixels")
	file.close()
	var texture: Texture2D
	if ClassDB.class_exists("StreamedTexture2D"):
		texture = ClassDB.instantiate("StreamedTexture2D")
		check(texture.call("load", native_path) == OK, "load real StreamedTexture2D")
	else:
		texture = ImageTexture.create_from_image(image)
		check(texture != null, "older engine uses existing prepared Texture2D")
	texture.set_meta("runtime_source_sha256", digest)
	texture.set_meta("runtime_texture_representation", representation)
	# Conservative full-chain cache charge, not a dynamic residency measurement.
	texture.set_meta("runtime_upload_bytes", image.get_data_size())
	texture.set_meta("surface_has_alpha", true)
	texture.set_meta("runtime_normal_xy", false)
	return texture

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	Paint.refresh_sources()
	Paint.texture_profile_enabled = true
	Paint.TextureCache.profile_enabled = true
	Paint.compressed_sidecars_enabled = false
	var folder := output.get_base_dir()
	var path := folder.path_join("source.png")
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(.1, .6, .3, .5))
	check(image.save_png(path) == OK, "create isolated source image")
	image.generate_mipmaps()
	var digest := FileAccess.get_sha256(path)
	var first := prepared_texture(image, folder.path_join("first.stex"), digest, "stex:first")
	var next := prepared_texture(image, folder.path_join("next.stex"), digest, "stex:next")
	var definition := {"name": "texture-only", "color": [1.,1.,1.,1.], "roughness": .8, "texture_path": path}
	var packet := {"images": {}, "uploaded_textures": {path: first}, "sources": {path: digest}}
	var record := {"house_prefab": {"sha256": "fixture"}}
	var state: Dictionary = {}
	var pool: Dictionary = {}
	Paint.reset_profile()
	var scope := Prefab.begin_texture_publication(record, pool, packet, state)
	check(scope.ok, "texture-only packet enters publication scope")
	var material := Paint.make_material(definition)
	Prefab.end_texture_publication(scope)
	check(material.albedo_texture == first, "first material binds the supplied texture RID")
	check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "prepared alpha metadata survives without CPU Image")
	check(Paint.prepared_images.is_empty() and Paint.prepared_textures.is_empty(), "both borrowed scopes close")
	var counters: Dictionary = Paint.TextureCache.profile_snapshot("").counters
	check(counters.get("paint.texture.runtime_image_lookup", 0) == 0 and counters.get("paint.texture.upload_bytes", 0) == 0,
		"texture-only handoff performs no source Image lookup or duplicate upload")
	# Leave only a per-load material owner, then switch representation without
	# changing the source digest. A digest-only fast path must not revive it.
	pool["held"] = material
	Paint._textures.clear(); Paint._texture_refs.clear()
	packet.uploaded_textures = {path: next}
	scope = Prefab.begin_texture_publication(record, pool, packet, state)
	check(pool.is_empty(), "changed representation invalidates the caller material pool")
	var newer := Paint.make_material(definition)
	Prefab.end_texture_publication(scope)
	check(newer.albedo_texture == next and material.albedo_texture == first, "new representation replaces cache aliases, preserving visible old owner")
	for iteration in 100:
		scope = Prefab.begin_texture_publication(record, pool, packet, state)
		var repeated := Paint.make_material(definition)
		if iteration == 99: check(repeated == newer, "repeat slice retains the same material")
		Prefab.end_texture_publication(scope)
	check(state.initializations == 2 and state.get("reuses", 0) == 100, "100 unchanged slices do not repeat invalidation")
	var outer_images := {path: image}
	var outer_textures := {path: first}
	Paint.prepared_images = outer_images
	Paint.prepared_textures = outer_textures
	Paint.cache_byte_budget = 0
	Paint.trim_cached_resources()
	scope = Prefab.begin_texture_publication(record, pool, packet)
	check(Paint.texture(definition) == next, "zero hot cache and nested outer Image still use the exact inner texture")
	Prefab.end_texture_publication(scope)
	check(is_same(Paint.prepared_images, outer_images) and is_same(Paint.prepared_textures, outer_textures), "nested publication restores exact outer dictionary owners")
	Paint.prepared_images = {}; Paint.prepared_textures = {}
	var failed := checks.filter(func(row: Dictionary): return not row["pass"]).size()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed, "scope_state": state,
		"profile": Paint.TextureCache.profile_snapshot(""), "engine": Engine.get_version_info()}, "\t"))
	file.close()
	quit(0 if failed == 0 else 1)
