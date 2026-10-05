extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/house_flicker"
func _initialize()->void:call_deferred("run")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var doc=Doc.open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	var near:Array=[]
	for id in doc.map_meta.building_instances:
		var instance:Dictionary=doc.map_meta.building_instances[id]
		near.append({"id":id,"distance":Vector2(instance.position[0]+169.8,instance.position[2]+25.5).length(),"instance":instance})
	near.sort_custom(func(a,b):return a.distance<b.distance)
	for row in near.slice(0,3):print("NEAR ",row.id," distance=",row.distance," position=",row.instance.position)
	var id:String=near[0].id;var instance:Dictionary=near[0].instance
	var records:Array=doc.records.filter(func(r):return r.get("building",{}).get("id")==id)
	var rows:Array=[]
	for record:Dictionary in records:
		if not record.has("house_prefab") or record.has("fixture"):continue
		var mesh:Mesh=Prefab.geometry(record).mesh
		for slot in mesh.get_surface_count():
			var a:Array=mesh.surfaces[slot];var verts:Array=[];var normals:Array=[]
			for v:Vector3 in a[Mesh.ARRAY_VERTEX]:verts.append(B.arr(v+B.vec(record.position)))
			for v:Vector3 in a[Mesh.ARRAY_NORMAL]:normals.append(B.arr(v))
			var material:StandardMaterial3D=mesh.surface_get_material(slot)
			rows.append({"part":record.building.part,"slot":slot,"vertices":verts,"normals":normals,"indices":Array(a[Mesh.ARRAY_INDEX]),"rotation":record.rotation,"position":record.position,"material":material.resource_name if material!=null else "","paint":material.get_meta("runtime_paint_definition",{}) if material!=null else {},"cull":material.cull_mode if material!=null else -1})
	var file:=FileAccess.open(OUT+"/geometry.json",FileAccess.WRITE);file.store_string(JSON.stringify({"house":near[0],"surfaces":rows}));file.close()
	quit()
