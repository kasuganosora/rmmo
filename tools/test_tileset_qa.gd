extends SceneTree
const Qa = preload("res://scripts/editor/adapters/ops/tileset_qa_ops.gd")
const Blit = preload("res://scripts/map/tile_blit.gd")
var failed := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed += 1

func run() -> void:
	var b := Image.create(768,768,false,Image.FORMAT_RGBA8)
	check(Qa.image_errors(b,5).is_empty(),"empty B0 is valid")
	b.set_pixel(47,47,Color.WHITE)
	check(Qa.image_errors(b,5).has("B0_not_transparent"),"opaque B0 last pixel rejected")
	check(Qa.image_errors(Image.create(48,48,false,Image.FORMAT_RGBA8),0).has("dimensions"),"wrong dimensions rejected")
	check(Qa.image_errors(null,0).has("missing_or_unreadable"),"missing sheet rejected")
	var pack = load("res://scripts/editor/domain/content_pack.gd").new()
	pack.new_blank("qa_fixture","QA",24,24)
	var ed = load("res://scripts/editor/content_editor.gd").new()
	ed.pack = pack
	ed.doc = pack.get_map("Map001")
	ed.current_map_id = "Map001"
	var mcp = load("res://scripts/editor/adapters/editor_mcp.gd").new()
	root.add_child(mcp)
	mcp.editor = ed
	var before: PackedInt32Array = ed.doc.data.duplicate()
	var dirty_before: bool = ed.doc.dirty
	var audit: Dictionary = mcp.call_tool("audit_tileset",{"expected_sha256":{"not_declared":"bad"}})
	check(not audit.get("technical_passed",true),"undeclared expected sheet fails acceptance")
	check(str(audit.get("errors",[])).contains("expected_sheet_not_declared"),"diagnostic identifies missing declaration")
	var wrong: Dictionary = mcp.call_tool("preview_autotile_cases",{"kinds":[128]})
	check(not wrong.get("ok",true),"out of range kind rejected")
	var empty: Dictionary = mcp.call_tool("preview_autotile_cases",{"kinds":[]})
	check(not empty.get("ok",true),"empty fixtures rejected")
	check(not mcp.call_tool("preview_autotile_cases",{"kinds":"bad"}).get("ok",true),"malformed kinds returns a tool error")
	check(not mcp.call_tool("audit_tileset",{"expected_sha256":[]}).get("ok",true),"malformed manifest returns a tool error")
	var mismatch: Dictionary = mcp.call_tool("audit_tileset",{"expected_sha256":{"Outside_A1":"wrong"}})
	check(not mismatch.get("technical_passed",true) and str(mismatch.get("errors",[])).contains("unexpected_sha256"),"incorrect version fails acceptance")
	var am = root.get_node("AssetManager")
	var sheets: Array = []
	for suffix in ["A1","A2","A3","A4","A5","B","C"]:
		sheets.append(am.load_image("content://tilesheet/Outside_"+suffix))
	var cache_image: Image = sheets[0]
	var pixel_before := cache_image.get_pixel(0,0)
	cache_image.set_pixel(0,0,Color.MAGENTA)
	var stale: Dictionary = mcp.call_tool("audit_tileset",{})
	check(not stale.get("technical_passed",true) and str(stale.get("errors",[])).contains("stale_or_missing_cache"),"stale image cache fails acceptance")
	cache_image.set_pixel(0,0,pixel_before)
	var fixture := Qa.fixture_image(sheets,[0,16,48,80],0)
	check(fixture.get_size()==Vector2i(1344,1152),"native fixture dimensions")
	check(not fixture.is_invisible(),"fixture rendered")
	var motion := Qa.fixture_image(sheets,[0],1)
	var still := Qa.fixture_image(sheets,[0],0)
	check(motion.get_data()!=still.get_data(),"water animation appears in fixtures")
	check(ed.doc.data==before and ed.doc.dirty==dirty_before,"audit and fixtures preserve map")
	Blit._color_cache[123] = Color.RED
	Blit.clear_color_cache()
	check(Blit._color_cache.is_empty(),"reload can clear stale minimap colors")
	var red := Image.create(768,768,false,Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(768,768,false,Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var first_color := Blit.sample_color(1,[null,null,null,null,null,red])
	var second_color := Blit.sample_color(1,[null,null,null,null,null,blue])
	check(first_color==Color.RED and second_color==Color.BLUE,"different tilesets cannot share a stale minimap color")
	var ops_owner = load("res://scripts/editor/adapters/editor_mcp_ops.gd").new()
	var ops_weak: WeakRef = weakref(ops_owner)
	ops_owner._build_op_registry()
	ops_owner = null
	check(ops_weak.get_ref()==null,"MCP operation modules do not retain their owner")
	var combat_owner = load("res://scripts/net/combat/combat_engine.gd").new()
	var combat_weak: WeakRef = weakref(combat_owner)
	combat_owner = null
	check(combat_weak.get_ref()==null,"combat modules do not retain their owner")
	ed.free()
	mcp.free()
	print("TILESET_QA failures=",failed)
	quit(0 if failed==0 else 1)
