extends RefCounted
## Scalar plans and sliced binding for separately published model textures.
## Only the catalog reads a metadata table; no image readback, source decoding,
## uploads, scene instantiation or global cache mutation happens here.
## The caller retains the ordinary shared-image lease until binding completes.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Products=preload("res://scripts/world3d/model_texture_products.gd")
const Readiness=preload("res://scripts/world3d/model_texture_readiness.gd")
const BINDINGS_META:=&"rmmo_model_texture_bindings_v1"
const TABLE_META:=&"rmmo_model_texture_table_v1"
const FAILED:=-1
const READY:=0
const PROGRESS:=1

static func candidate_plan(candidate:Dictionary,root:String,tables:Dictionary)->Dictionary:
	# Operation-local catalog. Its immutable values contain only scalar metadata,
	# so models sharing a table do not repeat file or ancestor-path reads.
	root=root.replace("\\","/").simplify_path()
	if not candidate.has("texture_table"):
		return {"ok":true,"error":"","keys":{},"sources":{},"plan":{"rows":{},"output_bytes":0,"estimated_bytes":0},"table_sha":""}
	var descriptor:Variant=candidate.texture_table
	if not descriptor is Dictionary:return {"ok":false,"error":"Invalid native model texture descriptor"}
	var key:String=root+":"+str(descriptor.get("sha256",""))
	if tables.has(key):
		# A SHA identifies one exact table/size contract. A contradictory index
		# must not borrow another model's already admitted texture budget.
		for field:String in ["version","sha256","bytes","textures","image_bytes"]:
			if tables[key].descriptor.get(field)!=descriptor.get(field):return {"ok":false,"error":"Conflicting native model texture descriptor"}
		return tables[key].prepared
	var read:=Products.read_table(descriptor,root,true)
	if not read.ok:return {"ok":false,"error":read.error}
	var prepared:=texture_plan(read.table,root)
	if not prepared.ok:return prepared
	prepared.table_sha=descriptor.sha256
	tables[key]={"descriptor":descriptor.duplicate(true),"prepared":prepared}
	return prepared

static func texture_plan(table:Dictionary,root:String)->Dictionary:
	# read_table has checked the published table once. Native products already
	# contain their final pixels/mips; a normal slot must not decode/upload them
	# again under a second key. Sampling/color-space choices stay on materials.
	root=root.replace("\\","/").simplify_path()
	var rows:Dictionary={};var sources:Dictionary={};var keys:Dictionary={}
	var output:=0;var scratch:=0
	for id:String in table.get("textures",{}):
		var entry:Dictionary=table.textures[id]
		var path:String=root.path_join(entry.file).replace("\\","/").simplify_path()
		# The table reader already checked ancestry in one batch. Keep only the
		# namespace invariant here; do not reopen every product's ancestors.
		if not Paths.asset_key_allowed(path,root):return {"ok":false,"error":"Model texture product escapes content root"}
		var key:=Paint.texture_key(path)
		var row:={"path":path,"product":path,"root":root,"flip":false,"normal":false,
			"extension":"stex","width":int(entry.width),"height":int(entry.height),
			"format":int(entry.format),"source_bytes":int(entry.file_bytes),"output_bytes":int(entry.bytes),
			"alpha":bool(entry.alpha),"representation":"stex:"+id,"mip_sizes":entry.mip_sizes,
			"model_product":true}
		keys[id]=key
		if rows.has(key):continue
		rows[key]=row;sources[key]=[path,false,false]
		output+=int(row.output_bytes);scratch=maxi(scratch,Prep.workspace_bytes(row))
	return {"ok":true,"error":"","keys":keys,"sources":sources,
		"plan":{"rows":rows,"output_bytes":output,"estimated_bytes":output*2+scratch}}

static func _fail(reason:String)->Dictionary:
	return {"ok":false,"error":reason,"bindings":[],"keys":{},"position":0,"sets":0,"unchanged":0}

static func begin(packed:PackedScene,keys:Dictionary,expected_table:String="")->Dictionary:
	if packed==null:return _fail("Missing model scene for texture binding")
	var scene:=packed.get_state()
	var pending:Array[Material]=[];var meshes:Dictionary={}
	var table:=""
	for node:int in scene.get_node_count():
		for property:int in scene.get_node_property_count(node):
			var name:StringName=scene.get_node_property_name(node,property)
			var value:Variant=scene.get_node_property_value(node,property)
			if node==0 and name==StringName("metadata/"+str(TABLE_META)):table=str(value)
			if value is Mesh:
				var id:int=value.get_instance_id()
				if meshes.has(id):continue
				meshes[id]=true
				for surface:int in value.get_surface_count():pending.append(value.surface_get_material(surface))
			elif value is Material:pending.append(value)
	if not expected_table.is_empty() and table!=expected_table:return _fail("Model texture table does not match scene")
	return _materials(pending,keys,table,packed,meshes.size())

static func begin_scene(scene:Node,keys:Dictionary,expected_table:String="")->Dictionary:
	# Geometry/collision preparation may instantiate before parallel pixels are
	# ready. Bind those actual private materials, including local-to-scene copies.
	if scene==null:return _fail("Missing private model scene for texture binding")
	var table:String=scene.get_meta(TABLE_META,"")
	if not expected_table.is_empty() and table!=expected_table:return _fail("Model texture table does not match scene")
	var nodes:Array[Node]=[scene];var pending:Array[Material]=[];var meshes:Dictionary={}
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		if not node is MeshInstance3D:continue
		pending.append(node.material_override);pending.append(node.material_overlay)
		if node.mesh==null:continue
		var id:int=node.mesh.get_instance_id()
		if not meshes.has(id):
			meshes[id]=true
			for surface:int in node.mesh.get_surface_count():pending.append(node.mesh.surface_get_material(surface))
		for surface:int in node.get_surface_override_material_count():pending.append(node.get_surface_override_material(surface))
	return _materials(pending,keys,table,scene,meshes.size())

static func _materials(pending:Array[Material],keys:Dictionary,table:String,owner:Object,mesh_count:int)->Dictionary:
	var visited:Dictionary={};var bindings:Array=[];var needed:Dictionary={}
	var texture_slots:Dictionary={}
	while not pending.is_empty():
		var material:Material=pending.pop_back()
		if material==null or visited.has(material.get_instance_id()):continue
		visited[material.get_instance_id()]=true;pending.append(material.next_pass)
		if not material.has_meta(BINDINGS_META):continue
		if not material is StandardMaterial3D or material.get_script()!=null:return _fail("Unsupported model material texture bindings")
		# One property-layout observation per operation, not per instance/slot.
		if texture_slots.is_empty():
			for info:Dictionary in material.get_property_list():
				if int(info.type)==TYPE_OBJECT and str(info.get("hint_string","")).split(",").has("Texture2D"):
					texture_slots[str(info.name)]=true
		var descriptor:Variant=material.get_meta(BINDINGS_META)
		if not descriptor is Dictionary:return _fail("Invalid model texture bindings")
		var slots:Array[StringName]=[];var targets:Array[String]=[]
		for slot:Variant in descriptor:
			if not slot is String or not texture_slots.has(slot):return _fail("Unknown model texture slot")
			var binding:Variant=descriptor[slot]
			if not binding is Dictionary or not binding.get("id") is String or not keys.has(binding.id):return _fail("Model texture binding is absent from table")
			var key:String=keys[binding.id]
			slots.append(StringName(slot));targets.append(key);needed[key]=true
		bindings.append({"material":material,"slots":slots,"targets":targets})
	return {"ok":true,"error":"","bindings":bindings,"keys":needed,"position":0,
		"sets":0,"unchanged":0,"visited_materials":visited.size(),"visited_meshes":mesh_count,"owners":{},"adopted":false,
		"owner":owner,"table_sha":table,"completed":false}

static func adopt(state:Dictionary,textures:Dictionary)->bool:
	# Resolve the whole immutable dependency set before the first setter. A
	# missing/cancelled sibling cannot partially publish a white/native model.
	if not state.get("ok",false):return false
	if state.get("adopted",false):return true
	for key:String in state["keys"]:
		if not textures.get(key) is Texture2D:
			state.error="Model texture is not ready: "+key;return false
	for key:String in state["keys"]:state.owners[key]=textures[key]
	state.adopted=true;state.error="";return true

static func step(state:Dictionary)->int:
	if not state.get("ok",false) or not state.get("adopted",false):return FAILED
	if int(state.position)>=state.bindings.size():return _complete(state)
	var binding:Dictionary=state.bindings[int(state.position)]
	var material:StandardMaterial3D=binding.material
	for slot:int in binding.slots.size():
		var texture:Texture2D=state.owners[binding.targets[slot]]
		if material.get(binding.slots[slot])==texture:state.unchanged+=1;continue
		material.set(binding.slots[slot],texture);state.sets+=1
	state.position+=1
	return _complete(state) if int(state.position)>=state.bindings.size() else PROGRESS

static func _complete(state:Dictionary)->int:
	if not state.completed:
		if not str(state.table_sha).is_empty():state.owner.set_meta(Readiness.READY_META,state.table_sha)
		state.completed=true
	return READY

static func release(state:Dictionary)->void:
	# Main owner after publication/discard; this plan never secretly retains a
	# second scene graph or pixels inside its small descriptor arrays.
	state.clear()
