extends "res://child.gd"
func inherited_work(loops:int)->int:
    return super.inherited_work(loops)+1
