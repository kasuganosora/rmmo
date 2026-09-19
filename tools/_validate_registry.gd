extends SceneTree

class MockMcp extends Node:
	func _tool(nm, desc, params = {}, required = []):
		return {"name": nm, "description": desc, "inputSchema": {"p": params, "r": required}}

func _init() -> void:
	var bad := 0
	var OpsScript = load("res://scripts/editor/adapters/editor_mcp_ops.gd")
	if OpsScript == null:
		print("FAIL load facade"); quit(); return
	var ops = OpsScript.new()
	ops.mcp = MockMcp.new()
	# registry build
	ops._build_op_registry()
	var reg = ops._op_registry
	print("registry ops:", reg.size())
	# every registered op maps to a module that has the method
	for op in reg:
		var m = reg[op]
		if not m.has_method(op):
			print("FAIL no-method ", op); bad += 1
	# tools_list aggregates
	var tl = ops.tools_list()
	print("tools_list entries:", tl.size())
	if tl.size() != 55:
		print("FAIL tools_list size (expect 55, got ", tl.size(), ")"); bad += 1
	# dispatch unknown op -> error dict (tests lookup path w/o editor state)
	var r = ops.dispatch("__nope__", {})
	if not (r is Dictionary and str(r.get("error", "")).begins_with("unknown tool")):
		print("FAIL dispatch-unknown ", r); bad += 1
	# every module op_names count sum == 57
	var total := 0
	for m in ops._op_modules:
		total += m.op_names().size()
	print("sum op_names:", total)
	if total != 57:
		print("FAIL op_names total (expect 57, got ", total, ")"); bad += 1
	print("REGISTRY_OK=", bad == 0, " bad=", bad)
	quit()
