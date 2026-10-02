extends RefCounted
## MIT Godot demo noise volumes. External pack, loaded once and shared across worlds.
const Art = preload("res://scripts/asset/art_paths.gd")
static var textures: Array[ImageTexture3D] = []
static var attempted := false

static func bind(material: ShaderMaterial) -> bool:
	if not attempted:
		attempted = true
		for entry in [["perlworlnoise.png",128],["worlnoise.webp",32]]:
			var path := Art.path("weather/clouds/"+str(entry[0]))
			var atlas := Image.load_from_file(path) if FileAccess.file_exists(path) else null
			var size: int = entry[1]
			if atlas == null or atlas.get_width()!=size*size or atlas.get_height()!=size:
				push_warning("Cloud noise unavailable; using layer clouds. Run tools/install_cloud_assets.py with the external content root.")
				textures.clear(); return false
			atlas.convert(Image.FORMAT_RGBA8)
			var slices: Array[Image] = []
			for z in size: slices.append(atlas.get_region(Rect2i(z*size,0,size,size)))
			var volume := ImageTexture3D.new()
			if volume.create(Image.FORMAT_RGBA8,size,size,size,false,slices)!=OK:
				textures.clear(); return false
			textures.append(volume)
	if textures.size()!=2: return false
	material.set_shader_parameter("cloud_base_noise",textures[0])
	material.set_shader_parameter("cloud_detail_noise",textures[1])
	return true

static func seed_offset(seed: int) -> Vector3:
	# Integer arithmetic keeps all 31 server seed bits; no float seed truncation.
	var state := seed
	var out := Vector3.ZERO
	for axis in 3:
		state = ((state^(state>>16))*1103515245+12345)&2147483647
		out[axis] = float(state%65536)/65536.
	return out
