# SPDX-License-Identifier: GPL-3.0-or-later
class_name HomePanel
extends StaticBody3D

var uid := "panel"
var viewport: SubViewport
var content: Control
var dimensions := Vector2(1.05,1.15)
var base_dimensions := Vector2(1.05,1.15)
var surface: MeshInstance3D
var panel_shape: CollisionShape3D
var bar: MeshInstance3D
var corner: MeshInstance3D
var held_by: Node3D
var wall_normal := Vector3.ZERO
var last_pixel := Vector2.ZERO
var pressed := false
var panel_scale := 1.0

func configure(id: String, size: Vector2, ui: Control) -> void:
	uid=id;dimensions=size;base_dimensions=size
	collision_layer=4;collision_mask=0
	viewport=SubViewport.new();viewport.size=Vector2i(900,1000)
	viewport.transparent_bg=false;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input=false;viewport.gui_embed_subwindows=true;add_child(viewport)
	content=ui;content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);viewport.add_child(content)
	surface=MeshInstance3D.new();var quad := QuadMesh.new();quad.size=dimensions;surface.mesh=quad
	surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture=viewport.get_texture();material.cull_mode=BaseMaterial3D.CULL_DISABLED
	surface.material_override=material;add_child(surface)
	panel_shape=CollisionShape3D.new();panel_shape.shape=BoxShape3D.new();add_child(panel_shape)
	bar=AssetLibrary.box_mesh(Vector3(dimensions.x,.04,.025),Color("46a7cf"));add_child(bar)
	corner=AssetLibrary.box_mesh(Vector3(.07,.07,.025),Color("51cfa7"));add_child(corner)
	bar.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;corner.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	apply_size(1.0)
	add_to_group("panels")

func apply_size(value: float) -> void:
	panel_scale=clampf(value,.4,2.5);dimensions=base_dimensions*panel_scale
	(surface.mesh as QuadMesh).size=dimensions
	(panel_shape.shape as BoxShape3D).size=Vector3(dimensions.x+.10,dimensions.y+.14,.04)
	(bar.mesh as BoxMesh).size=Vector3(dimensions.x,.04,.025)
	bar.position=Vector3(0,dimensions.y/2+.035,0)
	corner.position=Vector3(dimensions.x/2+.025,-dimensions.y/2-.025,0)

func is_resize_point(world: Vector3) -> bool:
	return to_local(world).distance_to(corner.position)<.10

func pointer(world: Vector3, down: bool, wheel: float=0.0) -> void:
	var local := to_local(world)
	var pixel := Vector2((local.x/dimensions.x+.5)*viewport.size.x,(.5-local.y/dimensions.y)*viewport.size.y)
	var motion := InputEventMouseMotion.new();motion.position=pixel;motion.global_position=pixel
	motion.relative=pixel-last_pixel;motion.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	viewport.push_input(motion,true);last_pixel=pixel
	if down!=pressed:
		var click := InputEventMouseButton.new();click.position=pixel;click.global_position=pixel
		click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down
		viewport.push_input(click,true);pressed=down
	if absf(wheel)>.5:
		var scroll := InputEventMouseButton.new();scroll.position=pixel
		scroll.button_index=MOUSE_BUTTON_WHEEL_UP if wheel>0 else MOUSE_BUTTON_WHEEL_DOWN
		scroll.pressed=true;viewport.push_input(scroll,true)

func release_pointer() -> void:
	if not pressed: return
	var release := InputEventMouseButton.new();release.position=last_pixel
	release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	viewport.push_input(release,true);pressed=false

func dock_to_wall() -> void:
	var p := global_position
	var gap_x := 2.96-absf(p.x);var gap_z := 2.96-absf(p.z)
	if minf(gap_x,gap_z)>.13:
		wall_normal=Vector3.ZERO;return
	if gap_x<gap_z:
		wall_normal=Vector3(-signf(p.x),0,0);p.x=signf(p.x)*2.935
		p.z=clampf(p.z,-2.9+dimensions.x/2,2.9-dimensions.x/2)
	else:
		wall_normal=Vector3(0,0,-signf(p.z));p.z=signf(p.z)*2.935
		p.x=clampf(p.x,-2.9+dimensions.x/2,2.9-dimensions.x/2)
	p.y=clampf(p.y,dimensions.y/2+.04,maxf(dimensions.y/2+.04,2.7-dimensions.y/2))
	global_transform=Transform3D(Basis.looking_at(-wall_normal,Vector3.UP),p)

func snapshot() -> Dictionary:
	return {"uid":uid,"panel":true,"pose":HomeData.pose(global_transform),"panel_scale":panel_scale}
