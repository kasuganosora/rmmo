extends "res://base.gd"
func inherited_work(loops:int)->int:
    return super.inherited_work(loops)+1
func native_direct_emit(loops:int)->int:
    return emit_signal("native_work",loops)
func native_selfbase_emit(loops:int)->int:
    return super.emit_signal("native_work",loops)
func builtin_signal_emit(loops:int)->void:
    native_work.emit(loops)
func native_selfbase_id()->int:
    return super.get_instance_id()
