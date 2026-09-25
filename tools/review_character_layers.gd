extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
var ROOT:String = ArtPaths.path("character_creator/Motion/")
func _initialize() -> void:
	var result := Image.create(96*8,96*8,false,Image.FORMAT_RGBA8)
	result.fill(Color("252936"))
	var names := ["Body_p01_m001", "Clothing2_p01_m007", "Clothing1_p01_m007", "Boots_p01_m007", "Belt_p01_m007", "Eyes_p01_m002", "FrontHair1_p01_m003"]
	for name in names:
		var sheet := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "Male/TV_" + name + ".png"))
		for action in range(8):
			for direction in range(8):
				result.blend_rect(sheet, Rect2i(192,(action*8+direction)*96,96,96),Vector2i(direction*96,action*96))
	result.resize(1536,1536,Image.INTERPOLATE_NEAREST)
	result.save_png(ArtPaths.path("character_creator/equipment_review.png"))
	quit()
