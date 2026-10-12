extends Node
## Editor-only derived shadows for immutable baked building parts. No frame poll.
const Shadow=preload("res://scripts/world3d/building_shadow_proxy.gd")
static var enabled:=true
var source:WeakRef
var resources:Array[Resource]=[]
var callback:Callable

static func attach(record:Dictionary,visual:Node3D)->bool:
	if not visual is MeshInstance3D:return false
	if visual.has_meta("editor_shadow_monitor"):
		var previous=visual.get_meta("editor_shadow_monitor").get_ref()
		if previous!=null:previous.restore()
	if not enabled or visual.mesh==null:return false
	# Authoring operations reject material/geometry/wind edits to locked prefabs.
	# Instance preview overrides are deliberately outside this stable contract.
	if not record.get("prefab_locked",false) or not record.has("house_prefab") or not record.has("building"):return false
	if record.has("wind_response") or visual.is_in_group("world3d_wind_receivers") or visual.get_meta("extras",{}).has("rmmo_wind"):return false
	if visual.material_override!=null or visual.material_overlay!=null or visual.transparency!=0:return false
	for slot in visual.mesh.get_surface_count():
		if visual.get_surface_override_material(slot)!=null:return false
	if not Shadow.attach(visual):return false
	var proxy:MeshInstance3D=visual.get_meta("building_shadow_proxy")
	proxy.set_meta("editor_shadow_proxy",true)
	var monitor=load("res://scripts/world_editor/building_shadow_preview.gd").new()
	monitor.source=weakref(visual)
	# Resource signals must not retain a scene node through a bound method.
	var reference:WeakRef=weakref(monitor)
	monitor.callback=func():_changed(reference)
	monitor.resources.append(visual.mesh)
	for slot in visual.mesh.get_surface_count():
		var material:Material=visual.get_active_material(slot)
		if material!=null and not monitor.resources.has(material):monitor.resources.append(material)
	for resource:Resource in monitor.resources:resource.changed.connect(monitor.callback)
	visual.set_meta("editor_shadow_monitor",weakref(monitor))
	proxy.add_child(monitor)
	return true

static func _changed(reference:WeakRef)->void:
	var monitor=reference.get_ref()
	if monitor!=null:monitor.restore()

func disconnect_resources()->void:
	for resource:Resource in resources:
		if resource.changed.is_connected(callback):resource.changed.disconnect(callback)
	resources.clear()

func restore()->void:
	disconnect_resources()
	var node:MeshInstance3D=source.get_ref() if source!=null else null
	if node==null:return
	var proxy:Node=node.get_meta("building_shadow_proxy",null)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.remove_meta("building_shadow_proxy");node.remove_meta("editor_shadow_monitor")
	if is_instance_valid(proxy):
		# Remove immediately from rendering, but do not free the executing callback.
		node.remove_child(proxy);proxy.queue_free()

func _exit_tree()->void:disconnect_resources()

func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:disconnect_resources()
