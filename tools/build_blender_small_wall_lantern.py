"""Door-side pointed lantern, isolated review asset with day/night previews."""
import bpy,math,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT.parent/'rmmo_runtime/art_sources/small_wall_lantern';OUT.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mat(name,c,rough=.65,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;return m
iron=mat('Weathered dark iron',(.035,.047,.043),.58,.75);glass=mat('Slightly aged lantern glass',(.48,.58,.48),.23);glass.node_tree.nodes.get('Principled BSDF').inputs['Transmission Weight'].default_value=.85
nt=iron.node_tree;p=nt.nodes.get('Principled BSDF')
n=nt.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=115;n.inputs['Detail'].default_value=3
r=nt.nodes.new('ShaderNodeValToRGB');r.color_ramp.elements[0].color=(.025,.028,.025,1);r.color_ramp.elements[1].color=(.12,.10,.074,1);nt.links.new(n.outputs['Fac'],r.inputs[0]);nt.links.new(r.outputs[0],p.inputs['Base Color'])
b=nt.nodes.new('ShaderNodeBump');b.inputs['Strength'].default_value=.2;b.inputs['Distance'].default_value=.0007;nt.links.new(n.outputs['Fac'],b.inputs['Height']);nt.links.new(b.outputs[0],p.inputs['Normal'])
gp=glass.node_tree.nodes.get('Principled BSDF');gp.inputs['Base Color'].default_value=(.83,.88,.81,1);gp.inputs['Roughness'].default_value=.09;gp.inputs['Transmission Weight'].default_value=1
# Thin clear panes transmit direct candle shadow rays; camera rays retain glass.
gn=glass.node_tree;lp=gn.nodes.new('ShaderNodeLightPath');clear=gn.nodes.new('ShaderNodeBsdfTransparent');mix=gn.nodes.new('ShaderNodeMixShader');gn.links.new(lp.outputs['Is Shadow Ray'],mix.inputs[0]);gn.links.new(gp.outputs[0],mix.inputs[1]);gn.links.new(clear.outputs[0],mix.inputs[2]);gn.links.new(mix.outputs[0],gn.nodes.get('Material Output').inputs['Surface'])
wax=mat('Warm candle wax',(.65,.49,.23));flame=mat('Night only warm flame',(1,.36,.055));fp=flame.node_tree.nodes.get('Principled BSDF');fp.inputs['Emission Color'].default_value=(1,.27,.035,1)
def mesh(name,vs,fs,m):
    d=bpy.data.meshes.new(name);d.from_pydata(vs,[],fs);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(m);return o
def box(name,p,s,m):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.scale=s;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m);be=o.modifiers.new('Soft iron edge','BEVEL');be.width=.003;be.segments=2;return o
def tube(name,pts,r,m):
    d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.bevel_depth=r;d.bevel_resolution=2;s=d.splines.new('POLY');s.points.add(len(pts)-1)
    for p,c in zip(s.points,pts):p.co=(*c,1)
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(m);return o
box('Wall mounting plate',(0,-.012,0),(.075,.024,.27),iron)
for z in [-.09,.09]:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,radius=.011,location=(0,-.029,z));bpy.context.object.data.materials.append(iron);bpy.context.object.name='Mounting rivet'
tube('Curled support',[(0,-.025,-.06),(0,-.065,-.12),(0,-.15,-.13),(0,-.22,-.07),(0,-.24,.02),(0,-.24,.09)],.013,iron)
support=bpy.context.collection.objects.get('Curled support');old=support.data.splines[0];coords=[p.co.xyz.copy() for p in old.points];support.data.splines.remove(old);s=support.data.splines.new('BEZIER');s.bezier_points.add(len(coords)-1)
for point,co in zip(s.bezier_points,coords):point.co=co;point.handle_left_type='AUTO';point.handle_right_type='AUTO'
support.data.resolution_u=16
tube('Decorative lower curl',[(0,-.07-.045*math.cos(t),-.17-.045*math.sin(t)) for t in [k*math.pi*1.65/32 for k in range(33)]],.009,iron)
cy=-.24
for z,r in [(.075,.087),(.12,.11),(.40,.13),(.425,.155)]:
    tube('Hexagonal frame rim',[(r*math.cos(a*math.tau/6),cy+r*math.sin(a*math.tau/6),z) for a in range(7)],.010,iron)
for j in range(6):
    a=j*math.tau/6;b=(j+1)*math.tau/6
    tube('Lantern vertical frame',[(.11*math.cos(a),cy+.11*math.sin(a),.12),(.13*math.cos(a),cy+.13*math.sin(a),.40)],.008,iron)
    vs=[(r*math.cos(t),cy+r*math.sin(t),z) for r,z in [(.108,.125),(.128,.395)] for t in [a,b]]
    o=mesh('Separate glazing panel',vs,[(0,1,3,2)],glass);o.modifiers.new('Thin glass','SOLIDIFY').thickness=.0014
vs=[(.16*math.cos(j*math.tau/6),cy+.16*math.sin(j*math.tau/6),.43) for j in range(6)]+[(0,cy,.575)]
roof=mesh('Pointed six-sided weather roof',vs,[(j,(j+1)%6,6) for j in range(6)],iron);roof.modifiers.new('Sheet metal thickness','SOLIDIFY').thickness=.002
bev=roof.modifiers.new('Folded roof softened edges','BEVEL');bev.width=.0015;bev.segments=3
tube('Roof finial',[(0,cy,.56),(0,cy,.63)],[.01][0],iron)
bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=.026,depth=.12,location=(0,cy,.19));bpy.context.object.name='Replaceable candle';bpy.context.object.data.materials.append(wax)
bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=.109,depth=.006,location=(0,cy,.121));bpy.context.object.name='Solid lantern floor';bpy.context.object.data.materials.append(iron)
bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.043,depth=.008,location=(0,cy,.127));bpy.context.object.name='Candle socket dish';bpy.context.object.data.materials.append(iron)
tube('Candle wick',[(0,cy,.25),(0,cy,.258)],.0018,iron)
for z in [.19,.33]:tube('Glazing door hinge',[(.057,cy-.10,z-.012),(.057,cy-.10,z+.012)],.006,iron)
box('Glazing door latch',(-.055,cy-.104,.265),(.018,.009,.012),iron)
bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=.016,location=(0,cy,.268));fire=bpy.context.object;fire.name='Night flame';fire.scale=(.6,.6,1.8);fire.data.materials.append(flame);fire.hide_render=True
fire.visible_shadow=False
root=bpy.data.objects.new('WALL_MOUNT_ORIGIN',None);bpy.context.collection.objects.link(root);root['mount_plane']='Y=0; faces local -Y';root['night_light_socket']=[0,cy,.268];root['status']='offline review, no game lighting integration'
parts=[o for o in bpy.context.scene.objects if o!=root]
for o in parts:o.parent=root
bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
    if o.type=='CURVE':bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');o.select_set(False)
bpy.ops.object.select_all(action='SELECT');bpy.ops.export_scene.gltf(filepath=str(OUT/'small_wall_lantern.glb'),export_format='GLB',use_selection=True)
wall=mat('Review pale plaster',(.55,.51,.42));box('Review wall',(0,.10,.20),(2,.18,2.2),wall)
scene=bpy.context.scene;scene.world.use_nodes=True;world=scene.world.node_tree.nodes['Background'];world.inputs[0].default_value=(.62,.70,.82,1);world.inputs[1].default_value=.55
bpy.ops.object.light_add(type='AREA',location=(-1,-2,2));area=bpy.context.object;area.data.energy=200;area.data.size=2;area.rotation_euler=(Vector((0,0,.25))-area.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='POINT',location=(0,cy,.268));light=bpy.context.object;light.name='Preview warm light only';light.data.color=(1,.48,.15);light.data.energy=0;light.data.shadow_soft_size=.004
bpy.ops.object.camera_add(location=(1,-2,1));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.15,.22))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=1.15;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.view_settings.view_transform='AgX';scene.unit_settings.system='METRIC'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'small_wall_lantern.blend'))
scene.render.filepath=str(OUT/'wall_lantern_day.png');bpy.ops.render.render(write_still=True)
world.inputs[1].default_value=.035;area.data.energy=5;fire.hide_render=False;fp.inputs['Emission Strength'].default_value=4;light.data.energy=9
scene.render.filepath=str(OUT/'wall_lantern_night.png');bpy.ops.render.render(write_still=True)
(OUT/'asset.json').write_text(json.dumps({'height_m':.845,'width_m':.32,'mount':'Y=0, outward -Y','light_socket':[0,cy,.268],'status':'offline review','game_integration':False},indent=2))
print('SMALL_WALL_LANTERN_COMPLETE')
