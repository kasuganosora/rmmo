extends "res://tools/test_town_grass.gd"
func run()->void:
	create_timer(600).timeout.connect(func():quit(2))
	manifest=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/town_grass/manifest.json"))
	entries=JSON.parse_string(FileAccess.get_file_as_string(out+"/validation.json")).entries
	await render_review();print("GRASS_VISUAL_CHECK_FAILURES ",failed);quit(1 if failed else 0)
