"""Reference-led v10 exterior components; neutral geometry only."""
import math


def build_exterior(api):
    import bpy
    box, mesh, beam = api['box'], api['mesh'], api['beam']
    TRIM, WOOD, DARK, WHITE = (api[k] for k in ['TRIM', 'WOOD', 'DARK', 'WHITE'])
    g = '12_Facade_Detail'
    # U19 stone entrance surround, stepped cornice, side walls and door lamps.
    for x in [14.20, 17.80]:
        box('Entry stone jamb', x, -.14, 1.73, .32, .70, 3.46, g, TRIM)
        box('Entry jamb capital', x, -.16, 3.42, .48, .78, .22, g, TRIM)
    for z,w,d,h in [(3.57,4.25,.90,.20),(3.75,4.55,1.02,.16),(3.92,4.85,1.14,.14)]:
        box('Entry stepped lintel',16,-.12,z,w,d,h,g,TRIM)
    for x in [12.75,19.25]:
        box('Entry low side parapet',x,-.92,.38,.28,1.70,.76,g,WHITE)
        box('Entry parapet cap',x,-.92,.81,.40,1.82,.12,g,TRIM)
    for x in [13.68,18.32]:
        # Reusable static lantern assembly, no emissive materials/light sources.
        root=bpy.data.objects.new('Guild facade wall lantern',None)
        api['SC'].collection.objects.link(root);api['register'](root,root.name,g,None,False)
        root['independent_prop']=True;root['asset_id']='guild_facade_wall_lantern'
        start=len(api['OBJECTS'])
        post=box('Facade lantern wall mount',x,-.30,2.25,.14,.18,.52,g,DARK)
        post['independent_prop']=True
        beam('Facade lantern bracket',(x,-.30,2.45),(x,-.67,2.45),.055,g,DARK,False)
        box('Facade lantern glass',x,-.68,2.06,.28,.24,.42,g,TRIM,collision=False)
        for dx in [-.15,.15]:
            for dy in [-.13,.13]:beam('Facade lantern rib',(x+dx,-.68+dy,1.83),(x+dx,-.68+dy,2.29),.028,g,DARK,False)
        box('Facade lantern base',x,-.68,1.81,.38,.34,.07,g,DARK,collision=False)
        mesh('Facade lantern hip cap',[(x+dx,-.68+dy,2.30) for dx,dy in [(-.22,-.20),(.22,-.20),(.22,.20),(-.22,.20)]]+[(x,-.68,2.50)],[(0,3,2,1),(0,1,4),(1,2,4),(2,3,4),(3,0,4)],g,DARK,False)
        root.location=(x,-.30,1.80)
        for part in api['OBJECTS'][start:]:part.parent=root;part.location-=root.location
    # Stone corner pilasters and plinth remain texture-free rather than brick meshes.
    for x in [.10,31.90]:box('Front corner pilaster',x,-.06,4.02,.28,.18,8.04,g,TRIM)
    for xa,xb in [(0,12.55),(19.45,32)]:box('Front stone plinth',(xa+xb)/2,-.04,.24,xb-xa,.18,.48,g,TRIM)


def build_heraldry(api):
    """U01 shield-bottom hanging cloth, independent from the wall and railing."""
    import bpy
    mesh,beam=api['mesh'],api['beam'];g='12_Facade_Detail'
    root=bpy.data.objects.new('Guild facade heraldry assembly',None)
    api['SC'].collection.objects.link(root);api['register'](root,root.name,g,None,False)
    root['independent_prop']=True;root['asset_id']='guild_facade_heraldry'
    start=len(api['OBJECTS'])
    outline=[(14.45,7.75),(17.55,7.75),(17.55,5.52),(16,4.75),(14.45,5.52)]
    vertices=[(x,-.86,z) for x,z in outline]+[(x,-.82,z) for x,z in outline]
    o=mesh('Guild shield banner',vertices,[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],g,api['WOOD'],False)
    o['independent_prop']=True;o['reference']='U01,U19';o['structural_wall']=False
    for i,(x,z) in enumerate(outline):
        x2,z2=outline[(i+1)%5]
        beam('Banner narrow border',(x,-.895,z),(x2,-.895,z2),.045,g,api['TRIM'],False)
    beam('Banner suspension rod',(14.24,-.86,7.90),(17.76,-.86,7.90),.065,g,api['WOOD'],False)
    for x in [14.65,15.30,16,16.70,17.35]:beam('Banner hanging loop',(x,-.86,7.72),(x,-.86,7.93),.04,g,api['TRIM'],False)
    # Whitebox bird silhouette indicates the reference emblem without colour/texture.
    wing=[(0,.65),(.26,.32),(.56,.55),(.84,.78),(1.02,.08),(.92,-.55),(.73,-.08),(.45,.13),(.16,-.12)]
    for sign in [-1,1]:
        mesh('Guild bird wing',[(16+sign*x,-.916,6.45+z) for x,z in wing],[tuple(range(len(wing)))],g,api['TRIM'],False)
    mesh('Guild bird body',[(16+x,-.923,6.45+z) for x,z in [(-.17,.51),(0,.80),(.17,.51),(.10,-.48),(.40,-.92),(0,-.73),(-.40,-.92),(-.10,-.48)]],[tuple(range(8))],g,api['TRIM'],False)
    # Hang beyond the guardrail, leaving the door/platform walking strip clear.
    for part in api['OBJECTS'][start:]:
        part.location.y-=1.52
        part['banner_assembly']=True
    for x in [14.3,17.7]:
        beam('Banner wall arm',(x,-.10,7.90),(x,-2.38,7.90),.065,g,api['WOOD'],False)
    for part in api['OBJECTS'][start:]:part.parent=root


def build_main_doors(api):
    """Door leaves have hinge roots; default open for gameplay, closed for exterior views."""
    import bpy
    from mathutils import Vector
    g='43_Entrance_Doors';parts=[]
    for side,x in [('left',14.42),('right',17.58)]:
        sign=1 if side=='left' else -1
        root=bpy.data.objects.new('Main door hinge '+side,None)
        api['SC'].collection.objects.link(root)
        api['register'](root,root.name,g,None,False)
        root['door_hinge']=[x,.25,0];root['door_pose']='open_90';root['closed_angle']=0
        start=len(api['OBJECTS']);center=x+sign*.785
        api['box']('Main door leaf '+side,center,.25,1.65,1.57,.12,3.28,g,api['WOOD'])
        for offset in [.10,1.47]:api['box']('Main door edge stile',x+sign*offset,.17,1.65,.10,.07,3.18,g,api['FURN'])
        for z in [.13,1.65,3.17]:api['box']('Main door horizontal rail',center,.16,z,1.50,.08,.10,g,api['FURN'])
        for j in range(4):
            z=.35+j*.72
            api['beam']('Main door diagonal board',(x+sign*.20,.17,z),(x+sign*1.36,.17,z+.48),.045,g,api['TRIM'],False)
        for z in [.60,2.65]:
            api['box']('Main door hinge strap',x+sign*.31,.10,z,.52,.045,.10,g,api['DARK'],collision=False)
        api['beam']('Main door handle',(x+sign*1.35,.04,1.30),(x+sign*1.35,.04,1.78),.045,g,api['DARK'],False)
        for o in api['OBJECTS'][start:]:
            # Rebase mesh and object transforms to the hinge; preserve beam rotations.
            o.parent=root;o.location-=Vector((x,.25,0))
            parts.append(o)
        root.location=(x,.25,0);root.rotation_euler.z=sign*math.pi/2
    return parts
