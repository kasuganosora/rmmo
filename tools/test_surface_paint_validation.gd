extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func entry_for(node:MeshInstance3D)->Dictionary:
	var geo:=Paint.geometry(node)
	return {"mesh":".","surface":0,"face":geo.surfaces[0].faces.keys()[0],"geometry":geo.surfaces[0].signature,"mapping":"planar","scale":[1.,1.],"offset":[0.,0.],"rotation":0.,"material":{"name":"preflight contract","color":[.3,.4,.5,1.],"roughness":.8}}
func rejected(node:MeshInstance3D,entry:Dictionary,label:String)->void:
	var before:=var_to_bytes(entry)
	var validation:=Paint.validate_paint(node,[entry])
	var build:=Paint.painted_mesh(node,[entry])
	check(not validation.ok and not build.ok and validation.error==build.error,label+" uses the same rejection before and during construction")
	check(var_to_bytes(entry)==before,label+" never changes authoring data")
func run()->void:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new()
	var entry:=entry_for(node)
	var materials_before:=Paint._materials.size()
	var source:=node.mesh
	var validation:=Paint.validate_paint(node,[entry])
	check(validation.ok and not validation.has("mesh"),"valid preflight prepares no disposable mesh")
	check(Paint._materials.size()==materials_before and node.mesh==source,"preflight neither creates a painted material nor changes source geometry")
	var built:=Paint.painted_mesh(node,[entry])
	check(built.ok and built.mesh.get_surface_count()==2,"actual construction splits the requested face")
	var stale:=entry.duplicate(true);stale.geometry="stale"
	rejected(node,stale,"stale geometry")
	var wrong_face:=entry.duplicate(true);wrong_face.face=999999
	rejected(node,wrong_face,"missing face")
	var missing:=entry.duplicate(true);missing.material.texture_path="C:/outside-missing-preflight.png"
	rejected(node,missing,"unreadable texture")
	var arrays:=source.surface_get_arrays(0);arrays[Mesh.ARRAY_TEX_UV]=null;arrays[Mesh.ARRAY_TANGENT]=null
	var no_uv:=MeshInstance3D.new();no_uv.mesh=ArrayMesh.new();no_uv.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var uv:=entry_for(no_uv);uv.mapping="uv"
	rejected(no_uv,uv,"missing original UV")
	node.free();no_uv.free()
	print("PAINT_VALIDATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
