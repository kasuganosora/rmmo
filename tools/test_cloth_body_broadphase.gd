extends SceneTree
## Compare real GPU outputs with and without block culling. Uneven block counts,
## moving colliders, rotated coordinates, substeps and reverse vertex IDs.
var rd:RenderingDevice
var owned:Array[RID]=[]
var failed:=false
var candidate_program:RID
var candidate_group_size:=64
var cooperative_candidates:=false
func _initialize()->void:call_deferred("run")
func buffer(bytes:PackedByteArray)->RID:
	var result:=rd.storage_buffer_create(bytes.size(),bytes);owned.append(result);return result
func uniform(binding:int,rid:RID)->RDUniform:
	var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=binding;u.add_id(rid);return u
func shader(name:String, exhaustive:=false,define:String="")->RID:
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/"+name+".glsl").replace("\r\n","\n").replace("#[compute]\n","")
	if exhaustive:source.source_compute=source.source_compute.replace("#version 450","#version 450\n#define RMMO_EXHAUSTIVE_SANITIZE")
	if not define.is_empty():source.source_compute=source.source_compute.replace("#version 450","#version 450\n#define "+define)
	var spirv:=rd.shader_compile_spirv_from_source(source)
	var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		failed=true;push_error(name+" "+define+": "+error);return RID()
	var result:=rd.shader_create_from_spirv(spirv);owned.append(result);return result
func dispatch(program:RID,data:Dictionary,push:PackedByteArray,count:int)->void:
	var uniforms:Array[RDUniform]=[]
	for key:int in data:uniforms.append(uniform(key,data[key]))
	var bindings:=rd.uniform_set_create(uniforms,program,0)
	var pipeline:=rd.compute_pipeline_create(program)
	var cl:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(cl,pipeline);rd.compute_list_bind_uniform_set(cl,bindings,0)
	rd.compute_list_set_push_constant(cl,push,push.size());rd.compute_list_dispatch(cl,count if program==candidate_program and cooperative_candidates else ceili(float(count)/float(candidate_group_size if program==candidate_program else 64)),1,1);rd.compute_list_end();rd.submit();rd.sync()
	rd.free_rid(bindings);rd.free_rid(pipeline)
func run()->void:
	rd=RenderingServer.create_local_rendering_device();assert(rd!=null)
	var bounds_shader:=shader("cloth_body_bounds")
	var forward_shader:=shader("cloth_collide_triangles")
	var reverse_shader:=shader("cloth_reverse_contacts")
	var sanitize_shader:=shader("cloth_skin_collide_triangles")
	var sanitize_reference:=shader("cloth_skin_collide_triangles",true)
	var args:=OS.get_cmdline_user_args();var padding:=.012;var padding_flag:=args.find("--candidate-padding")
	if padding_flag>=0 and padding_flag+1<args.size():padding=float(args[padding_flag+1])
	var group_flag:=args.find("--candidate-group-size")
	if group_flag>=0 and group_flag+1<args.size():candidate_group_size=int(args[group_flag+1])
	cooperative_candidates="--cooperative-candidates" in args
	var candidate_shader:=shader("cloth_contact_candidates",false,"RMMO_CANDIDATE_PADDING %.6f\n#define RMMO_CANDIDATE_GROUP_SIZE %d"%[padding,candidate_group_size]+("\n#define RMMO_COOPERATIVE_CANDIDATES" if cooperative_candidates else ""))
	candidate_program=candidate_shader
	var narrow_forward:=shader("cloth_collide_triangles",false,"RMMO_CANDIDATE_LIST")
	var fallback_forward:=shader("cloth_collide_triangles",false,"RMMO_CANDIDATE_FALLBACK")
	var narrow_reverse:=shader("cloth_reverse_contacts",false,"RMMO_CANDIDATE_LIST")
	var combined_forward:=shader("cloth_collide_triangles",false,"RMMO_CANDIDATE_COMBINED")
	var combined_reverse:=shader("cloth_reverse_contacts",false,"RMMO_CANDIDATE_COMBINED")
	var fallback_reverse:=shader("cloth_reverse_contacts",false,"RMMO_CANDIDATE_FALLBACK")
	if failed:
		for rid in owned:rd.free_rid(rid)
		rd.free();quit(2);return
	var worst:=0.0;var changed:=0;var comparisons:=0
	for case in 13:
		var mark:=owned.size()
		var triangle_count:int=2305 if case==12 else [1,7,9,31,65,257][case%6]
		var triangle_leaves:=1;var vertex_leaves:=1
		while triangle_leaves*8<triangle_count:triangle_leaves*=2
		while vertex_leaves*8<triangle_count*3:vertex_leaves*=2
		var leaf_count:=maxi(triangle_leaves,vertex_leaves)
		var levels:=0;var width:=leaf_count
		while width>0:levels+=1;width>>=1
		var basis:=Basis(Vector3(1,2,3).normalized(),case*.17)
		var old:=PackedVector4Array();var body:=PackedVector4Array();var ids:=PackedInt32Array()
		for i in triangle_count:
			# Far blocks plus a moving near block across the cloth plane.
			var x:=float(i/64)*4 if i<192 else float(i%8)*.1-.4
			var z:=float(i%8)*.1-.4
			if case==12:x=0;z=0 # Natural overflow, not only a manually forced sentinel.
			var motion:float=[.001,.03,.13][case%3]
			for p in [Vector3(x-.06,0,z-.06),Vector3(x+.06,0,z-.06),Vector3(x,0,z+.06)]:
				var a:Vector3=basis*(p+Vector3(0,-motion,0));var b:Vector3=basis*(p+Vector3(0,motion,0))
				old.append(Vector4(a.x,a.y,a.z,0));body.append(Vector4(b.x,b.y,b.z,0))
				ids.append(ids.size())
		# Reverse the vertex ID order as well; bounds must follow the index buffer.
		if case%2:ids.reverse()
		var previous:=buffer(old.to_byte_array());var current:=buffer(body.to_byte_array());var vertices:=buffer(ids.to_byte_array())
		var empty:=PackedByteArray();empty.resize((triangle_leaves*2+vertex_leaves)*2*32);var bounds:=buffer(empty)
		var permutation:=PackedInt32Array()
		var centers:=PackedVector3Array()
		for i in triangle_count:centers.append(Vector3(body[i*3].x,body[i*3].y,body[i*3].z))
		permutation=preload("res://addons/godot_gpu_cloth/src/cloth_spatial_order.gd").order(centers)
		centers.clear()
		for id in ids:centers.append(Vector3(body[id].x,body[id].y,body[id].z))
		permutation.append_array(preload("res://addons/godot_gpu_cloth/src/cloth_spatial_order.gd").order(centers))
		var order_buffer:=buffer(permutation.to_byte_array())
		if case%3==0:
			var a:=permutation.slice(0,triangle_count);a.reverse()
			var b:=permutation.slice(triangle_count);b.reverse();a.append_array(b)
			rd.buffer_update(order_buffer,0,a.size()*4,a.to_byte_array())
		var bp:=PackedByteArray();bp.resize(32);bp.encode_u32(0,triangle_count);bp.encode_u32(4,ids.size());bp.encode_u32(8,triangle_leaves)
		for level in levels:
			bp.encode_u32(12,level)
			dispatch(bounds_shader,{0:current,1:previous,2:vertices,3:bounds,4:order_buffer},bp,leaf_count>>level)
		var points:=PackedVector4Array();var indices:=PackedInt32Array();var weights:=PackedVector4Array()
		for face in 43:
			var center:=Vector3(float(face%7)*.1-.3,0,float(face/7)*.1-.3)
			for offset in [Vector3(-.06,0,-.06),Vector3(.06,0,-.06),Vector3(0,0,.06)]:
				var p:Vector3=basis*(center+offset);points.append(Vector4(p.x,p.y,p.z,1));indices.append(indices.size());weights.append(Vector4(1,0,0,0))
		var pos:=buffer(points.to_byte_array());var predicted:=buffer(points.to_byte_array());var weight:=buffer(weights.to_byte_array());var faces:=buffer(indices.to_byte_array())
		empty.resize(points.size()*32);empty.fill(0);var directions:=buffer(empty)
		empty.resize(points.size()*16);empty.fill(0);var corrections:=buffer(empty)
		empty.resize(8);empty.fill(0);var edges:=buffer(empty)
		empty.resize(points.size()*2055*4);empty.fill(0);var candidates:=buffer(empty)
		for reverse in [false,true]:
			var push:=PackedByteArray();push.resize(32)
			push.encode_u32(0,43 if reverse else points.size());push.encode_u32(4,ids.size() if reverse else triangle_count)
			push.encode_float(8,.006);push.encode_float(16,0 if case<4 else .25);push.encode_float(20,1 if case<8 else .75)
			push.encode_u32(28,triangle_leaves)
			var data:Dictionary={0:pos,1:predicted,4:current,5:weight,6:previous,7:directions,8:bounds,9:order_buffer}
			if reverse:data={0:pos,1:predicted,2:faces,3:current,4:previous,5:vertices,6:corrections,7:edges,8:bounds,9:order_buffer}
			var reference:=PackedFloat32Array()
			for enabled in [false,true]:
				rd.buffer_update(predicted,0,points.to_byte_array().size(),points.to_byte_array())
				push.encode_u32(24,int(enabled))
				dispatch(reverse_shader if reverse else forward_shader,data,push,43 if reverse else points.size())
				var actual:=rd.buffer_get_data(corrections if reverse else predicted).to_float32_array()
				if not enabled:reference=actual;continue
				comparisons+=1
				for i in actual.size():
					assert(is_finite(actual[i]));worst=maxf(worst,absf(actual[i]-reference[i]))
				if reverse:
					for value in actual:
						if absf(value)>.0001:changed+=1
			# Split broad/narrow pipeline, including deliberate overflow fallback.
			for cache_case in ["reuse", "overflow", "escape", "body_refresh", "substep_reuse", "substep_filtered", "adaptive", "adaptive_boundary", "refit", "refit_adaptive", "refit_boundary"]:
				rd.buffer_update(predicted,0,points.size()*16,points.to_byte_array())
				var cp:=PackedByteArray();cp.resize(32);cp.encode_u32(0,43 if reverse else points.size());cp.encode_u32(4,int(reverse)+2);cp.encode_u32(8,triangle_leaves);cp.encode_u32(12,triangle_count)
				cp.encode_float(16,push.decode_float(16));cp.encode_float(20,push.decode_float(20));cp.encode_float(24,.006);cp.encode_u32(28,ids.size())
				if cache_case=="substep_filtered":cp.encode_u32(4,int(reverse)+2+4)
				if cache_case in ["adaptive","adaptive_boundary"]:cp.encode_u32(4,int(reverse)+2+4+16+(80<<8))
				var original_bounds:=PackedByteArray()
				if cache_case.begins_with("refit"):
					original_bounds=rd.buffer_get_data(bounds)
					cp.encode_u32(4,int(reverse)+2+4+(16+(80<<8) if cache_case!="refit" else 0))
					bp.encode_u32(24,80);bp.encode_u32(28,3 if cache_case=="refit" else 1)
					bp.encode_float(16,cp.decode_float(16));bp.encode_float(20,cp.decode_float(20))
					if cache_case=="refit_boundary":
						bp.encode_float(16,0);bp.encode_float(20,.1)
						for level in levels:
							bp.encode_u32(12,level);dispatch(bounds_shader,{0:current,1:previous,2:vertices,3:bounds,4:order_buffer},bp,leaf_count>>level)
						var first_push:=cp.duplicate();first_push.encode_float(16,0);first_push.encode_float(20,.1)
						dispatch(candidate_shader,{0:pos,1:predicted,2:faces,3:current,4:previous,5:vertices,6:bounds,7:order_buffer,8:candidates,9:weight},first_push,43 if reverse else points.size())
						bp.encode_float(16,cp.decode_float(16));bp.encode_float(20,cp.decode_float(20));cp.encode_u32(4,int(reverse)+4+8+16+(80<<8))
					for level in levels:
						bp.encode_u32(12,level);dispatch(bounds_shader,{0:current,1:previous,2:vertices,3:bounds,4:order_buffer},bp,leaf_count>>level)
					assert(rd.buffer_get_data(bounds,0,triangle_leaves*2*32)==original_bounds.slice(0,triangle_leaves*2*32),"Refit changed sanitizer/fallback whole-frame tree")
				var candidate_bindings:Dictionary={0:pos,1:predicted,2:faces,3:current,4:previous,5:vertices,6:bounds,7:order_buffer,8:candidates,9:weight}
				if cache_case in ["substep_reuse","adaptive_boundary"]:
					cp.encode_float(16,0);cp.encode_float(20,.1)
					dispatch(candidate_shader,candidate_bindings,cp,43 if reverse else points.size())
					cp.encode_float(16,push.decode_float(16));cp.encode_float(20,push.decode_float(20))
					cp.encode_u32(4,int(reverse)+(4+8+16+(80<<8) if cache_case=="adaptive_boundary" else 0))
				if cache_case=="escape":
					var distant:=points.duplicate()
					for i in distant.size():distant[i].x+=50
					rd.buffer_update(pos,0,distant.size()*16,distant.to_byte_array())
					rd.buffer_update(predicted,0,distant.size()*16,distant.to_byte_array())
					dispatch(candidate_shader,candidate_bindings,cp,43 if reverse else points.size())
					rd.buffer_update(pos,0,points.size()*16,points.to_byte_array())
					rd.buffer_update(predicted,0,points.size()*16,points.to_byte_array())
					cp.encode_u32(4,int(reverse)) # Must invalidate by query escape alone.
				if cache_case=="body_refresh":
					var distant_body:=body.duplicate();var distant_old:=old.duplicate()
					for i in distant_body.size():distant_body[i].x+=50;distant_old[i].x+=50
					rd.buffer_update(current,0,distant_body.size()*16,distant_body.to_byte_array())
					rd.buffer_update(previous,0,distant_old.size()*16,distant_old.to_byte_array())
					for level in levels:
						bp.encode_u32(12,level);dispatch(bounds_shader,{0:current,1:previous,2:vertices,3:bounds,4:order_buffer},bp,leaf_count>>level)
					dispatch(candidate_shader,candidate_bindings,cp,43 if reverse else points.size())
					rd.buffer_update(current,0,body.size()*16,body.to_byte_array())
					rd.buffer_update(previous,0,old.size()*16,old.to_byte_array())
					for level in levels:
						bp.encode_u32(12,level);dispatch(bounds_shader,{0:current,1:previous,2:vertices,3:bounds,4:order_buffer},bp,leaf_count>>level)
					# Query is unchanged: only the forced new-packet refresh can repair the list.
				dispatch(candidate_shader,{0:pos,1:predicted,2:faces,3:current,4:previous,5:vertices,6:bounds,7:order_buffer,8:candidates,9:weight},cp,43 if reverse else points.size())
				cp.encode_u32(4,int(reverse)+(4 if cache_case in ["substep_filtered","refit"] else (4+16+(80<<8) if cache_case in ["adaptive","adaptive_boundary","refit_adaptive","refit_boundary"] else 0)))
				dispatch(candidate_shader,{0:pos,1:predicted,2:faces,3:current,4:previous,5:vertices,6:bounds,7:order_buffer,8:candidates,9:weight},cp,43 if reverse else points.size())
				if cache_case=="overflow":
					var bytes:=rd.buffer_get_data(candidates)
					for i in range(0,43 if reverse else points.size(),2):bytes.encode_u32(i*2055*4,2049)
					rd.buffer_update(candidates,0,bytes.size(),bytes)
				if case==12 and cache_case=="reuse":
					var overflow_bytes:=rd.buffer_get_data(candidates);var overflow_seen:=false
					for query in (43 if reverse else points.size()):overflow_seen=overflow_seen or overflow_bytes.decode_u32(query*2055*4)>2048
					assert(overflow_seen,"Dense natural overflow case did not exercise candidate fallback")
				var candidate_data:=data.duplicate();candidate_data[10]=candidates
				dispatch(narrow_reverse if reverse else narrow_forward,candidate_data,push,(43 if reverse else points.size())*64)
				dispatch(fallback_reverse if reverse else fallback_forward,candidate_data,push,(43 if reverse else points.size())*64)
				var actual:=rd.buffer_get_data(corrections if reverse else predicted).to_float32_array()
				for i in actual.size():assert(is_finite(actual[i]));worst=maxf(worst,absf(actual[i]-reference[i]))
				rd.buffer_update(predicted,0,points.size()*16,points.to_byte_array())
				dispatch(combined_reverse if reverse else combined_forward,candidate_data,push,(43 if reverse else points.size())*64)
				var combined:=rd.buffer_get_data(corrections if reverse else predicted).to_float32_array()
				comparisons+=2
				for i in combined.size():assert(is_finite(combined[i]));worst=maxf(worst,absf(combined[i]-reference[i]))
				if not original_bounds.is_empty():
					rd.buffer_update(bounds,0,original_bounds.size(),original_bounds);bp.encode_u32(28,0)
		var sp:=PackedByteArray();sp.resize(16);sp.encode_u32(0,points.size());sp.encode_u32(4,triangle_count);sp.encode_float(8,.04)
		var sanitized:=PackedFloat32Array()
		for program in [sanitize_reference,sanitize_shader]:
			rd.buffer_update(predicted,0,points.size()*16,points.to_byte_array())
			dispatch(program,{0:predicted,1:current,2:bounds},sp,points.size())
			var actual:=rd.buffer_get_data(predicted).to_float32_array()
			if sanitized.is_empty():sanitized=actual
			else:
				comparisons+=1
				for i in actual.size():assert(is_finite(actual[i]));worst=maxf(worst,absf(actual[i]-sanitized[i]))
		for i in range(owned.size()-1,mark-1,-1):rd.free_rid(owned[i]);owned.remove_at(i)
	failed=failed or changed<=0 or worst>=.000002
	for rid in owned:rd.free_rid(rid)
	rd.free()
	if failed:push_error("GPU parity failed: "+str(worst));quit(2);return
	print("PASS block bounds / exhaustive GPU parity: ",comparisons," cases incl sanitizer, split candidates, overflow, query escape, body refresh, substep reuse and tree refit, max error=",worst," active reverse corrections=",changed);quit()
