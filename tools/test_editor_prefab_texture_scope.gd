extends "res://tools/test_editor_terrain_texture_scope.gd"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")

func base_texture(id:String)->Texture2D:
	return editor._view.get_node(id).get_active_material(0).albedo_texture

func texture_timing_key()->String:return "prefab_texture_worker"

func setup_record(doc:RefCounted,id:String,definition:Dictionary)->Dictionary:
	var record:Dictionary=doc._find(id)
	record.collision="block"
	var box:=BoxMesh.new();box.size=Vector3(8,1,8);box.material=Paint.make_material(definition)
	var cpu:Mesh=Cpu.capture(box);var data:=Cook.pack({[0]:{"mesh":cpu,"source":cpu}},"","house_prefab_v1")
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	record.building={"id":"texture_fixture","part":"main/baked_0","role":"shell","floor":0,"floor_y":0.}
	record.prefab_locked=true;record.prefab_materials=[definition.duplicate(true)]
	var blueprint=preload("res://scripts/world3d/building_blueprint.gd")
	doc.map_meta.building_instances={"texture_fixture":{"version":blueprint.VERSION,"parameters":blueprint.defaults(),"position":[0.,0.,0.],"yaw":0.,"baked":true,"parts":{record.building.part:id},"signatures":{record.building.part:blueprint.geometry_signature(record)}}}
	check(Prefab.valid(record),"tiny frozen payload is valid")
	# Keep an unrelated render entry live; targeted invalidation must preserve it.
	var plain:=record.duplicate(true);var plain_definition:Dictionary=plain.prefab_materials[0]
	for field in Paint.MAP_FIELDS:plain_definition.erase(field)
	Prefab.retarget_materials(plain)
	var unrelated:=Prefab.geometry(plain);var target:=Prefab.geometry(record)
	Prefab.invalidate_texture_materials({definition.normal_path:true})
	check(is_same(Prefab.geometry(record),target),"normal format distinguishes flipped cache key")
	Prefab.invalidate_texture_materials({definition.normal_path+"|flip_y":true})
	check(not Prefab._meshes.has(record.house_prefab.sha256) and is_same(Prefab.geometry(plain),unrelated),"flipped normal invalidates only dependent prefab caches")
	return record
