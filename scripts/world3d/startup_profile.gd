extends RefCounted
## Which world the shipped game boots. The other world stays loadable.

const PROFILE_3D := "world3d"
const PROFILE_2D := "world2d"
const SCENE_3D := "res://scenes/world_3d.tscn"
const SCENE_2D := "res://scenes/world.tscn"


static func current() -> String:
	return str(ProjectSettings.get_setting("rmmo/startup_profile", PROFILE_2D))


static func scene_for(profile: String) -> String:
	if profile == PROFILE_3D:
		return SCENE_3D
	return SCENE_2D


static func startup_scene() -> String:
	return scene_for(current())
