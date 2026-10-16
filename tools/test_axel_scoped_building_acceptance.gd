extends "res://tools/publish_axel_town_layout.gd"
func run()->void:pass # Never invoke the inherited publication entry point.
func finish()->void:pass # Tests never emit publication receipts.
func _init()->void:call_deferred("test_scoped")
func test_scoped()->void:
 var path=OUT+"/functional_inputs/23f2bc3baa18d039c6c9749a7e0ca36ba033628c5dbd9d7a631ea5514869c104.json"
 var data=read(path);var sha=FileAccess.get_sha256(path);var placements=[]
 for key in ["guardhouse","church","watermill"]:
  var model=data.formal_publications[key]
  placements.append({"key":key,"source_sha256":model.source.sha256,"asset_path":model.asset_id})
 var receipt={"building_inputs":{"path":path,"sha256":sha,"scope_token":City.token(data)},"inputs":{path:sha},"placements":placements,"handoff_observation":{"path":"mutable unrelated handoff need not exist","sha256":"old"}}
 building_inventory(receipt)
 var positive=failures==0
 print("SCOPED positive=",positive)
 var original=failures;receipt.building_inputs.scope_token="tampered";building_inventory(receipt)
 var rejected=failures>original
 print("SCOPED token tamper rejected=",rejected)
 receipt.building_inputs.scope_token=City.token(data);receipt.placements[0].source_sha256="wrong"
 original=failures;building_inventory(receipt)
 var source_rejected=failures>original
 print("SCOPED placed source mismatch rejected=",source_rejected)
 print("SCOPED_TEST ",positive and rejected and source_rejected)
 quit(0 if positive and rejected and source_rejected else 1)
