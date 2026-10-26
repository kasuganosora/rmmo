extends SceneTree
## Intentional native decode errors, followed by retry into the SAME placeholder.
## Fixed Vulkan container fixtures only; no production cache files are modified.
var checks:=0
var failures:Array[String]=[]
var output:=""

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func run()->void:
	var rd:=RenderingServer.get_rendering_device()
	check(rd!=null and not output.is_empty(),"GPU RenderingDevice and external output provided")
	if not failures.is_empty():quit(1);return
	var source:=RDShaderSource.new()
	source.source_vertex="#version 450\nlayout(location=0) in vec3 vertex;\nlayout(constant_id=0) const float scale=1.0;\nvoid main(){gl_Position=vec4(vertex*scale,1.0);}\n"
	source.source_fragment="#version 450\nlayout(location=0) out vec4 color;\nvoid main(){color=vec4(1.0,0.0,0.0,1.0);}\n"
	var spirv:=rd.shader_compile_spirv_from_source(source)
	check(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_VERTEX).is_empty(),"vertex source compiles")
	check(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_FRAGMENT).is_empty(),"fragment source compiles")
	var binary:=rd.shader_compile_binary_from_spirv(spirv,"RmmoPreparationFailure")
	check(binary.size()>100 and binary.decode_u32(16)==2,"fixture has two serialized stages")
	if not failures.is_empty():quit(1);return
	# ShaderHeader is four uint32 fields in this Vulkan container version. Locate
	# the FINAL fragment header by its exact end alignment instead of assuming
	# reflection struct padding. Reject an ambiguous layout before any mutation.
	var offsets:Array[int]=[]
	for offset in range(20,binary.size()-16,4):
		if binary.decode_u32(offset)!=RenderingDevice.SHADER_STAGE_FRAGMENT:continue
		var size:=binary.decode_u32(offset+4)
		var flags:=binary.decode_u32(offset+8)
		if size>=16 and ((offset+16+size+3)&~3)==binary.size() and (flags&0x10000)!=0:offsets.append(offset)
	check(offsets.size()==1,"unique final fragment header located")
	if not failures.is_empty():quit(1);return
	var original_hash:=binary.hex_encode().sha256_text()
	var corrupt:=binary.duplicate()
	corrupt.encode_u32(offsets[0]+8,0x10000) # SMOL-V, without outer ZSTD.
	corrupt.encode_u32(offsets[0]+12,0) # Deliberately decode the invalid inner header directly.
	corrupt.encode_u32(offsets[0]+16,0) # Invalid SMOL-V magic; no invalid data reaches Vulkan.
	var expected_errors:=0
	var recovered:=0
	for i in 4:
		var placeholder:=rd.shader_create_placeholder()
		var failed:=rd.shader_create_from_bytecode(corrupt,placeholder)
		expected_errors+=1
		check(not failed.is_valid(),"partial CPU preparation fails without publishing a RID")
		check(not rd.uniform_set_is_valid(RID()),"RD remains responsive after failure")
		var retried:=rd.shader_create_from_bytecode(binary,placeholder)
		check(retried==placeholder and retried.is_valid(),"valid retry preserves original placeholder identity")
		if retried.is_valid():recovered+=1
		rd.free_rid(placeholder)
	check(binary.hex_encode().sha256_text()==original_hash,"corruption fixture never mutates shared valid input")
	RenderingServer.force_sync()
	for i in 3:await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"expected_decode_errors":expected_errors,"recovered":recovered,"input_sha256":original_hash,"corrupt_header_offset":offsets[0]}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SHADER_PREPARATION_FAILURE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
