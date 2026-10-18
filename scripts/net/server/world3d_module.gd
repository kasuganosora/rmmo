extends RefCounted
## Mock server domain: world3d.

var ctrl

## @server-state
var _world3d_worker = null

## @server-state
var world3d_summons: WeakRef

## @server-state
var world3d_state = preload("res://scripts/world3d/world_state.gd").new()

## @server-state
var world3d_events

## @server-state
var world3d_authority = preload("res://scripts/world3d/world_authority.gd").new()

## @server-state
var sky_authority := preload("res://scripts/net/server/sky_module.gd").new()


func _init(owner):
	ctrl = owner
	world3d_events = preload("res://scripts/world3d/world_events.gd").new(ctrl)

## @server-api
func mount_world3d_sky(map_id: String, path: String) -> void:
	if ctrl.sky_authority.maps.has(map_id): return
	var settings := preload("res://scripts/world3d/environment_settings.gd").defaults()
	if preload("res://scripts/world3d/map_paths.gd").allowed(path) and FileAccess.file_exists(path):
		# Weather only needs server-owned environment metadata. Reopening the
		# complete editor document here revalidates every painted face on the
		# main thread after the runtime loader has already finished the map.
		var Doc=preload("res://scripts/world3d/world_document.gd")
		var EnvironmentSettings=preload("res://scripts/world3d/environment_settings.gd")
		var native: Dictionary=Doc.authoritative_extras(path,null,true)
		if native.has("extras"):
			if EnvironmentSettings.valid(native.extras): settings=EnvironmentSettings.resolve(native.extras)
		elif not native.has("error"):
			var document=Doc.open_file(path)
			if document!=null: settings=EnvironmentSettings.resolve(document.map_meta)
	ctrl.sky_authority.ensure_map(map_id,settings)

## @server-api
func register_loaded_world3d_environment(path:String, extras:Dictionary)->void:
	var id:=str(extras.get("map_ref",""))
	if not preload("res://scripts/world3d/world_location.gd").map_ref_ok(id):id="prototype/map_"+path.sha256_text().substr(0,16)
	if ctrl.sky_authority.maps.has(id):return
	var settings=preload("res://scripts/world3d/environment_settings.gd")
	if settings.valid(extras):ctrl.sky_authority.ensure_map(id,settings.resolve(extras))

## @server-api
func snapshot_world3d_sky(map_id: String) -> Dictionary:
	return ctrl.sky_authority.snapshot(map_id,Time.get_ticks_msec()/1000.0)

## @server-api
func try_set_world3d_environment(map_id: String, changes: Dictionary) -> Dictionary:
	return ctrl.sky_authority.set_environment(map_id,changes,Time.get_ticks_msec()/1000.0)

## @server-api
func issue_world3d_meteor(map_id: String, event: Dictionary) -> bool:
	return ctrl.sky_authority.meteor(map_id,event)

## @server-api
func issue_world3d_meteor_shower(map_id: String, command: Dictionary) -> bool:
	return ctrl.sky_authority.meteor_shower(map_id,command)

## @server-api
func issue_world3d_lightning(map_id: String, event: Dictionary) -> bool:
	return ctrl.sky_authority.lightning(map_id,event)

## @server-api
func try_move_world(sequence: int, direction: Vector3, speed_mps: float, jump:bool=false) -> Dictionary:
	return ctrl.world3d_authority.move_intent(sequence, direction, speed_mps,jump)

## @server-api
func world3d_mount_actors(table) -> void:
	ctrl.world3d_release_actors()
	var worker = load("res://scripts/world3d/chunk_actor_worker.gd").new()
	worker.start(table)
	ctrl._world3d_worker = worker

## @server-api
func world3d_release_actors() -> void:
	if ctrl._world3d_worker != null:
		ctrl._world3d_worker.stop()
		ctrl._world3d_worker = null

## @server-api
func world3d_actor_generation() -> int:
	if ctrl._world3d_worker == null:
		return 0
	return int(ctrl._world3d_worker.latest().get("generation", 0))

## @server-api
func try_world3d_chunk(player_x: float, player_z: float, view_m: float = -1.0) -> Dictionary:
	if ctrl._world3d_worker == null:
		return {"ok": false, "actors": [], "view": [], "sent": 0, "visible": 0, "total": 0}
	var radius := preload("res://scripts/net/server/mock_config.gd").number("chunk_view_radius_m") if view_m < 0.0 else view_m
	ctrl._world3d_worker.kick(Vector3(player_x, 0.0, player_z), radius)
	return ctrl._world3d_worker.latest()
