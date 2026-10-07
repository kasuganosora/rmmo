extends SceneTree
const Prepare=preload("res://scripts/world_editor/terrain_load_preparation.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
var failures:=0
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func fixture(id:String,offset:float)->Dictionary:
	var heights:Array=[];var holes:Array=[]
	for z in 5:
		for x in 5:heights.append(.002*pow(offset+x*2-4,2)+.01*z)
	holes.resize(16);holes.fill(false);holes[5]=true
	return {"uuid":id,"kind":"box","surface_id":"grass","position":[offset,0,0],"rotation":[0,0,0],"size":[8,1,8],"terrain_mesh":{"version":1,"columns":4,"rows":4,"floor":-1.,"heights":heights,"holes":holes}}
func _initialize()->void:run.call_deferred()
func run()->void:
	var a:=fixture("left",0);var b:=fixture("right",8)
	a.terrain_regions={"materials":[{"name":"soil","color":[1,1,1,1],"roughness":1.}],"regions":[{"id":"field","layer":0,"opacity":.8,"feather":.5,"polygon":[[-3,-3],[3,-3],[3,3],[-3,3]],"furrows":{"angle":17.,"height":.1,"margin":.5,"setback":.2,"spacing":2.,"phase":0.}}]}
	var records:Array=[a,b,{"uuid":"unrelated","kind":"box"}]
	var before:=var_to_bytes(records)
	var context:=Neighbors.new();context.update(records)
	var expected:Dictionary={}
	for record:Dictionary in [a,b]:expected[record.uuid]=Terrain.arrays(record,context.data[record.uuid])
	var expected_mask:=Regions.mask(a).get_data()
	var normals_before:=var_to_bytes(context.data.left.normals)
	var worker:=Thread.new()
	if worker.start(Prepare.prepare.bind(records,context))!=OK:
		check(false,"private CPU preparation worker starts");quit(1);return
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check(result.surfaces.size()==2 and result.masks.size()==1,"only terrain geometry and existing region masks are prepared")
	for id:String in expected:
		check(var_to_bytes(result.surfaces[id])==var_to_bytes(expected[id]),"worker matches synchronous vertices/normals/UV/tangents/indices for "+id)
	check(result.surfaces.left.size()==3 and result.surfaces.left[2][Mesh.ARRAY_VERTEX].size()>0,"cultivation surface remains present")
	check(result.surfaces.left[0][Mesh.ARRAY_INDEX].size()==15*6,"hole omits exactly one top cell")
	check(result.masks.left.get_data()==expected_mask,"worker region mask matches every synchronous pixel")
	check(var_to_bytes(records)==before and var_to_bytes(context.data.left.normals)==normals_before,"worker leaves authoring records and neighbor normals unchanged")
	check(not context.data.left.has("region_mask"),"preparation never persists a mask in editable neighbor context")
	var edited:=a.duplicate(true);edited.terrain_mesh.heights[12]+=.02
	edited.terrain_regions.regions[0].opacity=.3
	var edited_context:=Neighbors.new();edited_context.update([edited])
	var next:=Prepare.prepare([edited],edited_context)
	check(next.masks.left.get_data()!=expected_mask and var_to_bytes(next.surfaces.left)!=var_to_bytes(result.surfaces.left),"later geometry and region edits prepare fresh payloads")
	print("TERRAIN_LOAD_PREPARATION failures=",failures);quit(failures)
