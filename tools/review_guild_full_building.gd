extends "res://tools/review_axel_guild_finish.gd"
func draw_scene(scene:Node,views:Array)->void:
	views.append_array([
		{"name":"guest_single","eye":[24.7,6.15,-1.0],"aim":[22.8,5.5,-3.4],"fov":76.0},
		{"name":"guest_twin","eye":[28.0,6.15,-1.0],"aim":[30.3,5.5,-3.5],"fov":76.0},
		{"name":"washroom","eye":[28.1,6.15,-9.2],"aim":[30.4,5.5,-11.6],"fov":76.0},
		{"name":"stair","eye":[12.5,1.7,-9.9],"aim":[3.0,5,-9.9],"fov":66.0}
	])
	report.generator=Compiled.generator();report.engine=Engine.get_version_info()
	await super.draw_scene(scene,views)
