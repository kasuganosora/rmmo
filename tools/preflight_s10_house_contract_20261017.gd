extends SceneTree
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Embedded=preload("res://scripts/world3d/embedded_glb.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017/v5/s10_court_shutter_house.glb";var sha:=FileAccess.get_sha256(path)
	var d:=Imported.source_descriptor(path,sha);var first:Variant=JSON.parse_string(JSON.stringify(d));var second:Variant=JSON.parse_string(JSON.stringify(first))
	var passed:=Embedded.can_copy(path) and Imported.valid_descriptor(d) and Imported.same(d,first) and Imported.same(first,second)
	var proof:Dictionary={"passed":passed,"source_sha256":sha,"byte_copy_eligible":Embedded.can_copy(path),"valid_descriptor":Imported.valid_descriptor(d),"first_json_roundtrip_same":Imported.same(d,first),"second_json_roundtrip_same":Imported.same(first,second),"fixtures":d.get("fixtures",{}).size(),"members":d.get("members",{}).size()}
	var file:=FileAccess.open(path.get_basename()+"_contract_preflight.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"  "));file.close();print(JSON.stringify(proof));quit(0 if passed else 1)
