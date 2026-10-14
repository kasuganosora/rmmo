extends SceneTree
## Headless opt-in, shared-resource isolation and native PackedScene contract.
## Optical appearance/transmission is deliberately left to coordinated GPU QA.
const Glass=preload("res://scripts/world3d/tinted_glass.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("%s: %s"%["PASS" if value else "FAIL",label])
func recipe()->Dictionary:return {"version":1,"materials":{"Rose ruby":{"transmittance":[.65,.06,.035],"roughness":.13}}}
func array_mesh(material:Material)->ArrayMesh:
	var a:Array=[];a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	a[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	a[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);result.surface_set_material(0,material);return result
func instance(parent:Node3D,name_:String,mesh:ArrayMesh,optin:Variant=null)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name_;node.mesh=mesh;parent.add_child(node);node.owner=parent
	if optin!=null:node.set_meta("extras",{Glass.KEY:optin})
	return node
func run()->void:
	var shared:=StandardMaterial3D.new();shared.resource_name="Rose ruby";shared.albedo_color=Color(.8,.4,.3,.4)
	shared.metallic=.2;shared.roughness=.72;shared.clearcoat_enabled=true;shared.emission_enabled=true;shared.emission=Color(.1,.2,.3);shared.refraction_enabled=true
	var mesh:=array_mesh(shared)
	var scene:=Node3D.new();scene.name="TintedGlassFixture"
	var a:=instance(scene,"OptedA",mesh,recipe());var b:=instance(scene,"OptedB",mesh,recipe());var untouched:=instance(scene,"UnmarkedShared",mesh)
	check(Glass.valid(recipe()),"valid explicit named material recipe")
	Glass.apply(scene)
	var tint:=a.get_active_material(0) as StandardMaterial3D
	check(tint!=null and not is_same(tint,shared),"opt-in creates independent override")
	check(is_same(tint,b.get_active_material(0)),"same eligible source and recipe reuse conversion")
	check(is_same(untouched.get_active_material(0),shared) and is_same(mesh.surface_get_material(0),shared),"unmarked sibling and shared mesh material untouched")
	check(shared.albedo_color==Color(.8,.4,.3,.4) and shared.emission_enabled and shared.refraction_enabled and is_equal_approx(shared.roughness,.72),"source authored properties unchanged")
	check(tint.blend_mode==BaseMaterial3D.BLEND_MODE_MUL and tint.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,"transmission uses native unshaded multiply")
	check(tint.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and tint.metallic==0 and not tint.emission_enabled and not tint.refraction_enabled,"transmission has no emission/refraction/metal")
	var wanted:=Color(.65*.96,.06*.96,.035*.96,1).linear_to_srgb()
	check(tint.albedo_color.is_equal_approx(wanted),"linear transmittance converts once to material sRGB")
	var reflected:=tint.next_pass as StandardMaterial3D
	check(reflected!=null and reflected.next_pass==null and reflected.blend_mode==BaseMaterial3D.BLEND_MODE_ADD and reflected.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"one dielectric additive PBR next pass")
	check(reflected.metallic==0 and is_equal_approx(reflected.roughness,.13) and not reflected.emission_enabled and not reflected.refraction_enabled,"reflection has requested roughness without emission/refraction")
	Glass.apply(scene)
	check(is_same(tint,a.get_active_material(0)) and is_same(reflected,tint.next_pass),"repeated application is idempotent and does not chain passes")
	var other:=recipe();other.materials["Rose ruby"].transmittance=[.035,.06,.65]
	var c:=instance(scene,"DifferentRecipe",mesh,other);Glass.apply(scene)
	check(not is_same(c.get_active_material(0),tint) and a.get_active_material(0).albedo_color.is_equal_approx(wanted),"different recipe keeps per-instance colour independent")
	var missing:=recipe();missing.materials={"No matching surface":{"transmittance":[.2,.3,.4]}}
	var d:=instance(scene,"UnmatchedName",mesh,missing);Glass.apply(scene)
	check(is_same(d.get_active_material(0),shared),"valid unmatched material name has no side effects")
	var invalids:Array=[null,[],{}, {"version":2,"materials":recipe().materials},{"version":1,"materials":{}}, {"version":1,"materials":[]}, {"version":1,"materials":{"":{}}}]
	for bad_rgb:Variant in [[0,.1,.2],[-.01,.1,.2],[1.01,.1,.2],[NAN,.1,.2],[INF,.1,.2],["0.2",.1,.2],[.1,.2]]:
		var invalid:=recipe();invalid.materials["Rose ruby"].transmittance=bad_rgb;invalids.append(invalid)
	for bad_rough:Variant in [.019,.601,NAN,INF,".13"]:
		var invalid:=recipe();invalid.materials["Rose ruby"].roughness=bad_rough;invalids.append(invalid)
	var mixed:=recipe();mixed.materials["Second invalid slot"]={"transmittance":[.1,0,.2]};invalids.append(mixed)
	for i in invalids.size():
		var item:=instance(scene,"Invalid%d"%i,mesh,invalids[i])
		check(not Glass.valid(invalids[i]),"invalid recipe rejected %d"%i)
		Glass.apply(item)
		check(item.get_surface_override_material(0)==null and is_same(item.get_active_material(0),shared),"invalid recipe leaves all material slots untouched %d"%i)
		item.free()
	# A ShaderMaterial remains unsupported; the opt-in must not coerce it.
	var shader:=ShaderMaterial.new();shader.resource_name="Rose ruby"
	var shader_node:=instance(scene,"UnsupportedShader",array_mesh(shader),recipe());Glass.apply(scene)
	check(is_same(shader_node.get_active_material(0),shader),"non-Standard material preserved")
	shader_node.free()
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack converted scene")
	check(Compiled._valid_packed(packed),"existing static native schema accepts both StandardMaterial passes")
	packed.set_meta("compiled_asset_validated",true)
	var before:=Footprint.measure(packed)
	check(not before.is_empty() and before.materials>=5,"existing footprint walks linked reflection material")
	var folder:=Paths.cache_directory("tinted_glass_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	var target:=folder+"/fixture.scn"
	check(ResourceSaver.save(packed,target,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"native compressed save")
	scene.free();packed=null
	var reopened:PackedScene=ResourceLoader.load(target,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened!=null and Compiled._valid_packed(reopened),"native reload retains supported closed graph")
	if reopened!=null:
		var loaded:=reopened.instantiate()
		var after:StandardMaterial3D=loaded.get_node("OptedA").get_active_material(0)
		check(after.blend_mode==BaseMaterial3D.BLEND_MODE_MUL and after.albedo_color.is_equal_approx(wanted) and after.next_pass is StandardMaterial3D and after.next_pass.blend_mode==BaseMaterial3D.BLEND_MODE_ADD,"native preserves multiply/transmittance/reflection recipe")
		check(after.get_meta(Glass.STAMP,"")==JSON.stringify(recipe().materials["Rose ruby"],"",true),"native preserves idempotence stamp")
		Glass.apply(loaded);check(is_same(after,loaded.get_node("OptedA").get_active_material(0)),"native reapply remains idempotent")
		var measured:=Footprint.measure(reopened)
		check(not measured.is_empty() and measured.materials==before.materials,"native footprint retains material graph cost")
		loaded.free()
	var report:Dictionary={"checks":checks,"failures":failures,"native_path":target,"script_sha":FileAccess.get_sha256("res://scripts/world3d/tinted_glass.gd"),"generator":Compiled.generator(),"headless":true,"scope":"CPU contracts, native save/reopen and existing footprint; optical appearance needs GPU", "stats":before}
	var file:=FileAccess.open(folder+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("TINTED_GLASS checks=",checks," failures=",failures," evidence=",folder+"/result.json")
	quit(0 if failures==0 else 1)
