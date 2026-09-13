extends SceneTree

func _init() -> void:
	var CharsetSheet = load("res://scripts/char/charset_sheet.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	ProjectSettings.set_setting("rmmo/charset_root", "D:/code/rmmo_runtime/characters")
	var root: String = CharsetSheet.charset_root()
	print("charset_root=", root)
	var path: String = CharsetSheet.resolve_sheet_path("actor03_0001")
	print("actor path=", path, " exists=", FileAccess.file_exists(path))
	var img = CharsetSheet.load_image(path)
	print("actor image=", img.get_width() if img else 0, "x", img.get_height() if img else 0)
	var frames = CharsetSheet.build_sprite_frames("actor03_0001", 4)
	print("anims=", frames.get_animation_names())
	var path2: String = CharsetSheet.resolve_sheet_path("$Eternaler_TV02")
	print("tv path=", path2, " exists=", FileAccess.file_exists(path2))
	var pack = TilemapPack.load_pack("res://demo_map")
	print("pack npcs=", pack.npcs.size(), " warps=", pack.warps.size())
	print("extra_blocked count=", pack.collision.extra_blocked.size() if pack.collision else -1)
	var pack2 = TilemapPack.load_pack("res://bath_map")
	print("bath npcs=", pack2.npcs.size(), " blocked=", pack2.collision.extra_blocked.size())
	# Sample first npc
	if pack.npcs.size() > 0:
		print("first npc=", pack.npcs[0])
	quit(0)