extends "res://tools/test_building_shadow_proxy.gd"
const Preview=preload("res://scripts/world_editor/building_shadow_preview.gd")

func run()->void:
	Preview.enabled=true;Shadow.enabled=true
	var cpu:=Cpu.new();var material:=StandardMaterial3D.new()
	for i in 2:
		var mesh:=BoxMesh.new()
		cpu.surfaces.append(mesh.surface_get_arrays(0));cpu.materials.append(material)
	var mesh:=cpu.restore()
	var a:=piece(mesh);var b:=piece(mesh)
	var record:Dictionary={"prefab_locked":true,"house_prefab":{},"building":{}}
	var before:int=material.changed.get_connections().size()
	check(Preview.attach(record,a) and Preview.attach(record,b),"two sources can monitor shared resources independently")
	check(material.changed.get_connections().size()==before+2,"each weak closure has a distinct signal connection")
	material.emit_changed()
	check(not a.has_meta("building_shadow_proxy") and not b.has_meta("building_shadow_proxy"),"one resource event invalidates all sharing sources")
	check(material.changed.get_connections().size()==before,"invalidation disconnects all weak closures")
	check(Preview.attach(record,a) and Preview.attach(record,b),"sources can reattach without duplicate connections")
	a.free();b.free()
	check(material.changed.get_connections().size()==before,"deleting sources disconnects resource listeners")
	await process_frame;Preview.enabled=false
	print("EDITOR_SHADOW_LISTENERS_FINISHED failures=",failures)
	quit(1 if failures else 0)
