extends "res://tools/test_reference_grass_clumps.gd"
func run()->void:
	manifest=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/reference_grass_clumps/manifest.json"))
	for row in manifest:entries.append({"id":row.id,"entry":{"asset_path":row.file}})
	await render_review();quit()
