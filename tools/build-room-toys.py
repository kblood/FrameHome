# SPDX-License-Identifier: GPL-3.0-or-later
"""Original mobile VR props. Run with Blender --background --factory-startup --python.

Editable scenes, independent glTF exports, audits and contact sheet: build/room-toys.
Runtime GLBs: assets/furniture (tools), assets/toys (colored cosmetic effects).
"""
from pathlib import Path
import bpy, bmesh, math, json, zipfile, hashlib
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/room-toys'
ASSETS=ROOT/'assets'
OUT.mkdir(parents=True,exist_ok=True)
(ASSETS/'toys').mkdir(parents=True,exist_ok=True)
COLORS={'red':(.82,.045,.065),'orange':(1,.25,.025),'yellow':(1,.72,.045),
        'green':(.065,.64,.16),'cyan':(.04,.68,.74),'blue':(.065,.20,.95),
        'purple':(.45,.12,.80),'pink':(1,.17,.52)}

def clear(name):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for col in list(bpy.data.collections):
        if col.users==0 or col.name.startswith('COL_'): bpy.data.collections.remove(col)
    col=bpy.data.collections.new('COL_'+name);bpy.context.scene.collection.children.link(col)
    bpy.context.view_layer.active_layer_collection=bpy.context.view_layer.layer_collection.children[col.name]

def material(name,color,rough=.4,metal=0):
    m=bpy.data.materials.new('MAT_'+name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    return m

metal=material('BrushedAluminum',(.32,.35,.38),.29,.8)
rubber=material('GripRubber',(.022,.028,.034),.82)
paint=material('BlueEnamel',(.025,.16,.31),.33,.25)
ivory=material('WarmPolymer',(.72,.67,.55),.47)

def finish(o,name,mat):
    o.name='SM_'+name;o.data.materials.append(mat);return o

def box(name,p,size,mat,bevel=.006):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=finish(bpy.context.object,name,mat);o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('MachinedEdges','BEVEL');mod.width=bevel;mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def rod(name,a,b,r,mat,n=16):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=finish(bpy.context.object,name,mat);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    return o

def sphere(name,p,size,mat,segments=20,rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=p)
    o=finish(bpy.context.object,name,mat);o.scale=size
    for face in o.data.polygons:face.use_smooth=True
    return o

def handle():
    # -Y forward converts to glTF +Z. Controller anchor is (0,-.065,-.07) in glTF.
    box('ErgonomicGrip',(0,.07,-.065),(.062,.077,.15),rubber,.013)
    box('GripHeel',(0,.07,-.146),(.075,.085,.028),metal,.009)
    # Open trigger guard; its center remains empty.
    rod('TriggerGuardFront',(0,-.024,.006),(0,-.024,-.074),.009,metal)
    rod('TriggerGuardLower',(0,-.024,-.074),(0,.06,-.09),.009,metal)
    rod('Trigger',(0,.015,.004),(0,-.002,-.038),.006,rubber,12)
    for z in [-.105,-.075,-.045]:
        box('GripRib',(0,.110,z),(.052,.006,.010),rubber,.002)

def marker():
    handle()
    box('Receiver',(0,.022,.023),(.088,.175,.068),paint,.012)
    rod('Barrel',(0,-.065,.035),(0,-.205,.035),.018,metal,24)
    rod('MuzzleCollar',(0,-.183,.035),(0,-.210,.035),.023,paint,24)
    # Dark inset at the bore makes its direction unambiguous.
    rod('Bore',(0,-.2102,.035),(0,-.2105,.035),.012,rubber,20)
    rod('FeedNeck',(0,.010,.045),(0,.010,.095),.023,metal)
    sphere('PaintHopper',(0,.006,.112),(.069,.073,.047),paint)
    box('HopperLid',(0,.022,.153),(.07,.07,.01),rubber,.004)
    sphere('AirReservoir',(0,.145,-.013),(.04,.058,.042),metal)
    box('ColorDisplayBezel',(0,.110,.110),(.043,.046,.014),rubber,.004)

def inflator():
    handle()
    box('PumpBody',(0,.028,.035),(.125,.17,.135),ivory,.020)
    sphere('PressureTank',(0,.121,.035),(.059,.084,.079),paint)
    rod('NozzleBase',(0,-.052,.055),(0,-.130,.055),.032,metal,24)
    rod('Nozzle',(0,-.125,.055),(0,-.210,.055),.018,paint,24)
    rod('NozzleLip',(0,-.196,.055),(0,-.210,.055),.023,ivory,24)
    rod('AirOutlet',(0,-.2102,.055),(0,-.2105,.055),.010,rubber)
    box('ColorDisplayBezel',(0,.110,.110),(.043,.046,.014),rubber,.004)
    for x in [-.03,0,.03]:box('Vent',(x,-.012,.104),(.014,.05,.003),rubber,.001)

def balloon(mat):
    sphere('LatexBalloon',(0,0,0),(.14,.14,.168),mat,24,12)
    bpy.ops.mesh.primitive_cone_add(vertices=10,radius1=.018,radius2=.006,depth=.02,location=(0,0,-.177))
    finish(bpy.context.object,'BalloonKnot',mat)
    rod('BalloonTail',(0,0,-.187),(.018,0,-.29),.0015,mat,8)

def splat(mat):
    # Flat closed mesh, front -Y Blender / +Z glTF. Runtime scale sets its radius.
    n=32;verts=[]
    for y in [0,-.0005]:
        for i in range(n):
            a=i*math.tau/n;r=.65+.22*math.sin(a*5+.3)+.09*math.cos(a*9)
            verts.append((r*math.cos(a),y,r*math.sin(a)))
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new('PaintSplash');mesh.from_pydata(verts,[],faces)
    o=bpy.data.objects.new('SM_PaintSplash',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mat)

def audit():
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    # Merge by material to minimize actual draw calls. Preserve authored surface normals.
    groups=[[o for o in objects if len(o.data.materials)==1 and o.data.materials[0]==m]
            for m in sorted({m for o in objects for m in o.data.materials},key=lambda m:m.name)]
    for group in groups:
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:o.select_set(True)
        bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join()
    triangles=0;topology=[];points=[]
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        bm=bmesh.new();bm.from_mesh(o.data)
        # Check topological edges without welding overlapping independent component shells.
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        invalid=sum(not e.is_manifold for e in bm.edges)
        assert invalid==0,(o.name,invalid)
        bm.to_mesh(o.data);bm.free()
        triangles+=sum(len(p.vertices)-2 for p in o.data.polygons)
        points.extend([o.matrix_world@v.co for v in o.data.vertices])
        topology.append(dict(name=o.name,nonmanifold_edges=invalid))
    assert all(math.isfinite(c) for p in points for c in p)
    return triangles,topology,[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]

reports=[]
def export(name,generator,directory='toys',budget=3000,preview=False):
    clear(name);generator()
    tris,topology,bounds=audit();assert tris<=budget,(name,tris,budget)
    folder=OUT/name;folder.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(folder/(name+'.blend')))
    glb=ASSETS/directory/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True)
    bpy.ops.export_scene.gltf(filepath=str(folder/(name+'.gltf')),export_format='GLTF_SEPARATE',use_selection=True)
    reports.append(dict(id=name,triangles=tris,budget=budget,bounds_blender=bounds,topology=topology,
        materials=len([o for o in bpy.context.scene.objects if o.type=='MESH']),bytes=glb.stat().st_size,
        sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),source=str(glb.relative_to(ROOT))))
    if directory=='furniture':
        # Explicit alternate LOD for imports, not an unsupported automatic glTF LOD extension.
        for o in list(bpy.context.scene.objects):
            if o.type=='MESH':
                bpy.context.view_layer.objects.active=o
                mod=o.modifiers.new('LOD1','DECIMATE');mod.ratio=.5;bpy.ops.object.modifier_apply(modifier=mod.name)
        lod_tris,lod_topology,_=audit()
        reports[-1]['lod1_triangles']=lod_tris;reports[-1]['lod1_topology']=lod_topology
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.export_scene.gltf(filepath=str(folder/(name+'_lod1.glb')),export_format='GLB',use_selection=True)
    # Independent GLB import catches missing dependencies and establishes actual runtime axes.
    clear(name);bpy.ops.import_scene.gltf(filepath=str(glb))
    roundtrip=sum(len(p.vertices)-2 for o in bpy.context.scene.objects if o.type=='MESH' for p in o.data.polygons)
    assert tris==roundtrip,(name,tris,roundtrip)
    reports[-1]['roundtrip_triangles']=roundtrip
    if preview:render(folder/'preview.png',bounds)

def render(path,bounds):
    center=Vector([(bounds[0][i]+bounds[1][i])/2 for i in range(3)])
    radius=max(bounds[1][i]-bounds[0][i] for i in range(3))
    bpy.ops.object.camera_add(location=center+Vector((2,-3,1.3))*radius)
    cam=bpy.context.object;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=radius*1.4;bpy.context.scene.camera=cam
    for offset,energy in [((1,-2,3),400),((-2,-1,1),170),((0,3,2),250)]:
        bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*radius)
        light=bpy.context.object;light.data.energy=energy*radius**2;light.data.size=2*radius
        light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.world.color=(.12,.12,.12)
    scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
    scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)

export('paintball_gun',marker,'furniture',preview=True)
export('balloon_inflator',inflator,'furniture',preview=True)
for name,color in COLORS.items():
    m=material('Latex_'+name,color,.28)
    export('balloon_'+name,lambda m=m:balloon(m),budget=650,preview=name=='red')
    export('paintball_'+name,lambda m=m:sphere('Paintball',(0,0,0),(.009,.009,.009),m,12,6),budget=150)
    export('splat_'+name,lambda m=m:splat(m),budget=130,preview=name=='blue')
(OUT/'manifest.json').write_text(json.dumps(dict(units='meters',gltf_forward='+Z',gltf_up='+Y',assets=reports),indent=2))
(OUT/'README.txt').write_text('QuestHome original room toys; GPL-3.0-or-later.\n'
    'Tools: GLB in furniture/. Cosmetic colored meshes: toys/. Editable Blender and independent glTF in each named folder.\n'
    'Metres, +Y up, +Z forward. Tools centered; grip anchor (0,-.065,-.07), grip quaternion wxyz=(0,0,1,0).\n'
    'GLB imports provide geometry and generic grips. Built-in tool IDs add gameplay; importing a GLB alone does not add scripts.\n'
    'The LOD1 exports are optional alternate files, not automatically switched at runtime.\n')
with zipfile.ZipFile(ROOT/'build/QuestHome-room-toys.zip','w',zipfile.ZIP_DEFLATED) as z:
    for record in reports:
        name=record['id'];folder=OUT/name
        for f in folder.iterdir():
            if f.suffix in ['.gltf','.bin','.png','.glb','.blend']:z.write(f,f.relative_to(OUT))
        f=ROOT/record['source'];z.write(f,f.relative_to(ASSETS))
    for file in [OUT/'manifest.json',OUT/'README.txt',ROOT/'LICENSE']:z.write(file,file.name)
print('QUEST_HOME_ROOM_TOYS_COMPLETE',len(reports))
