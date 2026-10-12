extends SceneTree
const Estimate = preload("res://scripts/world3d/asset_memory_estimate.gd")
var passed := 0
var failures := 0
var directory := ""
var created: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ",label)
	if ok: passed += 1
	else: failures += 1

func data() -> Dictionary:
	return {"asset":{"version":"2.0"},"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],
		"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}],"bufferViews":[{"buffer":0,"byteLength":36}],"buffers":[{"byteLength":36}]}

func put_be(bytes: PackedByteArray, at: int, value: int) -> void:
	for i in 4: bytes[at+i] = (value >> ((3-i)*8)) & 255

func png(width: int, height: int, bits: int = 8) -> PackedByteArray:
	# Deliberately header-only: this test cannot succeed by decoding the image.
	var bytes := PackedByteArray([137,80,78,71,13,10,26,10]); bytes.resize(33)
	put_be(bytes,8,13)
	for i in 4: bytes[12+i] = "IHDR".to_ascii_buffer()[i]
	put_be(bytes,16,width); put_be(bytes,20,height); bytes[24] = bits; bytes[25] = 6
	return bytes

func jpeg(width: int, height: int) -> PackedByteArray:
	# APP metadata followed by progressive SOF2, again without image scan data.
	return PackedByteArray([255,216,255,224,0,6,1,2,3,4,255,194,0,17,8,(height>>8)&255,height&255,(width>>8)&255,width&255,3,1,17,0,2,17,0,3,17,0,255,217])

func write(name: String, raw: Dictionary, image: PackedByteArray = PackedByteArray(), mime: String = "image/png") -> String:
	var value := raw.duplicate(true)
	var payload := PackedByteArray(); payload.resize(36)
	if not image.is_empty():
		value.bufferViews.append({"buffer":0,"byteOffset":36,"byteLength":image.size()})
		value.images=[{"bufferView":value.bufferViews.size()-1,"mimeType":mime}]
		payload.append_array(image)
	value.buffers[0].byteLength=payload.size()
	while payload.size()%4: payload.append(0)
	var bytes := JSON.stringify(value).to_utf8_buffer()
	while bytes.size()%4: bytes.append(32)
	var path := directory.path_join(name)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67); file.store_32(2); file.store_32(28+bytes.size()+payload.size())
	file.store_32(bytes.size()); file.store_32(0x4e4f534a); file.store_buffer(bytes)
	file.store_32(payload.size()); file.store_32(0x004e4942); file.store_buffer(payload); file.close()
	if path not in created: created.append(path)
	return path

func unknown(path: String, label: String) -> void:
	var result := Estimate.estimate(path)
	check(not result.known and result.exclusive and result.estimated_bytes >= Estimate.UNKNOWN_BYTES,label)

func run() -> void:
	directory = ProjectSettings.globalize_path("user://asset_memory_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var path := write("plain.glb",data())
	var plain := Estimate.estimate(path)
	check(plain.known and not plain.exclusive and plain.source_bytes == FileAccess.open(path,FileAccess.READ).get_length(),"small embedded mesh is bounded and records actual source size")
	check(plain.mesh_bytes >= 36 and plain.collision_bytes >= 36 and plain.estimated_bytes == plain.source_bytes*2+plain.decoded_bytes+plain.output_bytes+plain.overhead_bytes,"estimate accounts for decoded geometry, collision, source and output")
	var image_path := write("png.glb",data(),png(1024,512))
	var image := Estimate.estimate(image_path)
	check(image.known and image.texture_bytes == 2796204 and image.estimated_bytes > plain.estimated_bytes + 8*1024*1024-100,"PNG header reserves exact full mip chain and three texture copies")
	var stages:=Estimate.stage_profile(image)
	check(stages.compiled_read_reservation_bytes==image.estimated_bytes and stages.raw_import_reservation_bytes==image.estimated_bytes and stages.retained_result_charge_bytes==image.estimated_bytes,"compiled/native stage labels never discount decode/upload reservation")
	check(not stages.source_identity_verified and not stages.loading_eligible and stages.components_overlap,"memory stages are neither source validation nor additive independent memory measurements")
	stages.components.texture_bytes=1
	check(image.texture_bytes==2796204,"stage diagnostics do not mutate source estimate")
	check(Estimate.stage_profile({}).exclusive and Estimate.stage_profile({}).estimated_bytes>=Estimate.UNKNOWN_BYTES,"missing stage estimate remains conservative and exclusive")
	var high_depth := Estimate.estimate(write("png16.glb",data(),png(1024,512,16)))
	check(high_depth.known and high_depth.texture_bytes == image.texture_bytes*2,"16 bit PNG reserves twice the RGBA8 storage")
	var photo := Estimate.estimate(write("jpeg.glb",data(),jpeg(1024,512),"image/jpeg"))
	check(photo.known and photo.texture_bytes == image.texture_bytes,"JPEG progressive SOF dimensions found after APP segment")
	var huge := Estimate.estimate(write("large.glb",data(),png(32768,32768)))
	check(huge.known and huge.exclusive and huge.estimated_bytes > 16*1024*1024*1024,"tiny compressed/header file with huge decoded image is exclusive")
	unknown(write("zero.glb",data(),png(0,32)),"zero image dimension is unknown and exclusive")
	unknown(write("overflow.glb",data(),png(4294967295,32)),"oversized dimensions cannot overflow estimates")
	unknown(write("depth.glb",data(),png(8,8,3)),"unsupported PNG header is conservative")
	var broken_jpeg := jpeg(32,32); broken_jpeg[4]=255;broken_jpeg[5]=255
	unknown(write("jpeg_range.glb",data(),broken_jpeg,"image/jpeg"),"JPEG segment cannot read past its bufferView")
	unknown(write("jpeg_no_sof.glb",data(),PackedByteArray([255,216,255,217,0,0,0,0]),"image/jpeg"),"JPEG without SOF is conservative")
	unknown(write("wrong_mime.glb",data(),png(32,32),"image/webp"),"unknown image encodings remain exclusive")
	for mutation in ["uri","view_offset","view_length","fraction","huge_count","sparse","unknown_extension","morph","animation","bad_indices","attribute_count","skin","native"]:
		var changed := data()
		match mutation:
			"uri": changed.buffers[0].uri="elsewhere.bin"
			"view_offset": changed.bufferViews[0].byteOffset=4294967295
			"view_length": changed.bufferViews[0].byteLength=4294967295
			"fraction": changed.accessors[0].byteOffset=0.5
			"huge_count": changed.accessors[0].count=4294967295
			"sparse": changed.accessors[0].sparse={}
			"unknown_extension": changed.meshes[0].primitives[0].extensions={"KHR_draco_mesh_compression":{}}
			"morph": changed.meshes[0].primitives[0].targets=[]
			"animation": changed.animations=[{}]
			"bad_indices": changed.meshes[0].primitives[0].indices=0
			"attribute_count":
				changed.accessors.append({"bufferView":0,"componentType":5126,"count":2,"type":"VEC3"});changed.meshes[0].primitives[0].attributes.NORMAL=1
			"skin": changed.skins=[{}]
			"native": changed.nodes[0].extras={"rmmo_format":"rmmo_gltf_map"}
		unknown(write(mutation+".glb",changed),"malformed or unbounded model: "+mutation)
	var material := data(); material.materials=[{"extensions":{"KHR_materials_transmission":{"transmissionFactor":0.5}}}]
	check(Estimate.estimate(write("material.glb",material)).known,"familiar material metadata does not disable capacity estimates")
	for extension in ["KHR_materials_clearcoat","KHR_materials_ior"]:
		material=data();material.materials=[{"extensions":{extension:{}}}];material.extensionsUsed=[extension]
		check(Estimate.estimate(write(extension+".glb",material)).known,"bounded material-only extension: "+extension)
	var length_path := write("bad_length.glb",data())
	var file := FileAccess.open(length_path,FileAccess.READ_WRITE);file.seek(12);file.store_32(Estimate.MAX_JSON+4);file.close()
	unknown(length_path,"declared JSON length is bounded before reading")
	var short_path := directory.path_join("short.glb");created.append(short_path)
	file=FileAccess.open(short_path,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
	unknown(short_path,"short container is conservative")
	unknown(directory.path_join("missing.glb"),"missing source is exclusive")
	var first_size: int = image.estimated_bytes
	write("png.glb",data(),png(32,32))
	check(Estimate.estimate(image_path).estimated_bytes < first_size,"source replacement does not reuse an estimate cached by path")
	var workers: Array[Thread] = []
	for i in 4:
		var worker := Thread.new()
		check(worker.start(Callable(Estimate,"estimate").bind(path))==OK,"CPU estimator worker starts "+str(i))
		workers.append(worker)
	for worker: Thread in workers:
		check(worker.wait_to_finish()==plain,"concurrent estimates own handles and return identical values")
	for created_path: String in created: DirAccess.remove_absolute(created_path)
	DirAccess.remove_absolute(directory)
	print("ASSET_MEMORY_ESTIMATE passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
