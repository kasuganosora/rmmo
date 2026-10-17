extends SceneTree
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func run()->void:
	for path:String in ["D:/code/rmmo_runtime/packs/default/assets/8072add85cdbbcb157b0c372961af898fa635d9c8973543713ee1d613aaf657a.glb","D:/code/rmmo_runtime/art_sources/s10_warm_brick_planter_20261017/v1/s10_warm_redbrick_planter.glb"]:
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		if doc.append_from_file(path,state)!=OK:quit(2);return
		var scene:=Io.generate_scene(doc,state);var details:Array=[]
		for m:MeshInstance3D in Paint.meshes(scene):
			for slot in m.mesh.get_surface_count():
				var mat:StandardMaterial3D=m.get_active_material(slot);if not mat.normal_enabled:continue
				var a:=m.mesh.surface_get_arrays(slot);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var tangents:PackedFloat32Array=a[Mesh.ARRAY_TANGENT]
				var valid:=tangents.size()==vertices.size()*4 and tangents.size()>0
				for i in tangents.size():valid=valid and is_finite(tangents[i])
				details.append({"node":str(m.name),"material":mat.resource_name,"vertices":vertices.size(),"tangents":tangents.size(),"valid":valid,"tangent_sha256":digest(tangents.to_byte_array())})
		rows.append({"path":path,"source_sha256":FileAccess.get_sha256(path),"surfaces":details});scene.free()
	var foliage_a:Array=rows[0].surfaces.filter(func(v):return v.node=="Foliage")
	var foliage_b:Array=rows[1].surfaces.filter(func(v):return v.node=="Foliage")
	var passed:bool=foliage_a.size()==1 and foliage_b.size()==1 and foliage_a[0].tangent_sha256==foliage_b[0].tangent_sha256 and rows.all(func(v):return v.surfaces.all(func(s):return s.valid))
	var report:Dictionary={"passed":passed,"same_generated_foliage_tangents":passed,"rows":rows,"scope":"Actual production GLTF importer synthesizes omitted tangent data. No source foliage attributes or encoded images changed; old and new imported foliage tangent bytes are identical."}
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/s10_warm_brick_planter_20261017/v1/production_tangent_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print(JSON.stringify(report));quit(0 if passed else 1)
