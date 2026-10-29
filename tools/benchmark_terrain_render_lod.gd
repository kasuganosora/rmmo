extends SceneTree
## Added preparation cost, kept separate from renderer draw/primitive benefits.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const L=preload("res://scripts/world3d/terrain_render_lod.gd")
const G=preload("res://scripts/world3d/ground_batch_geometry.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/staged_far_20261017/terrain_preparation.json"
func _initialize()->void:run.call_deferred()
func run()->void:
	var record:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(64)
	for z in 65:
		for x in 65:record.terrain_mesh.heights[z*65+x]=.1*sin(x*.08)+.08*cos(z*.07)
	var material:=StandardMaterial3D.new();var surfaces:Array=T.arrays(record);var members:Array=[{"record":record,"surfaces":surfaces,"transform":Transform3D.IDENTITY,"materials":[material,material],"keys":[G.material_key(material),G.material_key(material)]}]
	var measurements:Array=[]
	for i in 10:
		for enabled:bool in ([false,true] if i%2==0 else [true,false]):
			L.enabled=enabled;var started:=Time.get_ticks_usec();var data:=G.build(members,Vector3.ZERO,true);var elapsed:float=(Time.get_ticks_usec()-started)/1000.
			measurements.append({"round":i,"enabled":enabled,"ms":elapsed,"serialized_work_bytes":var_to_bytes(data).size()})
	L.enabled=true
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"grid":[64,64],"measurements":measurements,"scope":"bounded CPU batch preparation, no upload; extra work runs on existing background geometry workers"},"  "))
	print("TERRAIN_LOD_PREPARATION samples=",measurements.size());quit()
