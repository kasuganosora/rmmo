extends RefCounted
## Query owners retain source identity, never collider readiness.
var spec:Dictionary
var mesh:Mesh
var pose:=Transform3D.IDENTITY
var local_bounds:=AABB()
var area:=Rect2()
var initialized:=false
# Only producer-owned geometry receives a narrow envelope. Public mutable
# sources use their original coarse index coverage instead.
var query_envelope:=Rect2()
var has_query_envelope:=false
var level:=4.0
var low:=Vector2i.ZERO
var high:=Vector2i.ZERO
func _init(source:Dictionary)->void:spec=source
