# SPDX-License-Identifier: GPL-3.0-or-later
"""Run in Blender --background --factory-startup --python tools/build-model-library.py.

Original props, an unstrung runtime bow, independent glTF exports and round-trip audits.
Original input GLBs are preserved; runtime variants are rebuilt reproducibly.
Generated previews and .blend sources live under build/.
"""
from pathlib import Path
import bpy, bmesh, json, math, hashlib, zipfile
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/furniture'
OUT = ROOT / 'build/model-library'
OUT.mkdir(parents=True, exist_ok=True)

def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def mat(name, color, rough=.55, metal=0):
    m = bpy.data.materials.new('MAT_' + name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    return m

def finish(obj, name, material):
    obj.name = 'SM_' + name
    obj.data.materials.append(material)
    return obj

def box(name, pos, size, material, bevel=.006):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = finish(bpy.context.object, name, material)
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        m = o.modifiers.new('Edge highlights', 'BEVEL'); m.width=bevel; m.segments=2
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o

def cylinder(name, pos, radius, depth, material, vertices=24, top=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if top is None else top, depth=depth, location=pos)
    return finish(bpy.context.object, name, material)

def rod(name, a, b, radius, material, vertices=12):
    a,b=Vector(a),Vector(b)
    o=cylinder(name,(a+b)/2,radius,(b-a).length,material,vertices)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return o

clear()
wood=mat('Walnut',(.22,.095,.033),.45)
grain=wood.node_tree.nodes.new('ShaderNodeTexImage')
grain.image=bpy.data.images.load(str(ROOT/'art/furniture/textures/oak_basecolor.png'))
wood.node_tree.links.new(grain.outputs['Color'],wood.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
leather=mat('Leather',(.065,.027,.016),.7)
steel=mat('Steel',(.34,.37,.40),.3,.85)
brass=mat('Brass',(.36,.24,.07),.36,.75)
cream=mat('Canvas',(.77,.71,.55),.9)
red=mat('TargetRed',(.56,.035,.025),.75)
blue=mat('TargetBlue',(.025,.13,.26),.8)
black=mat('TargetBlack',(.016,.02,.026),.85)
gold=mat('TargetGold',(.9,.55,.05),.8)
feather=mat('Feathers',(.72,.24,.085),.8)

def arrow():
    # Blender -Y becomes glTF +Z. Origin is the nock; arrow points +Z at runtime.
    rod('ArrowShaft',(0,0,0),(0,-.66,0),.004,wood)
    tip=cylinder('ArrowHead',(0,-.69,0),.012,.06,steel,8,0)
    tip.rotation_euler.x=math.pi/2
    rod('Nock',(0,.004,0),(0,-.025,0),.006,cream,10)
    for i in range(3):
        a=i*math.tau/3
        verts=[(0,-.035,0),(math.cos(a)*.022,-.065,math.sin(a)*.022),
               (math.cos(a)*.022,-.14,math.sin(a)*.022),(0,-.16,0)]
        mesh=bpy.data.meshes.new('Fletching'); mesh.from_pydata(verts,[],[(0,1,2,3)])
        o=bpy.data.objects.new('SM_Fletching',mesh); bpy.context.collection.objects.link(o)
        o.data.materials.append(feather)
        bpy.context.view_layer.objects.active=o
        mod=o.modifiers.new('Feather thickness','SOLIDIFY');mod.thickness=.001
        bpy.ops.object.modifier_apply(modifier=mod.name)

def target():
    for sign in [-1,1]:
        rod('StandLeg',(sign*.32,.18,.035),(sign*.21,0,1.32),.028,wood)
    rod('RearLeg',(0,-.32,.03),(0,0,1.22),.028,wood)
    rod('StandBrace',(-.3,.14,.32),(.3,.14,.32),.017,wood)
    # Front +Y in Blender is -Z in glTF: towards the room.
    for idx,(r,m) in enumerate([(.39,cream),(.312,black),(.234,blue),(.156,red),(.078,gold)]):
        o=cylinder('TargetRing',(0,.07 if idx==0 else .11+idx*.004,1.10),r,.075 if idx==0 else .004,m,48)
        o.rotation_euler.x=math.pi/2

def quiver():
    # Hollow leather tube with a closed base and brass bands.
    n=32; verts=[]
    for z,r in [(0,.075),(.5,.085),(0.025,.066),(.5,.076)]:
        verts += [(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),z) for i in range(n)]
    faces=[]
    for start,end in [(0,n),(2*n,3*n),(n,3*n),(0,2*n)]:
        faces += [(start+i,start+(i+1)%n,end+(i+1)%n,end+i) for i in range(n)]
    mesh=bpy.data.meshes.new('Quiver');mesh.from_pydata(verts,[],faces)
    o=bpy.data.objects.new('SM_QuiverLeather',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(leather)
    cylinder('Base',(0,0,.012),.067,.018,wood,32)
    for z in [.04,.465]:
        bpy.ops.mesh.primitive_torus_add(major_segments=32,minor_segments=6,
            location=(0,0,z),major_radius=.076+z*.02,minor_radius=.004)
        finish(bpy.context.object,'QuiverBand',brass)
    for sign in [-1,1]:
        box('BeltLoop',(sign*.05,-.075,.28),(.02,.018,.13),leather,.004)

def chest():
    box('ChestBody',(0,0,.205),(.68,.4,.36),wood,.012)
    box('ChestLid',(0,0,.41),(.71,.43,.065),wood,.013)
    for x in [-.25,.25]:
        box('LidStrap',(x,0,.446),(.035,.40,.006),steel,.002)
        box('FrontStrap',(x,.204,.22),(.035,.009,.34),steel,.002)
    box('Latch',(0,.221,.352),(.052,.014,.078),brass,.004)
    for x in [-.26,.26]:
        for y in [-.13,.13]: box('Foot',(x,y,.026),(.075,.075,.052),wood,.008)

def export(name, generator):
    clear()
    generator()
    collection=bpy.data.collections.new('COL_'+name)
    bpy.context.scene.collection.children.link(collection)
    for obj in list(bpy.context.scene.objects):
        for owner in list(obj.users_collection): owner.objects.unlink(obj)
        collection.objects.link(obj)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    tris=sum(len(p.vertices)-2 for o in objs for p in o.data.polygons)
    assert tris < 3000, (name,tris)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/(name+'.glb')),export_format='GLB',use_selection=True)

for name,generator in [('arrow',arrow),('archery_target',target),('quiver',quiver),('storage_chest',chest)]:
    export(name,generator)

# The previous glass and bottom bezel obscured the foot. Raise the housing, extend its
# rear neck and broaden the base; retain the exact 0.64 x 0.36 m live-screen aperture.
clear();bpy.ops.import_scene.gltf(filepath=str(ASSETS/'monitor_with_stand.glb'))
for obj in bpy.context.scene.objects:
    if obj.type!='MESH': continue
    if any(part in obj.name for part in ['BackShell','ScreenGlass','Bezel','StatusIndicator','Vent','StandSocket']):
        obj.location.z+=.10
    elif 'StandNeck' in obj.name:
        obj.location.z=.105;obj.scale.z*=.165/.086
    elif 'BaseFoot' in obj.name or 'BasePad' in obj.name:
        obj.scale.y*=.18/.074
    elif 'StandCollar' in obj.name:
        obj.scale.y*=.12/.076
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'monitor_library.blend'))
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'monitor_library.glb'),export_format='GLB',use_selection=True)

# Keep the existing authored wooden bow. Runtime owns the two moving string segments.
clear(); bpy.ops.import_scene.gltf(filepath=str(ASSETS/'bow.glb'))
for o in list(bpy.context.scene.objects):
    if o.type!='MESH': continue
    bm=bmesh.new();bm.from_mesh(o.data)
    remove=[]
    for f in bm.faces:
        coords=[o.matrix_world@v.co for v in f.verts]
        material=o.data.materials[f.material_index].name
        if ('LinenBowstring' in material and all(abs(v.z)<.58 for v in coords)) or all(v.x>.19 and abs(v.z)<.06 for v in coords) or all(abs(v.z)<.000001 for v in coords):
            remove.append(f)
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    # Close the trimmed string ends; join the two touching limb shells at the riser.
    bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=16)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(o.data);bm.free()
bpy.ops.object.select_all(action='SELECT')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bow_frame.blend'))
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'bow_frame.glb'),export_format='GLB',use_selection=True)

report=[]
for file in sorted(ASSETS.glob('*.glb')):
    clear(); bpy.ops.import_scene.gltf(filepath=str(file))
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    points=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
    lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
    tris=sum(len(p.vertices)-2 for o in objs for p in o.data.polygons)
    invalid=sum(not math.isfinite(c) for p in points for c in p)
    assert not invalid
    folder=OUT/file.stem;folder.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(folder/(file.stem+'.gltf')),export_format='GLTF_SEPARATE',use_selection=True)
    topology=[]
    for obj in objs:
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
        topology.append(dict(mesh=obj.name,boundary_edges=sum(e.is_boundary for e in bm.edges),
            nonmanifold_edges=sum(not e.is_manifold for e in bm.edges)))
        bm.free()
    report.append(dict(id=file.stem,triangles=tris,materials=len({m.name for o in objs for m in o.data.materials}),
        bounds_blender=[lo,hi],bytes=file.stat().st_size,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),
        finite=True,topology=topology,source=str(file.relative_to(ROOT))))
    # Reimport the exported .gltf independently, then render a normalized preview.
    clear();bpy.ops.import_scene.gltf(filepath=str(folder/(file.stem+'.gltf')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    roundtrip=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    assert roundtrip==tris,(file,roundtrip,tris)
    center=Vector([(lo[i]+hi[i])/2 for i in range(3)])
    radius=max(hi[i]-lo[i] for i in range(3))
    bpy.ops.object.camera_add(location=center+Vector((1.9,2.5,1.5))*radius)
    camera=bpy.context.object;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=radius*1.5;bpy.context.scene.camera=camera
    for offset,energy,size in [((2,3,4),500,3),((-2,1,2),250,2)]:
        bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*max(radius,.5))
        light=bpy.context.object;light.data.energy=energy*max(radius,.5)**2;light.data.shape='DISK';light.data.size=size*max(radius,.5)
        light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16
    scene.world.color=(.13,.13,.13)
    scene.render.resolution_x=400;scene.render.resolution_y=400;scene.render.resolution_percentage=100
    scene.render.filepath=str(folder/'preview.png');bpy.ops.render.render(write_still=True)
    report[-1]['roundtrip_triangles']=roundtrip
(OUT/'manifest.json').write_text(json.dumps({'units':'meters','gltf_up':'+Y','new_asset_budget':3000,'assets':report},indent=2))

# Review the actual rest/nock geometry with a drawn arrow, independently of the Android UI.
clear();bpy.ops.import_scene.gltf(filepath=str(ASSETS/'bow_frame.glb'))
before=set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=str(ASSETS/'arrow.glb'))
arrow_objects=set(bpy.context.scene.objects)-before
root=bpy.data.objects.new('GRIP_DrawnArrow',None);bpy.context.collection.objects.link(root)
for obj in arrow_objects:
    if obj.parent is None: obj.parent=root
root.location=(.59555,0,.049);root.rotation_euler.z=-math.pi/2
string_mat=mat('PreviewString',(.72,.65,.48),.8)
rod('UpperString',(.19555,0,.573),root.location,.0015,string_mat)
rod('LowerString',(.19555,0,-.573),root.location,.0015,string_mat)
center=Vector((.20,0,0))
bpy.ops.object.camera_add(location=(2.4,4.2,1.8))
camera=bpy.context.object;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=1.6
scene=bpy.context.scene;scene.camera=camera
for pos,energy in [((2,3,4),700),((-2,1,1),300)]:
    bpy.ops.object.light_add(type='AREA',location=pos)
    light=bpy.context.object;light.data.energy=energy;light.data.size=3
    light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=700;scene.render.resolution_y=700
scene.render.filepath=str(OUT/'archery-draw-preview.png');bpy.ops.render.render(write_still=True)

(OUT/'README.txt').write_text('QuestHome model library\n'
    'GLB files in glb/ import directly into QuestHome. Each glTF folder is independent; keep its .bin and textures together.\n'
    'Units: metres. glTF +Y up. Original models retained; bow_frame and monitor_library are corrected runtime variants.\n'
    'New objects: arrow, quiver, archery_target, storage_chest. Use Object library > Add inside QuestHome.\n'
    'Bow: hold grip, trigger near the string with the other hand, draw back, release trigger to shoot.\n'
    'Blender sources for the new variants are packed and included. GPL-3.0-or-later; see repository LICENSE.\n')
with zipfile.ZipFile(ROOT/'build/QuestHome-model-library.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for record in report:
        name=record['id'];folder=OUT/name;gltf=folder/(name+'.gltf')
        document=json.loads(gltf.read_text())
        dependencies={r['uri'] for group in ('buffers','images') for r in document.get(group,[]) if 'uri' in r and not r['uri'].startswith('data:')}
        for path in [gltf,folder/'preview.png']+[folder/ref for ref in sorted(dependencies)]:
            archive.write(path,path.relative_to(OUT))
        archive.write(ASSETS/(name+'.glb'),'glb/'+name+'.glb')
    for path in list(OUT.glob('*.blend'))+[OUT/'manifest.json',OUT/'README.txt',OUT/'archery-draw-preview.png']:
        archive.write(path,path.name)
    archive.write(ROOT/'LICENSE','LICENSE')
print('QUEST_HOME_MODEL_LIBRARY_COMPLETE',len(report))
