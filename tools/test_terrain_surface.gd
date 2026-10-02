extends SceneTree
const T=preload("res://scripts/world3d/terrain_surface.gd")
var failures:=0
func check(value: bool, message: String) -> void:
	if not value: failures+=1; push_error(message)
	else: print("PASS "+message)
static func fixture() -> Dictionary:
	var heights: Array=[]; heights.resize(81); heights.fill(0.0)
	var holes: Array=[]; holes.resize(64); holes.fill(false)
	return {"uuid":"terrain_test","kind":"box","surface_id":"ground","position":[0,0,0],"rotation":[0,0,0],"size":[8,1,8],"collision":"walk","terrain_mesh":{"version":1,"columns":8,"rows":8,"floor":-8.0,"heights":heights,"holes":holes}}
func _initialize() -> void:
	var r:=fixture(); check(T.valid(r),"heightfield dimensions and schema")
	var bad:=r.duplicate(true); bad.terrain_mesh.heights.pop_back(); check(not T.valid(bad),"malformed grid rejected")
	var args:={"id":r.uuid,"mode":"raise","points":[[0,0]],"radius":2.0,"strength":2.0}
	var raised:=T.stroke(r,args); check(raised.ok and is_equal_approx(T.sample(raised.record,Vector3.ZERO),2) and T.sample(r,Vector3.ZERO)==0,"raise is pure and applies center strength")
	var low:=T.stroke(r,args.merged({"mode":"lower"},true)); check(low.ok and T.sample(low.record,Vector3.ZERO)==-2,"lower digs a real pit")
	var flat:=T.stroke(raised.record,args.merged({"mode":"flatten","target_height":0,"strength":20},true)); check(flat.ok and T.sample(flat.record,Vector3.ZERO)==0,"flatten targets an explicit height")
	var smooth:=T.stroke(raised.record,args.merged({"mode":"smooth","strength":1},true)); check(smooth.ok and T.sample(smooth.record,Vector3.ZERO)<2 and T.sample(smooth.record,Vector3.ZERO)>0,"smooth reads a snapshot of neighbors")
	var hole:=T.stroke(r,args.merged({"mode":"hole","radius":1},true)); check(hole.ok and hole.record.terrain_mesh.holes.count(true)==4 and is_nan(T.sample(hole.record,Vector3.ZERO)),"holes omit entire cells")
	var fill:=T.stroke(hole.record,args.merged({"mode":"fill","radius":1},true)); check(fill.ok and fill.record==r,"fill restores stored heights exactly")
	check(not T.stroke(r,args.merged({"mode":"hole","radius":32},true)).ok,"cannot erase whole patch by accident")
	check(not T.stroke(r,args.merged({"mode":"lower","strength":20},true)).ok,"reject bedrock underflow without partial mutation")
	check(not T.stroke(r,args.merged({"mode":"flatten"},true)).ok,"flatten requires height")
	var moved:=r.duplicate(true); moved.position=[12,7,-3]; moved.rotation=[0,90,0]
	var m:=T.stroke(moved,args.merged({"points":[[12,-3]],"mode":"flatten","target_height":8},true)); check(m.ok and T.sample(m.record,Vector3.ZERO)==1,"world height and XZ work on translated yaw terrain")
	var mesh:=T.mesh(hole.record,null); check(mesh.get_surface_count()==2,"many cells share two render surfaces")
	check(mesh.create_trimesh_shape().get_faces().size()>0,"mesh supplies runtime collision triangles")
	var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(hole.record)); check(T.valid(roundtrip) and T.mesh(roundtrip,null).get_faces()==mesh.get_faces(),"JSON roundtrip preserves exact geometry")
	print("TERRAIN_SURFACE_FINISHED failures=%d"%failures); quit(1 if failures else 0)
