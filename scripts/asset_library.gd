# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetLibrary
extends RefCounted

const PALETTE: Array[Color] = [Color("e84148"),Color("ff8a30"),Color("ffd83d"),Color("48cc70"),Color("42d7df"),Color("527fff"),Color("ae6aeb"),Color("ff72bf")]
const COLOR_NAMES := ["Red","Orange","Yellow","Green","Cyan","Blue","Purple","Pink"]
const COLOR_IDS := ["red","orange","yellow","green","cyan","blue","purple","pink"]
const FILES := {"tv":"monitor_library","bow":"bow_frame","cartridge":"cartridge_shell"}
const MASSES := {"table":10.0,"console":1.5,"tv":3.0,"headset":0.5,"cartridge":0.15,
	"chair":6.0,"sofa":30.0,"shelf":16.0,"coffee_table":6.0,"side_table":4.0,
	"lamp":3.0,"plant":4.0,"rug":0.3,"sword":1.0,"bow":0.6,"arrow":0.025,
	"archery_target":10.0,"quiver":0.5,"storage_chest":11.0,"paintball_gun":0.75,"balloon_inflator":0.75}
const DEFAULTS := [
	["table",Vector3(0,.372,-.85)], ["console",Vector3(0,.786,-.85)],
	["tv",Vector3(0,1.0,-1.06)], ["headset",Vector3(.1,1.2,-.85)],
	["chair",Vector3(-1.9,.42,.3)], ["sofa",Vector3(1.85,.41,1.45)],
	["side_table",Vector3(2.4,.27,.6)],["shelf",Vector3(-2.4,.7,-1.4)],
	["lamp",Vector3(2.2,.775,-.3)],["plant",Vector3(2.2,.425,-2.2)],
	["coffee_table",Vector3(-1.5,.2,1.55)],["rug",Vector3(0,.006,-.85)],
	["sword",Vector3(-2.35,.48,2.25)],["bow",Vector3(-1.8,.68,2.35)]]
const OPTIONAL := ["archery_target","quiver","storage_chest","arrow","paintball_gun","balloon_inflator"]

static func path_for(id: String) -> String:
	return "res://assets/furniture/"+str(FILES.get(id,id))+".glb"

static func handheld(id: String) -> bool:
	return id in ["sword","bow","arrow","cartridge","headset","quiver","paintball_gun","balloon_inflator"]

static func grip_points(id: String) -> Array:
	var p := Vector3.ZERO
	var q := Quaternion.IDENTITY
	match id:
		"sword": p.y=-.325
		"bow": p.x=-.089225;q=Quaternion(Vector3.UP,PI/2)
		"arrow": p.z=-.26
		"headset": p.y=.012
		"quiver": p=Vector3(.07,.19,0)
		"paintball_gun","balloon_inflator": p=Vector3(0,-.065,-.07);q=Quaternion(Vector3.UP,PI)
	return [{"name":"Main grip","hand":"both","p":[p.x,p.y,p.z],"q":[q.x,q.y,q.z,q.w],"scale":[1,1,1]}]

static func bounds(root: Node3D) -> AABB:
	var result: Array = []
	accumulate_bounds(root,Transform3D.IDENTITY,result)
	return result[0] if not result.is_empty() else AABB(Vector3(-.1,-.1,-.1),Vector3(.2,.2,.2))

static func accumulate_bounds(node: Node, parent: Transform3D, result: Array) -> void:
	var current := parent
	if node is Node3D: current=parent*node.transform
	if node is MeshInstance3D and node.mesh:
		var box: AABB = current*node.get_aabb()
		if result.is_empty(): result.append(box)
		else: result[0]=result[0].merge(box)
	for child in node.get_children(): accumulate_bounds(child,current,result)

static func load_model(path: String) -> Node3D:
	if path.begins_with("res://"):
		var packed = load(path)
		return packed.instantiate() if packed is PackedScene else null
	var doc := GLTFDocument.new();var state := GLTFState.new()
	if doc.append_from_file(path,state)!=OK: return null
	return doc.generate_scene(state)

static func box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new();var shape := BoxMesh.new();shape.size=size;mesh.mesh=shape
	var material := StandardMaterial3D.new();material.albedo_color=color;material.roughness=.8
	mesh.material_override=material
	return mesh
