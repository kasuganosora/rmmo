extends "res://tools/probe_axel_vegetation_tree_capacity.gd"
## Read-only exact current authoring precheck, no HTTP placement or map writes.
func result_path()->String:return OUT+"/vegetation_basal_support_capacity_review.json"
func sample_grid(region:Dictionary)->Dictionary:return {"id":region.id,"grid_not_repeated":true,"current_clear":0,"all_non_frozen_rules_clear":0,"geometry_refined_clear":0,"samples_inside":0}
func simulate(refined:bool)->Array:
 if refined:return [] # Authoring still keeps all existing conservative obstacles.
 return super.simulate(false)
func append_additional_probe():
 probe_result.basal_support_evidence=report.get("basal_support_evidence",{})
 probe_result.tree_support_error=tree_support_error
 probe_result.scope="Exact current helper deterministic 350-attempt capacity; all original full-crown obstacles retained, no native placements or saved scene"
 probe_result.actual_precheck_total=0
 for row:Dictionary in probe_result.current_seed_20261016:probe_result.actual_precheck_total+=row.count
