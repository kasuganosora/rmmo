extends SceneTree
const B=preload("res://scripts/world3d/building_blueprint.gd")
const F=preload("res://scripts/world3d/building_fixtures.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	var recipes:=B.medieval_presets()+B.town_presets()+B.urban_presets()+[{"parameters":B.defaults()},{"parameters":B.medieval_presets()[2].parameters.merged({"depth":24.0,"rooms_per_floor":3},true)}]
	var doors:=0
	for recipe:Dictionary in recipes:
		var plan:=B.generate(recipe.parameters)
		if not plan.ok:failures+=1;push_error(str(plan));continue
		for swap:Dictionary in plan.interior_door_replacements:
			var leaf:Dictionary=swap.leaf;var closed:=Transform3D(Basis.from_euler(B.vec(leaf.rotation)*PI/180),B.vec(leaf.position))
			for yaw in [0,37,90,181,270]:
				var world:=Transform3D(Basis(Vector3.UP,deg_to_rad(yaw)),Vector3(42,3,-17))*closed
				var inward:=Basis(Vector3.UP,deg_to_rad(yaw))*B.vec(swap.inward)
				for fraction in [.25,.5,.75,1.0]:
					var pose:=F.pose(world,leaf.fixture,fraction)
					if (pose.origin-world.origin).dot(inward)<.05 or (pose*B.vec(leaf.fixture.pivot)).distance_to(world*B.vec(leaf.fixture.pivot))>.0001:failures+=1;push_error("wrong inward hinge "+swap.id)
			var placed_leaf:=leaf.duplicate(true);var placed_frame:Dictionary=swap.frame.duplicate(true)
			placed_leaf.building.id="test_house";placed_frame.building.id="test_house"
			if not F.valid(leaf) or swap.frame.has("fixture") or not B.valid_record(placed_leaf) or not B.valid_record(placed_frame):failures+=1;push_error("invalid door/frame")
			doors+=1
	print("INTERIOR_LAYOUT recipes=",recipes.size()," doors=",doors," failures=",failures);quit(1 if failures else 0)
