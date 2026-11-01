extends SceneTree
const Data=preload("res://scripts/world3d/world_map_data.gd")
var checks:=0
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1;print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func oracle_less(a:Dictionary,b:Dictionary)->bool:
	if a.height!=b.height:return a.height<b.height
	if a.map_draw_order!=b.map_draw_order:return a.map_draw_order<b.map_draw_order
	return a.source_order<b.source_order
func run()->void:
	var host:=Node.new();var mesh:=BoxMesh.new();mesh.size=Vector3(2,.2,3)
	var specs:Array=[]
	for i in 512:
		specs.append({"uuid":"part_%d"%i,"mesh":mesh,"transform":Transform3D(Basis(Vector3.UP,float(i%3)*.13),Vector3(float(i%16)*4,float((i*13)%7)*.1,float(i/16)*4)),"map_draw_order":i%11,"extras":{}})
	host.set_meta("stream_library",specs)
	var data:=Data.new();data.build(host)
	check(data.shapes.size()==512,"actual build projects all512 footprints")
	var expected:Array=data.shapes.duplicate();expected.sort_custom(oracle_less)
	check(data.shapes==expected,"initial storage keeps height/draw-order/source-order painter semantics")
	var identity:=true
	for i in data.shapes.size():identity=identity and data._paint_order[i]==i and data.shapes[i].draw_order==i and data.shapes[i].draw_id==i
	check(identity,"rank/storage mapping and public draw IDs remain exact")
	var queries:Array[Rect2]=[Rect2(0,0,30,30),Rect2(-100,-100,400,400)]
	for query:Rect2 in queries:
		var wanted:Array=expected.filter(func(shape):return query.intersects(shape.bounds))
		check(data.visible_shapes(query)==wanted,"initial indexed/fallback visibility matches independent painter oracle")
	data.shapes.reverse();data.rebuild_shape_index()
	for query:Rect2 in queries:
		var wanted:Array=expected.filter(func(shape):return query.intersects(shape.bounds))
		check(data.visible_shapes(query)==wanted,"same-count reordered storage preserves visual order")
	var addition:Dictionary=specs[0].duplicate();addition.uuid="new_lower";addition.transform=Transform3D(Basis.IDENTITY,Vector3(1,-2,1))
	var appended:Dictionary=data.append_resident_specs([addition])
	check(appended.ok and data.shapes.size()==513,"incremental append remains supported after ordinary rebuild")
	var all:Array=data.shapes.duplicate();all.sort_custom(oracle_less)
	check(data.visible_shapes(Rect2(-100,-100,400,400))==all,"late lower footprint merges into painter order")
	var empty:=Node.new();data.build(empty)
	check(data.shapes.is_empty() and data._paint_order.is_empty() and data.visible_shapes(Rect2(-1,-1,2,2)).is_empty(),"rebind to empty map clears both representations")
	host.free();empty.free()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
