extends "res://scripts/net/combat/inventory.gd"
## Instance-preserving read model. Its contents only come from server snapshots.
func snapshot()->Array:
	return _stacks.duplicate(true)

func get_qty(reference:String)->int:
	var total:=0
	for row:Dictionary in _stacks:
		if reference==str(row.id) or reference==str(row.get("definition_id","")):total+=int(row.qty)
	return total

func grant_starter()->void:pass
