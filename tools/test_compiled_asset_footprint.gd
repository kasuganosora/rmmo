extends SceneTree
## Pure CPU: synthetic compression envelopes and Image data; no texture/mesh RID.
const Footprint = preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
var passed := 0
var failures := 0
var created: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	print("PASS: " if condition else "FAIL: ", label)
	if condition: passed += 1
	else: failures += 1

func put(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
	if path not in created: created.append(path)

func text_file(path: String, value: Variant) -> void: put(path, JSON.stringify(value).to_utf8_buffer())

func run() -> void:
	var folder := ProjectSettings.globalize_path("user://footprint_cpu_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var source := folder.path_join("assets/example.glb")
	put(source, PackedByteArray([1,2,3,4]))
	var stats := Footprint.empty_stats()
	stats.nodes = 1; stats.native_uncompressed_bytes = 1
	var small := Footprint.estimate_stats(stats)
	check(small.estimated_bytes > Footprint.FLOOR_BYTES and small.resident_bytes == small.estimated_bytes and not small.exclusive, "floor and full resident charge survive empty geometry")
	check(Footprint.estimate_stats({}).is_empty(), "missing accounting falls back rather than granting a discounted budget")
	var negative := stats.duplicate(); negative.image_mip_bytes = -1
	check(Footprint.estimate_stats(negative).is_empty(), "negative accounting is rejected")
	var fraction := stats.duplicate(); fraction.mesh_capture_bytes = 1.5
	check(Footprint.estimate_stats(fraction).is_empty(), "fractional JSON accounting is rejected")
	var overflow := stats.duplicate(); overflow.gpu_rgba_bytes = Footprint.MAX_BYTES
	check(Footprint.estimate_stats(overflow).is_empty(), "oversized arithmetic cannot wrap into a small reservation")
	var image := Image.create(16, 8, false, Image.FORMAT_RGB8)
	var image_size := Footprint.image_footprint(image)
	check(image_size.image_mip_bytes == 16 * 8 * 3 and image_size.gpu_rgba_bytes == (128+32+8+2+1)*4, "RGB8 reserves RGBA8 expansion and full mip chain")
	image.generate_mipmaps()
	check(Footprint.image_footprint(image).image_mip_bytes == image.get_data().size(), "stored mip byte count includes every level")
	var hdr := Image.create(4, 4, false, Image.FORMAT_RGBAF)
	check(Footprint.image_footprint(hdr).gpu_rgba_bytes == (16+4+1)*16, "HDR reserves full RGBA32F mip footprint")
	check(Footprint.image_footprint(Image.new()).is_empty(), "empty image leaves estimate unknown")
	var rich := stats.duplicate()
	rich.image_mip_bytes = 200000000; rich.gpu_rgba_bytes = 1000000000
	rich.mesh_storage_bytes = 1000000; rich.mesh_capture_bytes = 2000000; rich.collision_face_bytes = 3000000
	var rich_estimate := Footprint.estimate_stats(rich)
	check(rich_estimate.estimated_bytes >= 3660000000 and rich_estimate.resident_bytes == rich_estimate.estimated_bytes, "peak separately charges decoded images, upload and collision capture")
	rich.gpu_rgba_bytes = 2000000000
	check(Footprint.estimate_stats(rich).exclusive, "large native output remains an exclusive task")
	var context := {"ok":true, "seen":{}, "retained":[], "visits":0}
	var unique := Footprint.empty_stats()
	Footprint._walk([image, image, {"again":image}], unique, context, 0, false)
	check(context.ok and unique.images == 1 and unique.resources == 1 and unique.image_mip_bytes == image.get_data().size(), "shared Image resources count once across references")
	var unknown_context := {"ok":true, "seen":{}, "retained":[], "visits":0}
	Footprint._walk(Resource.new(), Footprint.empty_stats(), unknown_context, 0, false)
	check(not unknown_context.ok, "unsupported resource cannot receive a native discount")
	check(Footprint._packed_bytes(PackedVector3Array([Vector3.ZERO, Vector3.ONE])) == 24, "mesh packed vectors use exact component storage")
	var compression := folder.path_join("compressed.scn")
	# A structurally valid RSCC table; no decompression/deserialization is done.
	var bytes := PackedByteArray(); bytes.resize(29)
	bytes[0]=82; bytes[1]=83; bytes[2]=67; bytes[3]=67
	bytes.encode_u32(4, 2); bytes.encode_u32(8, 4096); bytes.encode_u32(12, 128); bytes.encode_u32(16, 5)
	bytes[25]=82; bytes[26]=83; bytes[27]=67; bytes[28]=67
	put(compression, bytes)
	check(Footprint.native_uncompressed_bytes(compression) == 128, "RSCC reads actual uncompressed size independently of compressed length")
	var corrupt := bytes.duplicate(); corrupt.encode_u32(8, 0); put(compression, corrupt)
	check(Footprint.native_uncompressed_bytes(compression) == 0, "zero compression block rejected without division")
	corrupt = bytes.duplicate(); corrupt.encode_u32(16, 5000); put(compression, corrupt)
	check(Footprint.native_uncompressed_bytes(compression) == 0, "compression block table cannot overrun payload")
	corrupt = bytes.duplicate(); corrupt[28]=0; put(compression, corrupt)
	check(Footprint.native_uncompressed_bytes(compression) == 0, "trailing compression magic is required")
	var source_sha := FileAccess.get_sha256(source)
	var payload_sha := bytes.hex_encode().sha256_text()
	var payload := Compiled.directory(folder).path_join(payload_sha + ".scn")
	put(payload, bytes)
	var manifest := {"version":Compiled.VERSION, "generator":Compiled.generator(), "source_sha":source_sha, "payload_sha":payload_sha, "bytes":bytes.size()}
	var index := Compiled.index_path(source, folder); text_file(index, manifest)
	check(Footprint.candidate(source, folder).is_empty(), "absent sidecar preserves previous estimator")
	var descriptor := {"version":Footprint.VERSION, "footprint_generator":Footprint.generator(), "source_path":source, "source_sha":source_sha, "payload_sha":payload_sha, "generator":manifest.generator, "bytes":bytes.size(), "source_bytes":4, "stats":stats, "estimated_bytes":small.estimated_bytes, "resident_bytes":small.resident_bytes}
	var destination := Footprint.descriptor_path(source, folder)
	write_descriptor(destination, descriptor)
	var candidate := Footprint.candidate(source, folder, source_sha)
	check(not candidate.is_empty() and candidate.product == payload and candidate.estimated_bytes == small.estimated_bytes, "matching descriptor freezes manifest and product identity")
	check(not candidate.has("loading_eligible") and not candidate.has("source_identity_verified"), "candidate does not grant trust or pretend to hash the source")
	check(Footprint.candidate(source, folder, "bad").is_empty() and Footprint.candidate(source, folder, "0".repeat(64)).is_empty(), "expected digest must be valid and match generation")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(destination)); envelope.body += " "
	text_file(destination, envelope)
	check(Footprint.candidate(source, folder).is_empty(), "sidecar content damage fails checksum")
	write_descriptor(destination, descriptor)
	manifest.source_sha = "f".repeat(64); text_file(index, manifest)
	check(Footprint.candidate(source, folder).is_empty(), "source manifest replacement invalidates existing footprint")
	manifest.source_sha = source_sha; manifest.generator = "0".repeat(64); text_file(index, manifest)
	check(Footprint.candidate(source, folder).is_empty(), "native generator replacement invalidates existing footprint")
	manifest.generator = Compiled.generator(); text_file(index, manifest)
	var undercharge := descriptor.duplicate(true); undercharge.estimated_bytes = 1
	write_descriptor(destination, undercharge)
	check(Footprint.candidate(source, folder).is_empty(), "recomputed formula rejects a checksum-valid undercharge")
	write_descriptor(destination, descriptor)
	put(payload, PackedByteArray([1]))
	check(Footprint.candidate(source, folder).is_empty(), "product size change rejects frozen candidate")
	put(payload, bytes); put(source, PackedByteArray([1,2,3,4,5]))
	check(Footprint.candidate(source, folder).is_empty(), "source length change is an early miss in addition to final consumer SHA")
	put(source, PackedByteArray([9,8,7,6]))
	check(not Footprint.candidate(source, folder).is_empty() and FileAccess.get_sha256(source) != candidate.source_sha, "same-size replacement remains only a candidate; final complete SHA is mandatory")
	check(Footprint._publish(descriptor, folder.path_join("outside.json"), folder) == ERR_FILE_BAD_PATH, "descriptor writer cannot leave derived cache")
	for path in created: DirAccess.remove_absolute(path)
	print("COMPILED_ASSET_FOOTPRINT passed=", passed, " failures=", failures)
	quit(0 if failures == 0 else 1)

func write_descriptor(path: String, descriptor: Dictionary) -> void:
	var body := JSON.stringify(descriptor)
	text_file(path, {"version":Footprint.VERSION, "body":body, "sha256":body.sha256_text()})
