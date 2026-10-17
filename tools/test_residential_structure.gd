extends "res://tools/test_residential_access.gd"
const Support=preload("res://scripts/world_editor/residential_support.gd")
const G=preload("res://scripts/world3d/building_geometry.gd")

static func arch_parameters()->Dictionary:
	return {"layout":"hall","template":"house","width":12.,"depth":12.,"floors":2,"floor_height":3.3,"rooms_per_floor":2,"style":"plaster","compound":"none","roof_axis":"depth","roof_pitch":39.,"dormers":0,"front_canopy":false,"jetty":0.,"base_height":.3,"entrance_style":"round_arch_hall","entrance_arch_width":2.28,"entrance_arch_spring":3.67}

static func pier_records()->Array:
	# Geometry-only regression fixture. No asset/production model is authored.
	var p:Dictionary={"records":[]}
	G.box(p,"f0/floor",Vector3(0,2.5,0),Vector3(4,.2,4),[.5,.5,.5],0,"floor")
	for x in [-1.75,1.75]:
		for z in [-1.75,1.75]:G.box(p,"f0/pier_%s_%s"%[x,z],Vector3(x,.7,z),Vector3(.5,3.4,.5),[.5,.5,.5],0,"foundation")
	for r:Dictionary in p.records:r.building.floor_y=2.5
	return p.records

func run()->void:
	var started:=Time.get_ticks_usec()
	var arch:=Blueprint.generate(arch_parameters());check(arch.ok,"existing arched hall recipe generates")
	var frozen_arch:=frozen(arch.records);var entry:=Access.entrance(frozen_arch,0.)
	check(entry.ok and entry.get("kind")=="passage","frozen arch retains explicit portal and proves actual floor/clearance",entry)
	if entry.ok:
		check(evaluate(frozen_arch).ok,"actual arched threshold and exterior treads connect to ground")
		var bad:=frozen_arch.duplicate(true)
		for r:Dictionary in bad:
			for hint:Dictionary in r.get("residential_portals",[]):hint.position[0]+=3.
		check(not Access.entrance(bad,0.).ok,"a forged portal hint cannot cut through actual masonry")
		var rotated:Array=preload("res://scripts/world_editor/residential_placement_tools.gd")._oriented({"records":frozen_arch,"building_instances":{}},37.).records
		var turned:=Access.entrance(rotated,37.,entry.entrance_id)
		check(turned.ok and turned.outward.distance_to(Basis(Vector3.UP,deg_to_rad(37.))*Vector3.FORWARD)<.00001,"portal orientation follows actual frozen pose")
	var multi:=Blueprint.generate({"layout":"townhouse","template":"house","width":11.,"depth":14.,"floors":2,"compound":"rear_workshop","annex_floors":1,"base_height":.3,"front_canopy":false})
	check(multi.ok,"existing native house and rear workshop supplies multiple exterior entrances")
	var frozen_multi:=frozen(multi.records);var choices:=Access.entrances(frozen_multi,0.)
	check(choices.size()>=2,"catalog exposes stable external door identities")
	check(not Access.entrance(frozen_multi,0.).ok,"ambiguous entrances never select first silently")
	for choice:Dictionary in choices:
		var picked:=Access.entrance(frozen_multi,0.,choice.id)
		check(picked.ok,"explicit native exterior door resolves: "+choice.id,picked)
	check(Access.entrance(frozen_multi,0.,"missing").get("code")=="entrance_not_found","unknown entrance is rejected")
	var ordinary:=frozen(native().records);var ordinary_entry:=Access.entrance(ordinary,0.)
	var other:Dictionary=ordinary.filter(func(r):return r.get("fixture",{}).get("id")==ordinary_entry.fixture_id and r.get("collision")!="none")[0].duplicate(true)
	other.uuid="other_exterior_fixture";other.fixture.id="f0/north/other/door";other.position=Blueprint.arr(Blueprint.vec(other.position)+ordinary_entry.outward*1.8);ordinary.append(other)
	var blocked:=evaluate(ordinary)
	check(blocked.get("code")=="entrance_clearance","another moving door cannot occupy selected entrance corridor",blocked)
	var piers:=frozen(pier_records());var doc:=Document.new();doc.records=[field()]
	var settings:Dictionary={"layout":"townhouse"};var fixed:Dictionary={"min_y":0.,"max_y":0.,"support_mode":"piers"}
	var result:=Support.solve(doc,piers,Vector3.ZERO,0.,settings,fixed)
	check(result.ok,"four actual closed piers support a raised slab",result)
	if result.ok:
		check(result.support.components.size()==4 and result.support.underfloor_clearances.size()==1,"only four real footing domains require terrain; void has separate clearance proof")
	doc.records[0].terrain_mesh.holes[16*32+16]=true
	check(Support.solve(doc,piers,Vector3.ZERO,0.,settings,fixed).ok,"real hole between piers is not filled or required for support")
	doc.records[0].terrain_mesh.holes[17*32+17]=true
	check(not Support.solve(doc,piers,Vector3.ZERO,0.,settings,fixed).ok,"hole under an actual pier rejects")
	doc.records=[field()];doc.records[0].terrain_mesh.heights[16*33+16]=1.
	check(not Support.solve(doc,piers,Vector3.ZERO,0.,settings,fixed).ok,"soil mound under raised slab cannot consume 1.8 m clearance")
	doc.records=[field()]
	check(not Support.solve(doc,piers,Vector3.ZERO,0.,settings,{"min_y":0.,"max_y":0.}).ok,"continuous mode does not invent a full foundation under piers")
	var forged:=piers.duplicate(true)
	for r:Dictionary in forged:
		if r.building.role=="floor":r._support_piers=[{"uuid":"invented","position":[0.,-100.,0.],"size":[4.,200.,4.],"rotation":[0,0,0]}]
	check(not Support.solve(doc,forged,Vector3.ZERO,0.,settings,{"min_y":0.,"max_y":0.}).ok,"imported private proof fields cannot forge supporting geometry")
	var ground:=field();ground.position=[10000.,0.,-10000.];doc.records=[ground]
	check(Support.solve(doc,piers,Vector3(10000.,0.,-10000.),17.,settings,fixed).ok,"scalar-double pier hull preserves far translated rotated support")
	doc.records=[field()]
	var missing:=pier_records();missing.pop_back()
	check(not Support.solve(doc,frozen(missing),Vector3.ZERO,0.,settings,fixed).ok,"three remaining supports cannot claim unsupported slab corner")
	finish(started)
