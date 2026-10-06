extends RefCounted
## Editable recipe over the approved branch-card asset, never a per-frame rebuild.
const Schema=preload("res://scripts/world3d/document_schema.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static var cache:Dictionary={}
static func schema()->Dictionary:
	return {"type":"object","additionalProperties":false,"properties":{
		"height":Schema.number(2,25),"crown_scale":Schema.number(.5,1.8),"trunk_scale":Schema.number(.5,2),
		"bare_trunk":Schema.number(.1,8),"lean":Schema.number(-2,2),"density":Schema.number(.4,1.5),"seed":Schema.number(0,100000,true)}}
static func valid_recipe(value:Variant)->bool:
	if not value is Dictionary or value.get("version")!=1 or value.get("role") not in ["trunk","foliage"]:return false
	for field in ["height","bare_trunk"]:
		var number_:Variant=value.get(field)
		if typeof(number_) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number_)) or number_<=0 or number_>100:return false
	if value.bare_trunk>=value.height:return false
	if not value.get("anchors") is Array or value.anchors.is_empty() or value.anchors.size()>600:return false
	for anchor in value.anchors:
		if not anchor is Array or anchor.size()!=3:return false
		for coordinate in anchor:
			if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)) or absf(float(coordinate))>100:return false
	return true
static func recipe(root:Node)->Dictionary:
	for mesh in Paint.meshes(root):
		var value:Variant=mesh.get_meta("extras",{}).get("rmmo_tree_recipe")
		if valid_recipe(value):return value
	return {}
static func defaults(source:Dictionary)->Dictionary:
	return {"height":source.height,"crown_scale":1.,"trunk_scale":1.,"bare_trunk":source.bare_trunk,"lean":0.,"density":1.,"seed":0}
static func valid(record:Dictionary)->bool:
	if not record.has("tree_settings"):return true
	if record.get("kind")!="asset" or not Schema.validate(record.tree_settings,schema()).is_empty():return false
	var values:Dictionary=record.tree_settings
	return values.has_all(schema().properties.keys()) and values.bare_trunk<values.height*.8
static func resolved(root:Node,record:Dictionary)->Dictionary:
	var source:=recipe(root)
	return {} if source.is_empty() else defaults(source).merged(record.get("tree_settings",{}),true)
static func noise(branch:int,seed_:int,salt:int)->float:
	var v:int=(branch*73856093+seed_*19349663+salt*83492791)&0x7fffffff
	v=((v^(v>>13))*1274126177)&0x7fffffff
	return float(v)/2147483647.
static func apply(root:Node3D,record:Dictionary)->String:
	if not record.has("tree_settings"):return ""
	if not valid(record):return "树形参数无效"
	var source:=recipe(root)
	if source.is_empty():return "此模型没有可编辑的枝簇配方"
	var values:Dictionary=record.tree_settings
	var staged:Array=[]
	for node in Paint.meshes(root):
		var metadata:Dictionary=node.get_meta("extras",{}).get("rmmo_tree_recipe",{})
		if metadata.is_empty():continue
		if not valid_recipe(metadata):return "树木枝簇配方无效"
		var key:=str(node.mesh.get_instance_id())+JSON.stringify(values)
		if not cache.has(key):
			var built:=build(node.mesh,metadata,values)
			if built==null:return "枝簇数据不完整，无法生成树形"
			if cache.size()>=48:cache.erase(cache.keys()[0])
			cache[key]=built
		staged.append([node,cache[key]])
	var bounds:=AABB();var first:=true
	for row in staged:
		row[0].mesh=row[1]
		if first:bounds=row[1].get_aabb();first=false
		else:bounds=bounds.merge(row[1].get_aabb())
	for row in staged:
		var node:MeshInstance3D=row[0];var extras:Dictionary=node.get_meta("extras",{}).duplicate(true)
		if extras.has("rmmo_visibility_range"):
			extras.rmmo_visibility_range.bounds=[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z]
			node.set_meta("extras",extras);preload("res://scripts/world3d/asset_visibility_range.gd").register(node)
	return ""
static func build(mesh:Mesh,source:Dictionary,v:Dictionary)->ArrayMesh:
	var output:=ArrayMesh.new();var trunk:bool=source.role=="trunk"
	var branches:Array=source.anchors;var rotations:Array[Basis]=[];var origins:Array[Vector3]=[]
	for i in branches.size():
		var a:Variant=branches[i]
		if not a is Array or a.size()!=3:return null
		origins.append(Vector3(a[0],a[1],a[2]))
		rotations.append(Basis(Vector3.UP,0. if int(v.seed)==0 else (noise(i,int(v.seed),2)-.5)*.42))
	var width:float=v.trunk_scale if trunk else v.crown_scale
	var low_scale:float=v.bare_trunk/source.bare_trunk
	var high_scale:float=(v.height-v.bare_trunk)/(source.height-source.bare_trunk)
	var transforms:Array[Basis]=[];var normals:Array[Basis]=[]
	for scale_y in [low_scale,high_scale]:
		var basis:=Basis(Vector3(width,0,0),Vector3(v.lean/v.height*scale_y,scale_y,0),Vector3(0,0,width))
		transforms.append(basis);normals.append(basis.inverse().transposed())
	for s in mesh.get_surface_count():
		var a:=mesh.surface_get_arrays(s);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		var tags:PackedVector2Array=a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
		if not trunk and tags.size()!=vertices.size():return null
		var old_indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
		if old_indices.is_empty():
			for i in vertices.size():old_indices.append(i)
		var b:Array=[];b.resize(Mesh.ARRAY_MAX)
		var points:=PackedVector3Array();var ns:=PackedVector3Array();var ts:=PackedFloat32Array();var uv:=PackedVector2Array();var uv2:=PackedVector2Array();var indices:=PackedInt32Array()
		for copy in (2 if not trunk and v.density>1 else 1):
			var offset:=points.size()
			for i in vertices.size():
				var p:Vector3=vertices[i];var branch:int=-1 if trunk else int(round(tags[i].x))-1
				if not trunk and (branch<0 or branch>=branches.size()):return null
				var turn:=Basis.IDENTITY
				if not trunk:
					turn=rotations[branch]
					if copy==1:turn=Basis(Vector3.UP,(.25+noise(branch,int(v.seed),3)*.4)*(1 if branch%2==0 else -1))*turn
					p=origins[branch]+turn*(p-origins[branch])
				var zone:=0 if p.y<source.bare_trunk else 1
				var y:float=p.y*low_scale if zone==0 else v.bare_trunk+(p.y-source.bare_trunk)*high_scale
				points.append(Vector3(p.x*width+v.lean*y/v.height,y,p.z*width))
				if a[Mesh.ARRAY_NORMAL]!=null:ns.append((normals[zone]*turn*a[Mesh.ARRAY_NORMAL][i]).normalized())
				if a[Mesh.ARRAY_TANGENT]!=null:
					var tangent:=Vector3(a[Mesh.ARRAY_TANGENT][i*4],a[Mesh.ARRAY_TANGENT][i*4+1],a[Mesh.ARRAY_TANGENT][i*4+2]);tangent=(transforms[zone]*turn*tangent).normalized()
					ts.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,a[Mesh.ARRAY_TANGENT][i*4+3]]))
				if a[Mesh.ARRAY_TEX_UV]!=null:uv.append(a[Mesh.ARRAY_TEX_UV][i])
				if not tags.is_empty():uv2.append(tags[i])
			for i in range(0,old_indices.size(),3):
				var branch:int=-1 if trunk else int(round(tags[old_indices[i]].x))-1
				var keep:bool=trunk or noise(branch,int(v.seed),1)<(minf(1.,v.density) if copy==0 else v.density-1.)
				if keep:indices.append_array(PackedInt32Array([old_indices[i]+offset,old_indices[i+1]+offset,old_indices[i+2]+offset]))
		if indices.is_empty():return null
		b[Mesh.ARRAY_VERTEX]=points;b[Mesh.ARRAY_INDEX]=indices
		if not ns.is_empty():b[Mesh.ARRAY_NORMAL]=ns
		if not ts.is_empty():b[Mesh.ARRAY_TANGENT]=ts
		if not uv.is_empty():b[Mesh.ARRAY_TEX_UV]=uv
		if not uv2.is_empty():b[Mesh.ARRAY_TEX_UV2]=uv2
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,b);output.surface_set_material(s,mesh.surface_get_material(s))
	return output
