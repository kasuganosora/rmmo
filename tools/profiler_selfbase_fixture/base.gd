extends RefCounted
signal native_work(loops:int)
var sink:int=0
func inherited_work(loops:int)->int:
    var sum_:int=0
    for i:int in loops:
        sum_=(sum_+i*17)%1000003
    sink=sum_
    return sum_
func _on_native_work(loops:int)->void:
    var sum_:int=0
    for i:int in loops:
        sum_=(sum_+i*19)%1000003
    sink=sum_
