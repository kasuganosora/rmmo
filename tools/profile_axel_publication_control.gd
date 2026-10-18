extends "res://tools/profile_axel_official_frames.gd"
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_publication_control.gd"]=FileAccess.get_sha256("res://tools/profile_axel_publication_control.gd")
	return result
func run()->void:
	var enabled:=not "--ordinary-publication-validation" in OS.get_cmdline_user_args()
	preload("res://scripts/world3d/stream_index_preparation.gd").native_snapshot_validation_enabled=enabled
	report.publication_control={"native_snapshot_validation":enabled}
	await super.run()
