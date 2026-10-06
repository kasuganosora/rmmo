extends SceneTree
const TileId = preload("res://scripts/map/tile_id.gd")
const Blit = preload("res://scripts/map/tile_blit.gd")
const Pack = preload("res://scripts/map/tilemap_pack.gd")
const ROOT := "D:/code/rmmo_runtime/style_work/town_m"
var failed := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL ", label)

func run() -> void:
	check(not TileId.is_visible(8192), "MV sentinel remains invalid")
	check(TileId.is_extra(16384) and not TileId.is_autotile(16384), "curve IDs never auto-connect")
	check(not TileId.is_visible(32768), "extended ID bounds")
	var pack = Pack.load_pack("user://content/packs/default", "Axel256")
	check(pack.width == 256 and pack.height == 256, "persisted town dimensions")
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/curves.json"))
	var object_sheets: Array = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/object_sheets.json"))
	check(pack.sheets.size() == 9 + spec.extra_sheets.size() + object_sheets.size() + 1, "runtime loads all curve and object pages")
	var sample := Image.create(48,48,false,Image.FORMAT_RGBA8)
	for i in range(int(spec.unique_tiles)):
		var tid: int = 16384 + i
		var page: int = 9 + i / 256
		var j: int = i % 256
		var sx: int = (j / 128 * 8 + j % 8) * 48
		var sy: int = ((j % 128) / 8) * 48
		if page >= pack.sheets.size() or pack.sheets[page] == null:
			check(false,"missing curve page");break
		var source: Image = pack.sheets[page]
		sample.fill(Color(0,0,0,0))
		Blit.blit_tile(sample,tid,0,0,pack.sheets)
		var expected := Image.create(48,48,false,Image.FORMAT_RGBA8)
		expected.blend_rect(source,Rect2i(sx,sy,48,48),Vector2i.ZERO)
		check(sample.get_data()==expected.get_data(),"curve native blit %d" % i)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/plan.json"))
	var farmland: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/farmland.json"))
	var farm_shapes := {}
	for cell in farmland.cells:
		var actual: int = pack.collision.tile_id(int(cell.x), int(cell.y), 0)
		check(TileId.is_autotile(actual) and TileId.autotile_kind(actual) == TileId.autotile_kind(int(cell.tile_id)), "persisted farm uses its A2 soil/crop material")
		farm_shapes[TileId.autotile_shape(actual)] = true
	check(farm_shapes.size() >= 9, "farms include connected interiors, edges and corners")
	var expected_layers := {}
	for z in [1,2,3]:
		var expected := PackedInt32Array();expected.resize(256*256);expected_layers[z]=expected
	for layer in spec.layers:
		var z := int(layer.z)
		if expected_layers.has(z):
			for cell in layer.cells:expected_layers[z][int(cell.y)*256+int(cell.x)]=int(cell.tile_id)
	for cell in plan.objects:expected_layers[3][int(cell.y)*256+int(cell.x)]=int(cell.tile_id)
	for cell in plan.plants:expected_layers[3][int(cell.y)*256+int(cell.x)]=int(cell.tile_id)
	var upgrade: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/scene_upgrade.json"))
	for cell in upgrade.cells:expected_layers[int(cell.z)][int(cell.y)*256+int(cell.x)]=int(cell.tile_id)
	for z in [1,2,3]:
		var mismatches := 0
		for y in range(256):
			for x in range(256):
				if pack.collision.tile_id(x,y,z)!=expected_layers[z][y*256+x]:mismatches+=1
		check(mismatches==0, "layer %d has no stale stamp remnants (%d mismatches)" % [z,mismatches])
	var expected_meta := PackedInt32Array();expected_meta.resize(256*256)
	for cell in plan.blocked:expected_meta[int(cell[1])*256+int(cell[0])]|=4
	for cell in plan.bridge_pass:expected_meta[int(cell[1])*256+int(cell[0])]|=8
	for cell in upgrade.lamp_feet:expected_meta[int(cell[1])*256+int(cell[0])]=4
	var bad_meta := 0
	for y in range(256):
		for x in range(256):
			if pack.collision.meta_at(x,y)!=expected_meta[y*256+x]:bad_meta+=1
	check(bad_meta==0, "all collision metadata matches geometry (%d mismatches)" % bad_meta)
	var col = pack.collision
	for y in range(244,253):
		check(col.can_pass_tiles(148,y,2), "southeast road crosses full wall thickness")
	for tid in [109,110,111]:
		check((pack.flags[tid] & 16) == 0, "low crops stay below player")
	var sprites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/sprites.json"))
	var tree: Dictionary = sprites.mature_tree
	for row in range(int(tree.h)):
		for x in range(int(tree.w)):
			var tid := int(tree.tiles[row * int(tree.w) + x])
			check(((pack.flags[tid] & 16) != 0) == (row < int(tree.h)-1), "tree canopy occludes behind, trunk base allows foreground")
	for layer in spec.layers:
		if layer.name == "wall_top":
			check(int(layer.z) == 3, "wall crown has separate upper map layer")
			for c in layer.cells:
				check((pack.flags[int(c.tile_id)] & 16) != 0, "wall crown renders above player")
		elif layer.name == "wall":
			check(int(layer.z) == 2, "wall body has lower map layer")
	var bridge_checks: Array = []
	for span in spec.bridge_spans:
		var a := Vector2(float(span[0][0]),float(span[0][1]))
		var b := Vector2(float(span[1][0]),float(span[1][1]))
		var from := Vector2i(a.floor())
		var to := Vector2i(b.floor())
		var bounds := Rect2i(Vector2i(a.min(b).floor()) - Vector2i(3,3), Vector2i((a-b).abs().ceil()) + Vector2i(8,8))
		var pending: Array[Vector2i] = [from]
		var visited := {from:true}
		var cursor := 0
		while cursor < pending.size() and not visited.has(to):
			var cell := pending[cursor];cursor += 1
			for dir in [2,4,6,8]:
				var next := cell + TileId.dir_delta(dir)
				if bounds.has_point(next) and not visited.has(next) and col.can_pass_tiles(cell.x,cell.y,dir):
					visited[next] = true;pending.append(next)
		var ok: bool = visited.has(to)
		check(ok, "bridge locally joins both banks")
		bridge_checks.append({"from":str(from),"to":str(to),"passed":ok})
	for cell in plan.blocked:
		check(not col.check_passage(int(cell[0]),int(cell[1]),1),"blocked geometry")
	for cell in plan.bridge_pass:
		check(col.check_passage(int(cell[0]),int(cell[1]),1),"bridge passage")
	# Actual runtime collision, not just the planning bitmap.
	var start := Vector2i(int(plan.start.x),int(plan.start.y))
	var queue: Array[Vector2i] = [start]
	var seen := {start:true}
	var pos := 0
	while pos < queue.size():
		var c: Vector2i = queue[pos];pos += 1
		for dir in [2,4,6,8]:
			var next: Vector2i = c + TileId.dir_delta(dir)
			if not seen.has(next) and col.can_pass_tiles(c.x,c.y,dir):
				seen[next]=true;queue.append(next)
	var unreachable: Array = []
	for obj in plan.buildings:
		if obj.get("kind","") == "wall":continue
		var door := Vector2i(int(obj.door[0]),int(obj.door[1]))
		if not seen.has(door):unreachable.append(obj)
	check(unreachable.is_empty(),"every building entrance reachable from guild")
	var report := {"passed":failed==0,"checks":checks,"failed":failed,"reachable_cells":seen.size(),"unreachable_entrances":unreachable,"bridges":bridge_checks,"curve_tiles":spec.unique_tiles,"size":[pack.width,pack.height]}
	var f := FileAccess.open(ROOT + "/runtime_acceptance.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify(report))
	quit(0 if failed==0 else 1)
