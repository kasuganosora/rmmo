extends SceneTree
## Pure CPU complement to the actual HTTP plot transaction regression.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok:failures+=1
func tile(id:String,position:Vector3,scale_y:float=1.,yaw:float=0.,columns:int=16)->Dictionary:
	var heights:Array=[];heights.resize((columns+1)*17);heights.fill((3.-position.y)/scale_y)
	var holes:Array=[];holes.resize(columns*16);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[position.x,position.y,position.z],"rotation":[0.,yaw,0.],"size":[16.,scale_y,16.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":columns,"rows":16,"floor":-20.,"heights":heights,"holes":holes}}
func world_height(r:Dictionary,p:Vector2)->float:
	var at:=Terrain.transform(r).affine_inverse()*Vector3(p.x,0,p.y)
	return float(r.position[1])+Terrain.sample(r,at)
func run()->void:
	var args:Dictionary={"id":"a","mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":10.,"plot_depth":2.,"plot_yaw":45.,"blend_margin":1.,"target_height":7.,"strength":1.}
	var a:=tile("a",Vector3.ZERO);var made:=Terrain.stroke(a,args)
	check(made.ok,"diagonal native rectangle succeeds")
	check(absf(world_height(made.record,Vector2(3,-3))-7.)<.00001,"positive house yaw runs along world +X minus Z")
	check(absf(world_height(made.record,Vector2(3,3))-3.)<.00001,"perpendicular diagonal remains outside the narrow plot")
	check(a.terrain_mesh.heights.all(func(h):return h==3.),"pure preparation does not mutate its source")
	var translated:=tile("a",Vector3(1024,11,512),2.5)
	var translated_args:Dictionary=args.merged({"points":[[1024.,512.]]},true)
	var offset:=Terrain.stroke(translated,translated_args)
	check(offset.ok and absf(world_height(offset.record,Vector2(1027,509))-7.)<.00001,"world target survives horizontal translation vertical offset and height scaling")
	check(absf(world_height(offset.record,Vector2(1027,515))-3.)<.00001,"outside ground retains its original absolute world height")
	var rotated:=Terrain.stroke(tile("a",Vector3.ZERO,1.,90.),args)
	check(rotated.ok and absf(world_height(rotated.record,Vector2(3,-3))-7.)<.00001 and absf(world_height(rotated.record,Vector2(3,3))-3.)<.00001,"rotating the terrain does not rotate a world-authored plot")
	var partial:=Terrain.stroke(a,args.merged({"strength":.25},true))
	check(partial.ok and absf(world_height(partial.record,Vector2.ZERO)-4.)<.00001,"fractional rectangle strength is a bounded blend without overshoot")
	var yaw:=37.;var basis:=Basis(Vector3.UP,deg_to_rad(yaw));var center:=Vector3(640,4,768)
	var left:=tile("left",center+basis*Vector3(-8,0,0),1.5,yaw,16)
	var right:=tile("right",center+basis*Vector3(8,0,0),.75,yaw,8)
	var seam_args:Dictionary=args.merged({"id":"left","points":[[640.,768.]],"plot_width":12.,"plot_depth":10.,"plot_yaw":yaw,"blend_margin":3.},true)
	var joined:=Batch.prepare([left,right],left,seam_args)
	check(joined.ok and joined.entries.size()==2,"mixed cell widths and height scales join in rotated world space")
	if joined.ok:
		var lo:Dictionary=joined.entries.filter(func(e):return e.record.uuid=="left")[0].record
		var hi:Dictionary=joined.entries.filter(func(e):return e.record.uuid=="right")[0].record
		check(Batch.validate_edge_continuity(left,right,lo,hi).ok,"complete shared edge remains continuous after rotated soft falloff")
		var lh:float=lo.position[1]+lo.terrain_mesh.heights[8*17+16]*lo.size[1]
		var rh:float=hi.position[1]+hi.terrain_mesh.heights[8*9]*hi.size[1]
		check(absf(lh-7.)<.00001 and absf(rh-7.)<.00001,"both seam endpoints of the central plateau hit the same absolute target")
	print("HOUSE_PLOT_COORDINATES failures=",failures);quit(failures)
