extends RefCounted
## Display textures stay on the main device; no per-frame render-queue wait.
var rd:RenderingDevice
var resources:Array[RID]=[]
var buffers:Array[RID]=[]
var pipeline:RID
var uniform_set:RID
var positions:=Texture2DRD.new()
var normals:=Texture2DRD.new()
var ready:=false
var submitted_bytes:=PackedByteArray()
func initialize(folder:String)->bool:
 RenderingServer.call_on_render_thread(_initialize_gpu.bind(folder));RenderingServer.force_sync()
 return ready
func _initialize_gpu(folder:String)->void:
 rd=RenderingServer.get_rendering_device()
 if rd==null:return
 var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://scripts/char/female_axis_display.glsl").replace("#[compute]","")
 var spirv:=rd.shader_compile_spirv_from_source(source)
 if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);return
 var shader:=rd.shader_create_from_spirv(spirv);resources.append(shader)
 pipeline=rd.compute_pipeline_create(shader);resources.append(pipeline)
 var points:=PackedByteArray();points.resize(21556*12)
 var data:Array[PackedByteArray]=[points,FileAccess.get_file_as_bytes(folder+"/axis_gpu_adjacency.bin"),FileAccess.get_file_as_bytes(folder+"/axis_gpu_triangles.bin")]
 var uniforms:Array[RDUniform]=[]
 for i in 3:
  var rid:=rd.storage_buffer_create(data[i].size(),data[i]);buffers.append(rid);resources.append(rid)
  var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(rid);uniforms.append(u)
 var format:=RDTextureFormat.new();format.width=512;format.height=43;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
 format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
 var zero:=PackedByteArray();zero.resize(512*43*16)
 for i in 2:
  var rid:=rd.texture_create(format,RDTextureView.new(),[zero]);resources.append(rid)
  (positions if i==0 else normals).texture_rd_rid=rid
  var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.binding=i+3;u.add_id(rid);uniforms.append(u)
 uniform_set=rd.uniform_set_create(uniforms,shader,0);resources.append(uniform_set);ready=true
func shared_points_buffer(points:PackedVector3Array)->RID:
 # Compare with the exact upload bytes, not a caller-owned mutable array.
 if not ready or points.to_byte_array()!=submitted_bytes:return RID()
 return buffers[0]
func update(points:PackedVector3Array,offset:Vector3)->void:
 submitted_bytes=points.to_byte_array()
 RenderingServer.call_on_render_thread(_update_gpu.bind(submitted_bytes,offset,rd,buffers[0],pipeline,uniform_set))
func _update_gpu(points:PackedByteArray,offset:Vector3,device:RenderingDevice,point_buffer:RID,compute_pipeline:RID,uniforms:RID)->void:
 device.buffer_update(point_buffer,0,points.size(),points)
 var list:=device.compute_list_begin();device.compute_list_bind_compute_pipeline(list,compute_pipeline);device.compute_list_bind_uniform_set(list,uniforms,0)
 var push:=PackedFloat32Array([offset.x,offset.y,offset.z,0.0]).to_byte_array()
 device.compute_list_set_push_constant(list,push,16);device.compute_list_dispatch(list,337,1,1)
 device.compute_list_end()
func close()->void:
 if rd==null:return
 positions.texture_rd_rid=RID();normals.texture_rd_rid=RID()
 var device:=rd;var rids:=resources.duplicate();rids.reverse()
 RenderingServer.call_on_render_thread(func():
  for rid in rids:device.free_rid(rid))
 resources.clear();buffers.clear();rd=null;ready=false;submitted_bytes=PackedByteArray()
func _notification(what:int)->void:
 if what!=NOTIFICATION_PREDELETE or rd==null:return
 positions.texture_rd_rid=RID();normals.texture_rd_rid=RID()
 var device:=rd;var rids:=resources.duplicate();rids.reverse()
 RenderingServer.call_on_render_thread(func():
  for rid in rids:device.free_rid(rid))
