extends Node3D
## The parent source drives a render group only when its world pose changes.
var changed:Callable
func _ready()->void:set_notify_transform(true)
func _notification(what:int)->void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and changed.is_valid():changed.call()
