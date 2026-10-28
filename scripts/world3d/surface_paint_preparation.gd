extends RefCounted
## Private CPU fragments. Final grouping uses actual main-thread material owners.
## No Node, texture/file access, shared cache writes or renderer calls in prepare.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
# Ordinary map07_B1 had an unlocated native access violation. Preserve the
# measured candidate, but require probe opt-in until its stability is resolved.
static var enabled:=false
static var publications:=0
static var publication_us:=0
static var fallback_count:=0

static func active()->bool:
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	return enabled and not controls.discard_map_textures

static func for_road(record:Dictionary,arrays:Array,budget:Dictionary,token:RefCounted=null,cached_source_bounds:Variant=null)->Dictionary:
	if not active() or record.get("surface_paint",[]).is_empty() or record.has("terrain_grade"):return {}
	if not record.surface_paint.all(func(entry):return entry.mesh=="."):return {}
	# Native road generators are unindexed. Each original vertex can therefore
	# belong to only one fragment, bounding retained arrays independent of face
	# count. Indexed/custom inputs keep the generic publication route for now.
	for surface:Array in arrays:
		if surface[Mesh.ARRAY_INDEX]!=null and not surface[Mesh.ARRAY_INDEX].is_empty():return {}
		# Only complete triangle streams preserve every source position through
		# grouping/compaction. Generic indexed or trailing-vertex inputs cannot
		# grant this proof (their unused vertices may disappear from the output).
		if surface[Mesh.ARRAY_VERTEX].size()%3!=0:return {}
	if cancelled(token):return {}
	var began:=Time.get_ticks_usec()
	var box:AABB=cached_source_bounds if cached_source_bounds is AABB else Bounds.bounds(arrays)
	var result:=_prepare(arrays,record.surface_paint,token,box)
	if result.get("ok",false):
		# A second conservative road envelope is reserved by the scheduler before
		# dispatch. It covers private topology scratch, indices and retained paint
		# fragments in addition to the unchanged original road-output charge.
		assert(int(result.output_bytes)<=int(budget.output_bytes)*2)
		result.source_bounds=box
		result.source_bounds_scans=0 if cached_source_bounds is AABB else 1
		result.elapsed_us=Time.get_ticks_usec()-began
	return result

static func cancelled(token:RefCounted)->bool:return token!=null and token.is_cancelled()

static func prepare(surfaces:Array,entries:Array,token:RefCounted=null)->Dictionary:
	return _prepare(surfaces,entries,token)

static func _prepare(surfaces:Array,entries:Array,token:RefCounted=null,complete_source_bounds:Variant=null)->Dictionary:
	var began:=Time.get_ticks_usec()
	if cancelled(token):return {}
	var first_only:bool=not entries.is_empty() and entries.all(func(entry):return int(entry.surface)==0)
	var geo:=Paint.geometry_arrays(surfaces,false,first_only)
	if not geo.ok:return geo
	var overrides:Dictionary={}
	for entry:Dictionary in entries:
		var slot:=int(entry.surface)
		if slot>=geo.surfaces.size() or not geo.surfaces[slot].faces.has(int(entry.face)) or geo.surfaces[slot].signature!=entry.geometry:return Paint.fail("模型几何已改变，请先清除旧面材质再重新绘制")
		var uv:Variant=surfaces[slot][Mesh.ARRAY_TEX_UV]
		if entry.mapping=="uv" and (uv==null or uv.size()!=surfaces[slot][Mesh.ARRAY_VERTEX].size()):return Paint.fail("这个模型没有原始 UV，请选择平面投影")
		overrides["%d:%d"%[slot,entry.face]]=entry
	if surfaces.size()+entries.size()>256:return Paint.fail("绘制后材质槽超过 256 个，请拆分模型")
	var fragments:Array=[];var output_arrays:Array=[];var output_bytes:=0
	for slot:int in surfaces.size():
		if cancelled(token):return {}
		var data:Dictionary
		if slot<geo.surfaces.size():data=geo.surfaces[slot]
		else:
			var arrays:Array=surfaces[slot]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			if indices.is_empty():
				indices.resize(arrays[Mesh.ARRAY_VERTEX].size())
				for i:int in indices.size():indices[i]=i
			data={"arrays":arrays,"indices":indices,"faces":{},"face_for_triangle":PackedInt32Array()}
		var groups:Dictionary={};var group_entries:Dictionary={};var face_groups:Dictionary={}
		for face:Variant in data.faces:
			var face_key:="%d:%d"%[slot,face]
			if not overrides.has(face_key):continue
			var entry:Dictionary=overrides[face_key]
			var group_key:String="uv:"+JSON.stringify([entry.material,entry.scale,entry.offset,entry.rotation],"",true) if entry.mapping=="uv" else face_key
			face_groups[face_key]=group_key;group_entries[group_key]=entry
		for triangle:int in data.face_for_triangle.size():
			var key:String=face_groups.get("%d:%d"%[slot,data.face_for_triangle[triangle]],"original")
			if not groups.has(key):groups[key]=PackedInt32Array()
			for corner:int in 3:groups[key].append(data.indices[triangle*3+corner])
		if slot>=geo.surfaces.size():groups.original=data.indices
		for key:String in groups:
			if cancelled(token):return {}
			var arrays:Array=data.arrays.duplicate();arrays[Mesh.ARRAY_INDEX]=groups[key]
			var entry:Dictionary=group_entries.get(key,{})
			if not entry.is_empty():arrays[Mesh.ARRAY_TEX_UV]=Paint._uvs(data,entry);arrays[Mesh.ARRAY_TANGENT]=null
			var source_indices:Variant=data.arrays[Mesh.ARRAY_INDEX]
			var complete_vertices:bool=source_indices==null or source_indices.is_empty()
			var compact:Array=arrays if Paint.preserve_complete_surfaces_enabled and key=="original" and groups.size()==1 and complete_vertices else Paint._compact(arrays)
			var normal:bool=not entry.is_empty() and not str(entry.material.get("normal_path","")).is_empty()
			if normal:
				var builder:=SurfaceTool.new();builder.create_from_arrays(compact);builder.generate_tangents();compact=builder.commit_to_arrays()
			var layout:=0
			for channel:int in Mesh.ARRAY_MAX:
				if compact[channel]!=null and not compact[channel].is_empty():layout|=1<<channel
			fragments.append({"arrays":compact,"source_slot":slot,"entry":entry,"normal":normal,"layout":layout})
			output_arrays.append(compact)
			output_bytes+=array_bytes(compact)
	# for_road alone establishes that grouping and tangent generation retain
	# all positions. Other callers still measure their actual compacted output.
	var box:AABB=complete_source_bounds if complete_source_bounds is AABB else Bounds.bounds(output_arrays)
	if cancelled(token):return {}
	return {"ok":true,"source":surfaces,"entries":entries,"fragments":fragments,"bounds":box,"output_bytes":output_bytes,"elapsed_us":Time.get_ticks_usec()-began}

static func array_bytes(arrays:Array)->int:
	# Native roads only use these packed channels. Counting is O(channels).
	var result:=0
	for value:Variant in arrays:
		if value is PackedVector3Array:result+=value.size()*12
		elif value is PackedVector2Array:result+=value.size()*8
		elif value is PackedColorArray:result+=value.size()*16
		elif value is PackedFloat32Array or value is PackedInt32Array:result+=value.size()*4
		elif value is PackedByteArray:result+=value.size()
		elif value is PackedFloat64Array or value is PackedInt64Array:result+=value.size()*8
	return result

static func publish(node:MeshInstance3D,entries:Array,packet:Dictionary,texture_checks:Variant)->Dictionary:
	var began:=Time.get_ticks_usec()
	var source:Mesh=Paint.source(node)
	# The mounted owner promises immutable arrays. Generic/editor calls without
	# this exact generation fall back; packet validity never becomes a disk proof.
	if not source is Cpu or not is_same(source.surfaces,packet.get("source")) or entries!=packet.get("entries"):fallback_count+=1;return {}
	if not packet.get("ok",false):return packet
	var issue:String=Paint.paint_texture_error(entries,texture_checks)
	if not issue.is_empty():return Paint.fail(issue)
	var merged:Dictionary={}
	for fragment:Dictionary in packet.fragments:
		var slot:int=fragment.source_slot
		var material:Material=node.get_meta("paint_source_materials")[slot] if node.has_meta("paint_source_materials") else Paint.source_material(node,slot)
		if not fragment.entry.is_empty():
			material=Paint.make_material(fragment.entry.material,material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK)
			if bool(material.normal_enabled)!=bool(fragment.normal):fallback_count+=1;return {} # Changed material: use ordinary geometry.
		var key:=str(material.get_instance_id() if material!=null else 0)+":"+str(fragment.layout)
		if not merged.has(key):
			merged[key]={"builder":null,"arrays":fragment.arrays,"material":material}
			if Paint.preserve_complete_surfaces_enabled:continue
		var row:Dictionary=merged[key]
		if row.builder==null:
			row.builder=SurfaceTool.new()
			if Paint.preserve_complete_surfaces_enabled:
				var first:=Cpu.new();first.surfaces=[row.arrays];first.materials=[material]
				row.builder.append_from(first,0,Transform3D.IDENTITY);row.arrays=[]
		var cpu:=Cpu.new();cpu.surfaces=[fragment.arrays];cpu.materials=[material]
		row.builder.append_from(cpu,0,Transform3D.IDENTITY)
	var arrays:Array=[];var materials:Array=[]
	for row:Dictionary in merged.values():
		arrays.append(row.arrays if row.builder==null else row.builder.commit_to_arrays());materials.append(row.material)
	var result:={"ok":true,"mesh":Bounds.make_cpu(arrays,materials,packet.bounds),"prepared_paint":true}
	publications+=1;publication_us+=Time.get_ticks_usec()-began
	return result

static func snapshot()->Dictionary:return {"publications":publications,"publication_us":publication_us,"fallbacks":fallback_count}
