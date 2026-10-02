# SPDX-License-Identifier: GPL-3.0-or-later
class_name HomeHand
extends XRController3D

var home: Node
var side := "left"
var aim: XRController3D
var held: Node3D
var attached := false
var held_local := Transform3D.IDENTITY
var last_grip := false
var last_trigger := false
var last_color := false
var armed := false
var ray: MeshInstance3D
var previous_position := Vector3.ZERO
var velocity := Vector3.ZERO
var resize_start := 1.0
var resizing := false
var resize_origin := Vector3.ZERO
var pointed_panel: HomePanel
var scroll_timer := 0.0
var cooldown := 0.0
var authored_grip := Transform3D.IDENTITY

func _ready() -> void:
	tracker="left_hand" if side=="left" else "right_hand"
	pose="grip"
	var body := AssetLibrary.box_mesh(Vector3(.035,.04,.08),Color("9bb8c9"));add_child(body)
	ray=AssetLibrary.box_mesh(Vector3(.0015,.0015,1),Color("72caeb"));home.add_child(ray)

func reset_input() -> void:
	if held: release()
	armed=false;last_grip=false;last_trigger=false;last_color=false
	if pointed_panel: pointed_panel.release_pointer();pointed_panel=null

func _physics_process(dt: float) -> void:
	if not home.xr_active: ray.visible=false;return
	if not get_is_active() or not home.input_focused:
		reset_input();ray.visible=false;return
	velocity=(global_position-previous_position)/maxf(dt,.001);previous_position=global_position
	var grip_down := get_float("grip")>.65
	var trigger_down := get_float("trigger")>.65
	var color_down := is_button_pressed("ax_button")
	if not grip_down and not trigger_down: armed=true
	var start := aim.global_position
	var direction := -aim.global_basis.z
	var end := start+direction*8
	var query := PhysicsRayQueryParameters3D.create(start,end,7)
	if held is CollisionObject3D: query.exclude=[held.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): end=hit.position
	ray.visible=held==null
	ray.global_position=(start+end)/2;ray.look_at(end,Vector3.UP)
	ray.scale=Vector3(1,1,start.distance_to(end))
	if armed and grip_down and not last_grip and held==null:
		# Prefer nearby handholds; otherwise use the aim ray for distance grabs.
		var nearest: HomeProp
		var distance := .13
		for prop in home.props:
			if not is_instance_valid(prop) or prop.held_by: continue
			if not prop.visible: continue
			var d: float = (prop.global_transform*prop.nearest_grip(side,global_position)).origin.distance_to(global_position)
			if d<distance: distance=d;nearest=prop
		if nearest: grab(nearest,global_position)
		elif not hit.is_empty() and (hit.collider is HomeProp or hit.collider is HomePanel): grab(hit.collider,hit.position)
	if not grip_down and last_grip and held: release()
	if held:
		if resizing and held is HomePanel:
			var motion := held.global_basis.inverse()*(global_position-resize_origin)
			held.apply_size(resize_start+(motion.x-motion.y)/maxf(held.base_dimensions.length(),.1))
		else:
			update_held(dt)
		cooldown=maxf(0,cooldown-dt)
		if held is HomeProp and attached and armed:
			if color_down and not last_color: home.toys.cycle_color(held.model_id)
			if held.model_id=="paintball_gun" and trigger_down and cooldown<=0:
				home.toys.fire_paint(held);cooldown=1.0/6.0
			elif held.model_id=="balloon_inflator": home.toys.inflate(held,trigger_down,dt)
	var panel: HomePanel = hit.collider if not hit.is_empty() and hit.collider is HomePanel and held==null else null
	if pointed_panel!=panel:
		if pointed_panel: pointed_panel.release_pointer()
		pointed_panel=panel
	if panel:
		scroll_timer-=dt
		# Scrolling is explicit: hold the stick click, preserving ordinary locomotion.
		var scroll := get_vector2("primary").y if is_button_pressed("primary_click") and scroll_timer<=0 else 0.0
		panel.pointer(hit.position,trigger_down and armed,scroll)
		if absf(scroll)>.5: scroll_timer=.15
	last_grip=grip_down;last_trigger=trigger_down;last_color=color_down

func grab(item: Node3D, point: Vector3) -> void:
	if item.held_by or item.has_meta("fixture"): return
	home.checkpoint();held=item;held_local=global_transform.affine_inverse()*item.global_transform
	attached=false;resizing=false
	if item is HomeProp:
		authored_grip=item.nearest_grip(side,global_position)
		item.begin_hold(self)
		attached=item.handheld() and (item.global_transform*authored_grip).origin.distance_to(global_position)<.13
	elif item is HomePanel:
		item.held_by=self;resizing=item.is_resize_point(point)
		resize_start=item.panel_scale;resize_origin=global_position
	home.selected=item;home.ui.refresh_selection()

func update_held(dt: float) -> void:
	var right: HomeHand = home.right_hand
	var owns_stick := side=="right" or right.held==null
	var stick := right.get_vector2("primary") if owns_stick else Vector2.ZERO
	manipulate_held(dt,stick)

func manipulate_held(dt: float, stick: Vector2) -> void:
	var depth := stick.y if absf(stick.y)>.2 else 0.0
	var grip_transform: Transform3D = authored_grip if held is HomeProp and held.handheld() else Transform3D.IDENTITY
	if attached and depth>.2:
		attached=false;held_local=grip_transform.affine_inverse()
	if not attached:
		var grip_position: Vector3 = (held_local*grip_transform).origin
		var distance := grip_position.length()
		var direction := grip_position.normalized() if distance>.001 else Vector3.FORWARD
		var next_distance := clampf(distance+depth*.9*dt,.02,8)
		held_local.origin+=direction*(next_distance-distance)
		if held is HomeProp and held.handheld() and next_distance<.12 and depth<-.2: attached=true
	if attached: held_local=grip_transform.affine_inverse()
	if held is HomePanel and absf(stick.x)>.2:
		held_local.basis=Basis(Vector3.UP,-stick.x*dt*1.5)*held_local.basis
	held.global_transform=global_transform*held_local
	if held is HomeProp and held.clear_at(held.global_transform): held.last_clear_pose=held.global_transform
	if held is HomePanel:
		held.dock_to_wall()

func release() -> void:
	if not is_instance_valid(held): held=null;return
	if held is HomeProp:
		if held.model_id=="balloon_inflator": home.toys.release_balloon(held.global_basis.z)
		held.end_hold(velocity)
	else: held.held_by=null
	held=null;attached=false;resizing=false;home.save_room()
