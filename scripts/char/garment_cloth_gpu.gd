extends RefCounted
## Experimental distance-constraint cloth, authored attachment masks and point-surface contact.
## Supports ordered inner-layer contact; not continuous collision or self collision.
var rd:RenderingDevice
var buffers:Array[RID]=[]
var shader:RID
var pipeline:RID
var uniform_set:RID
var count:int
var texture_height:int
var position_texture:ImageTexture
var normal_texture:ImageTexture
var last_positions:PackedByteArray
var last_ms:=0.0
var contact_point_count:=21556
const HAND_PROBES:=38
const Art=preload("res://scripts/asset/art_paths.gd")
func initialize(folder:String,vertex_count:int)->bool:
	if RenderingServer.get_rendering_device()==null:return false
	count=vertex_count;texture_height=ceili(float(count)/512)
	rd=RenderingServer.create_local_rendering_device()
	if rd==null:return false
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://scripts/char/garment_cloth_compute.glsl").replace("#[compute]","")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);close();return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var empty:=PackedByteArray();empty.resize(512*texture_height*16)
	var body_data:=PackedByteArray();body_data.resize(65536*16)
	var heads:=PackedByteArray();heads.resize(262144*4)
	var next:=PackedByteArray();next.resize(65536*4)
	var data:Array[PackedByteArray]=[FileAccess.get_file_as_bytes(folder+"/cloth_rest.bin"),FileAccess.get_file_as_bytes(folder+"/anchors.rgba32f"),body_data,body_data,empty,empty,empty,
		FileAccess.get_file_as_bytes(folder+"/cloth_spans.bin"),FileAccess.get_file_as_bytes(folder+"/cloth_links.bin"),FileAccess.get_file_as_bytes(folder+"/cloth_tri_spans.bin"),FileAccess.get_file_as_bytes(folder+"/cloth_tri_links.bin"),empty,heads,next]
	data.append(FileAccess.get_file_as_bytes(Art.path("characters/base/female_base_v2/axis_gpu_adjacency.bin")))
	data.append(FileAccess.get_file_as_bytes(Art.path("characters/base/female_base_v2/axis_gpu_triangles.bin")))
	var hand_data:=PackedByteArray();hand_data.resize(HAND_PROBES*32);data.append(hand_data)
	var uniforms:Array[RDUniform]=[]
	for i in data.size():
		if data[i].is_empty():close();return false
		var rid:=rd.storage_buffer_create(data[i].size(),data[i]);buffers.append(rid)
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=i;uniform.add_id(rid);uniforms.append(uniform)
	uniform_set=rd.uniform_set_create(uniforms,shader,0)
	position_texture=ImageTexture.create_from_image(Image.create(512,texture_height,false,Image.FORMAT_RGBAF))
	normal_texture=ImageTexture.create_from_image(Image.create(512,texture_height,false,Image.FORMAT_RGBAF))
	return true
func dispatch(list:int,mode:int,groups:int,iteration:int,floor_y:float,dt:float)->void:
	var push:=PackedFloat32Array([mode,count,iteration,dt,floor_y,.006,contact_point_count,HAND_PROBES]).to_byte_array()
	rd.compute_list_set_push_constant(list,push,32);rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_add_barrier(list)
func step(body:Node3D,reset:bool=false,substeps:int=3,inner_layers:Array=[])->void:
	var start:=Time.get_ticks_usec()
	# Both paths provide identical local control positions, including explicit root offset.
	var points:PackedByteArray=body.positions_texture.get_image().get_data().slice(0,21556*16)
	var normals:PackedByteArray=body.normals_texture.get_image().get_data().slice(0,21556*16)
	contact_point_count=21556
	for layer:RefCounted in inner_layers:
		if layer==self or layer.last_positions.is_empty():continue
		if contact_point_count+layer.count>65536:push_error("Cloth contact budget exceeded");return
		points.append_array(layer.last_positions.slice(0,layer.count*16))
		normals.append_array(layer.normal_texture.get_image().get_data().slice(0,layer.count*16))
		contact_point_count+=layer.count
	rd.buffer_update(buffers[2],0,points.size(),points);rd.buffer_update(buffers[3],0,normals.size(),normals)
	# Palm probes come from the shared skeleton and knuckle span, not garment IDs
	# or world-space constants. They catch coarse faces crossing between vertices.
	var hand_values:=PackedFloat32Array();hand_values.resize(HAND_PROBES*8)
	for side in 2:
		var prefix:String="l" if side==0 else "r"
		var skeleton:Skeleton3D=body.skeleton
		var wrist:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+"Hand")).origin+body.root_offset
		var middle:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+"Mid2")).origin+body.root_offset
		var index:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+"Index1")).origin
		var pinky:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+"Pinky1")).origin
		var radius:float=index.distance_to(pinky)*.52
		for sample in 4:
			var p:Vector3=wrist.lerp(middle,float(sample)/3.0)
			var offset:int=(side*19+sample)*8
			for axis in 3:hand_values[offset+axis]=p[axis]
			hand_values[offset+3]=radius
		var fingers:Array=["Thumb","Index","Mid","Ring","Pinky"]
		for finger in fingers.size():
			var first:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+fingers[finger]+"1")).origin
			var second:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+fingers[finger]+"2")).origin
			var third:Vector3=body.get_solved_bone_pose(skeleton.find_bone(prefix+fingers[finger]+"3")).origin
			var samples:Array[Vector3]=[first.lerp(second,.5),second.lerp(third,.5),third+(third-second)*.65]
			for sample in 3:
				var p:Vector3=samples[sample]+body.root_offset
				var offset:int=(side*19+4+finger*3+sample)*8
				for axis in 3:hand_values[offset+axis]=p[axis]
				hand_values[offset+3]=first.distance_to(second)*.32
		# The skirt stays on the medial side of a lowered hand. Contact compresses
		# the cloth, never edits the requested wearer pose. Coordinates follow hip.
		var hip:Transform3D=body.get_solved_bone_pose(skeleton.find_bone("hip"))*body.rests.hip.affine_inverse()
		var local_wrist:Vector3=hip.affine_inverse()*(wrist-body.root_offset)
		var inward:Vector3=-hip.basis.x.normalized()*signf(local_wrist.x)
		var waist:float=body.rests.abdomen2.origin.y
		for probe in 19:
			var offset:int=(side*19+probe)*8+4
			for axis in 3:hand_values[offset+axis]=inward[axis]
			hand_values[offset+3]=waist if local_wrist.y<waist else -100.0
	var hand_bytes:=hand_values.to_byte_array();rd.buffer_update(buffers[16],0,hand_bytes.size(),hand_bytes)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0)
	var groups:int=ceili(float(count)/64);var floor_y:float=-body.position.y
	dispatch(list,0,4096,0,floor_y,0);dispatch(list,1,ceili(float(contact_point_count)/64),0,floor_y,0)
	if reset:dispatch(list,2,groups,0,floor_y,0)
	for substep in substeps:
		dispatch(list,3,groups,0,floor_y,1.0/180.0)
		for iteration in 32:dispatch(list,4,groups,iteration,floor_y,0)
	dispatch(list,5,groups,0,floor_y,0)
	rd.compute_list_end();rd.submit();rd.sync()
	last_positions=rd.buffer_get_data(buffers[4])
	position_texture.update(Image.create_from_data(512,texture_height,false,Image.FORMAT_RGBAF,last_positions))
	normal_texture.update(Image.create_from_data(512,texture_height,false,Image.FORMAT_RGBAF,rd.buffer_get_data(buffers[11])))
	last_ms=(Time.get_ticks_usec()-start)/1000.0
func read_points()->PackedVector3Array:
	var values:=last_positions.to_float32_array();var result:=PackedVector3Array();result.resize(count)
	for i in count:result[i]=Vector3(values[i*4],values[i*4+1],values[i*4+2])
	return result
func close()->void:
	if rd==null:return
	if uniform_set.is_valid():rd.free_rid(uniform_set)
	if pipeline.is_valid():rd.free_rid(pipeline)
	if shader.is_valid():rd.free_rid(shader)
	for rid:RID in buffers:rd.free_rid(rid)
	buffers.clear();rd.free();rd=null
