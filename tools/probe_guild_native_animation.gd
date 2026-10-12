extends "res://tools/review_guild_full_batch.gd"
func run()->void:
	for id in ['guild_guest_nightstand','guild_guest_low_cabinet']:
		var packed:PackedScene=load(REVIEW_ROOT+'/library/'+id+'/asset.scn');var scene:=packed.instantiate()
		put(REVIEW_ROOT+'/library/'+id+'/animation_after.json',animation_signature(scene))
		scene.free()
	quit()
