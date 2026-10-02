# SPDX-License-Identifier: GPL-3.0-or-later
class_name HomeProp
extends RigidBody3D

var uid: String
var model_id: String
var app_id := ""
var model_path: String
var model_scale := 1.0
var pinned := false
var held_by: Node3D
var visual: Node3D
var size := Vector3.ONE
var default_grips: Array = []
var label_viewport: SubViewport
var custom_handheld := false
var home: Node
var last_clear_pose := Transform3D.IDENTITY

func configure(id: String, path: String, instance_id: String, initial_scale := 1.0) -> void:
	model_id=id;model_path=path;uid=instance_id;model_scale=initial_scale
	name=instance_id.validate_node_name()
	default_grips=AssetLibrary.grip_points(id)
	mass=AssetLibrary.MASSES.get(id,1.0)
	can_sleep=true;continuous_cd=true
	physics_material_override=PhysicsMaterial.new()
	physics_material_override.friction=.8;physics_material_override.bounce=0
	linear_damp=.15;angular_damp=.6
	collision_layer=2;collision_mask=3
	visual=AssetLibrary.load_model(path)
	if visual==null:
		visual=Node3D.new();visual.add_child(AssetLibrary.box_mesh(Vector3(.2,.2,.2),Color.MAGENTA))
	var box := AssetLibrary.bounds(visual)
	visual.position-=box.get_center()
	visual.scale*=initial_scale
	size=box.size*initial_scale
	add_child(visual)
	if id=="table":
		collider(Vector3(1.3,.04,.6),Vector3(0,.35,0))
		for x in [-.534,.534]:
			for z in [-.225,.225]: collider(Vector3(.052,.70,.052),Vector3(x,-.02,z))
	elif id=="shelf":
		for x in [-.484,.484]: collider(Vector3(.032,1.32,.28),Vector3(x,.04,0))
		for y in [.100,.402,.704,1.006,1.386]: collider(Vector3(.936,.028,.276),Vector3(0,y-.7,0))
		collider(Vector3(.936,1.265,.014),Vector3(0,.0525,.130))
	elif id in ["side_table","coffee_table"]:
		collider(Vector3(size.x,.035,size.z),Vector3(0,size.y/2-.0175,0))
		for x in [-1,1]:
			for z in [-1,1]: collider(Vector3(.045,size.y-.035,.045),Vector3(x*(size.x/2-.07),-.0175,z*(size.z/2-.07)))
	elif id=="archery_target":
		var disc := CollisionShape3D.new();var cylinder := CylinderShape3D.new()
		cylinder.radius=.39;cylinder.height=.09;disc.shape=cylinder
		disc.position=Vector3(0,1.10,-.07)-box.get_center();disc.rotation.x=PI/2;add_child(disc)
		for sign in [-1,1]:
			collider_rod(Vector3(sign*.32,.035,-.18)-box.get_center(),Vector3(sign*.21,1.32,0)-box.get_center(),.056)
		collider_rod(Vector3(0,.03,.32)-box.get_center(),Vector3(0,1.22,0)-box.get_center(),.056)
	else:
		collider(size)
	if id in ["rug","headset"]: set_pinned(true)
	add_to_group("props")
	Catalog.artwork_changed.connect(_artwork_changed)
	Catalog.catalog_changed.connect(func():
		if not app_id.is_empty(): set_app(app_id))

func collider_rod(a: Vector3, b: Vector3, thickness: float) -> void:
	var shape := BoxShape3D.new();shape.size=Vector3(thickness,thickness,a.distance_to(b))
	var col := CollisionShape3D.new();col.shape=shape;col.position=(a+b)/2
	col.basis=Basis.looking_at(b-a,Vector3.RIGHT);add_child(col)

func collider(dimensions: Vector3, offset := Vector3.ZERO) -> void:
	var col := CollisionShape3D.new();var shape := BoxShape3D.new()
	shape.size=dimensions.max(Vector3.ONE*.005);col.shape=shape;col.position=offset
	add_child(col)

func grip_key() -> String:
	return "import:"+model_id if model_path.begins_with("user://") else "builtin:"+model_id

func handheld() -> bool:
	return HomeData.grips.get(grip_key(),{}).get("handheld",AssetLibrary.handheld(model_id) or custom_handheld)

func grip(side: String) -> Transform3D:
	var value := HomeData.grip_for(grip_key(),side,default_grips)
	value.origin*=model_scale
	return value

func nearest_grip(side: String, hand_position: Vector3) -> Transform3D:
	var best := grip(side)
	var distance := INF
	for point in HomeData.profile_points(grip_key(),default_grips):
		if point.get("hand","both") not in ["both",side]: continue
		var candidate := HomeData.read_pose(point);candidate.origin*=model_scale
		var d := (global_transform*candidate).origin.distance_to(hand_position)
		if d<distance: best=candidate;distance=d
	return best

func clear_at(pose: Transform3D) -> bool:
	for child in get_children():
		if not child is CollisionShape3D or child.disabled: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=child.shape.duplicate()
		if query.shape is BoxShape3D: query.shape.size=(query.shape.size-Vector3.ONE*.004).max(Vector3.ONE*.002)
		query.transform=pose*child.transform;query.collision_mask=3;query.exclude=[get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func set_pinned(value: bool) -> void:
	pinned=value;freeze=value or held_by!=null
	freeze_mode=RigidBody3D.FREEZE_MODE_STATIC
	if not freeze: sleeping=false

func begin_hold(hand: Node3D) -> void:
	last_clear_pose=global_transform
	held_by=hand;freeze=true;collision_layer=0;collision_mask=0
	linear_velocity=Vector3.ZERO;angular_velocity=Vector3.ZERO

func end_hold(velocity: Vector3) -> void:
	# Never turn an overlapping held volume into a dynamic body inside the table.
	if not clear_at(global_transform):
		var candidate := global_transform
		var found := false
		for i in range(20):
			candidate.origin.y+=.05
			if clear_at(candidate): global_transform=candidate;found=true;break
		if not found: global_transform=last_clear_pose
	held_by=null;collision_layer=2;collision_mask=3;freeze=pinned
	if not pinned:
		linear_velocity=velocity.limit_length(3.0);angular_velocity=Vector3.ZERO;sleeping=false
	if home: home.prop_released(self)

func set_app(id: String) -> void:
	app_id=id
	if label_viewport:
		label_viewport.queue_free();label_viewport=null
	for child in get_children():
		if child.name=="Artwork": remove_child(child);child.queue_free()
	label_viewport=SubViewport.new();label_viewport.size=Vector2i(544,608)
	label_viewport.transparent_bg=false;label_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(label_viewport)
	var background := ColorRect.new();background.color=Color("111923");background.size=Vector2(544,608)
	label_viewport.add_child(background)
	var icon := TextureRect.new();icon.position=Vector2(12,12);icon.size=Vector2(520,444)
	icon.texture=Catalog.cover(id);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;label_viewport.add_child(icon)
	var title := Label.new();title.text=Catalog.find_app(id).name;title.position=Vector2(14,462);title.size=Vector2(516,138)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",27)
	label_viewport.add_child(title)
	var surface := MeshInstance3D.new();surface.name="Artwork"
	var quad := QuadMesh.new();quad.size=Vector2(.136,.152);surface.mesh=quad
	surface.position=Vector3(0,0,-.0127);surface.rotation.y=PI
	var mat := StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture=label_viewport.get_texture();surface.material_override=mat;add_child(surface)

func _artwork_changed(id: String) -> void:
	if id==app_id: set_app(id)

func snapshot() -> Dictionary:
	return {"uid":uid,"model":model_id,"path":model_path,"scale":model_scale,
		"pose":HomeData.pose(global_transform),"pinned":pinned,"app":app_id}
