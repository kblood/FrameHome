# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit opt-in integration checks on the running renderer/physics world.
# Synthetic interactions do not certify physical controller ergonomics.
extends Node

var home: Node
var report: Dictionary = {"checks":[],"samples":[],"scope":"Synthetic device integration; physical controls require manual validation"}
var output := "user://device-check"
var original: Dictionary
var completed := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output=arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func record(label: String, passed: bool, details = {}) -> void:
	report.checks.append({"name":label,"passed":passed,"details":details})
	print("DEVICE_CHECK ",label," ",passed," ",JSON.stringify(details))
	write_report()

func write_report() -> void:
	var file := FileAccess.open(output+"/report.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t"))

func _exit_tree() -> void:
	if not completed and not original.is_empty():
		HomeData.apply_document(original);HomeData.save()
		report["interrupted"]=true;write_report()

func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func stability(seconds: float) -> Dictionary:
	var initial: Dictionary = {};var worst := 0.0;var speed := 0.0
	for prop in home.props:
		if is_instance_valid(prop) and prop.visible: initial[prop.uid]=prop.global_position
	var until := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<until:
		await get_tree().physics_frame
		for prop in home.props:
			if not is_instance_valid(prop) or not initial.has(prop.uid): continue
			worst=maxf(worst,initial[prop.uid].distance_to(prop.global_position))
			speed=maxf(speed,prop.linear_velocity.length())
	return {"maximum_displacement_metres":worst,"maximum_speed_mps":speed}

func capture_scene(name: String, eye: Vector3, target: Vector3) -> void:
	# An explicit secondary camera on the real device, not the headset mirror.
	var view := SubViewport.new();view.size=Vector2i(1440,1000)
	view.world_3d=home.get_world_3d();view.msaa_3d=Viewport.MSAA_2X
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;home.add_child(view)
	var camera := Camera3D.new();view.add_child(camera);camera.fov=70
	camera.global_position=eye;camera.look_at(target);camera.current=true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	if image: image.save_png(output+"/"+name+".png")
	view.queue_free()

func run() -> void:
	original=HomeData.document().duplicate(true);home.restoring=true
	report["platform"]=OS.get_name();report["xr_active"]=home.xr_active
	report["tracked_hands"]=[home.left_hand.get_is_active(),home.right_hand.get_is_active()]
	report["started_utc"]=Time.get_datetime_string_from_system(true)
	report["device"]=RenderingServer.get_video_adapter_name()
	record("OpenXR initialized",home.xr_active)
	await settle(5)
	record("Installed Steam catalog",not Catalog.apps.is_empty(),{"count":Catalog.apps.size()})
	var baseline := await stability(2)
	record("Starting furniture settles",baseline.maximum_displacement_metres<.02 and baseline.maximum_speed_mps<.1,baseline)
	await capture_scene("room",Vector3(0,1.65,1.25),Vector3(0,1,-.9))
	var app_id: String=Catalog.apps[0].id if not Catalog.apps.is_empty() else "0"
	for app in Catalog.apps:
		if not app.system: app_id=app.id;break
	var table: HomeProp
	for prop in home.props:
		if prop.model_id=="table": table=prop;break
	if table:
		var top: float=table.to_global(Vector3(0,.37,0)).y
		var cart: HomeProp=home.spawn_prop("cartridge","probe_cart",AssetLibrary.path_for("cartridge"),Transform3D(Basis(Vector3.UP,PI),Vector3(.43,top+.125,-.74)))
		cart.set_app(app_id)
		await settle(3)
		var box: AABB=cart.global_transform*AABB(-cart.size/2,cart.size)
		record("Cartridge rests above tabletop",absf(box.position.y-top)<.02,{"bottom":box.position.y,"table_top":top,"speed":cart.linear_velocity.length()})
		cart.begin_hold(home.camera);cart.global_transform=home.console.global_transform*home.slot_pose();cart.end_hold(Vector3.ZERO)
		await settle(2)
		var inserted_stability := await stability(2)
		record("Console insertion stays stable",home.inserted==cart and inserted_stability.maximum_displacement_metres<.02 and inserted_stability.maximum_speed_mps<.1,inserted_stability)
		await capture_scene("console",Vector3(.1,1.4,.30),Vector3(0,.95,-.9))
		if cart.label_viewport: cart.label_viewport.get_texture().get_image().save_png(output+"/cartridge-label.png")
		if home.tv_viewport: home.tv_viewport.get_texture().get_image().save_png(output+"/monitor.png")
		# Trigger the actual configuration callback and assign an actual library app.
		for panel in home.panels:
			if panel.uid=="shelf_config": panel.content.pressed.emit();break
		home.assign_shelf(0,app_id)
		record("Bookshelf configuration and slot",home.ui.shelf_mode and home.shelf_carts.has(0))
		await capture_scene("bookshelf",Vector3(-2.4,1.5,.3),home.shelf.global_position)
		var hand: HomeHand=home.right_hand
		home.inserted=null;home.update_monitor()
		var hand_pose := hand.global_transform
		hand.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.5,.6))
		cart.set_pinned(false);cart.global_transform=hand.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,0,-2))
		hand.grab(cart,cart.global_position)
		for i in range(220): hand.manipulate_held(1.0/90,Vector2(0,-1))
		var grip_gap: float=(cart.global_transform*hand.authored_grip).origin.distance_to(hand.global_position)
		record("Synthetic pull attaches grip to controller",hand.attached and grip_gap<.001,{"grip_error_metres":grip_gap})
		for i in range(50): hand.manipulate_held(1.0/90,Vector2(0,1))
		record("Synthetic push releases hand attachment",not hand.attached and cart.global_position.distance_to(hand.global_position)>.3)
		hand.velocity=Vector3.ZERO;hand.release();hand.global_transform=hand_pose
	var player_pose: Transform3D=home.player.global_transform
	var rig_pose: Transform3D=home.rig.transform
	HomeData.settings.turn_mode="smooth";HomeData.settings.move_mode="walk"
	var camera_before: Vector3=home.camera.global_position
	var yaw_before: float=home.rig.rotation.y
	home.apply_locomotion(Vector2(0,1),1,1.0/90)
	var movement: Vector3=home.camera.global_position-camera_before
	var yaw_delta: float=angle_difference(yaw_before,home.rig.rotation.y)
	record("Synthetic walking and turning in same frame",movement.length()>.001 and yaw_delta<-.001,{"movement_metres":movement.length(),"yaw_radians":yaw_delta})
	home.player.global_transform=player_pose;home.rig.transform=rig_pose
	var window: HomePanel=home.tools_panel
	var saved_pose := window.global_transform
	var normals := [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]
	var positions := [Vector3(2.95,1.5,0),Vector3(-2.95,1.5,0),Vector3(0,1.5,2.95),Vector3(0,1.5,-2.95)]
	var walls_ok := true
	for i in range(4):
		window.global_position=positions[i];window.dock_to_wall()
		walls_ok=walls_ok and window.global_basis.z.dot(normals[i])>.99
	record("Windows face away from every wall",walls_ok)
	record("UI excluded from prop physics",window.collision_layer==4 and window.collision_mask==0)
	window.global_position=Vector3(0,1.5,0);window.dock_to_wall()
	record("Window pulls off wall",window.wall_normal==Vector3.ZERO)
	window.global_transform=saved_pose
	window.apply_size(1.4);record("Window resize dimensions",window.dimensions.is_equal_approx(window.base_dimensions*1.4));window.apply_size(1)
	home.ui.search.text="__no_matching_framehome_probe__";home.ui.refresh_games()
	record("Search filters game list",home.ui.games.get_child_count()==1)
	home.ui.search.text="";home.ui.refresh_games()
	home.ui.file_dialog("model",FileDialog.FILE_MODE_OPEN_FILE)
	await settle(.3)
	var dialog: FileDialog
	for child in home.ui.root.get_children():
		if child is FileDialog: dialog=child;break
	record("Import dialog stays embedded",is_instance_valid(dialog) and not dialog.use_native_dialog and window.viewport.gui_embed_subwindows)
	window.viewport.get_texture().get_image().save_png(output+"/import-dialog.png")
	if dialog: dialog.canceled.emit()
	var imported := HomeData.import_model(output+"/import-fixture.glb")
	record("glTF import packages model",imported.begins_with("Imported"),{"message":imported})
	var focus_before: bool=home.input_focused;home.input_focused=true
	var arrow: Node3D=home.toys.model(AssetLibrary.path_for("arrow"));arrow.position=Vector3(1,1.8,0)
	arrow.look_at(Vector3(1,1.8,3),Vector3.UP,true)
	var shot := {"node":arrow,"v":Vector3(0,0,15),"age":0.0,"stuck":false,"ignore":RID()}
	home.toys.arrows.append(shot);await settle(.4)
	record("Arrow swept collision sticks in wall",shot.stuck)
	var gun: HomeProp=home.spawn_prop("paintball_gun","probe_gun",AssetLibrary.path_for("paintball_gun"),Transform3D(Basis.IDENTITY,Vector3(1.5,1.6,0)))
	gun.set_pinned(true);home.toys.fire_paint(gun);await settle(.5)
	record("Paintball hits surface",not home.toys.marks.is_empty())
	home.toys.inflate(gun,true,.8);home.toys.release_balloon(Vector3.BACK)
	var first_height: float=home.toys.balloons[0].node.position.y if not home.toys.balloons.is_empty() else -100
	await settle(.5)
	record("Released balloon floats",not home.toys.balloons.is_empty() and home.toys.balloons[0].node.position.y>first_height)
	if not home.toys.balloons.is_empty(): home.toys.pop_balloon(home.toys.balloons[0].node)
	record("Balloon pops",home.toys.balloons.is_empty())
	home.input_focused=focus_before
	report["fps_at_finish"]=Engine.get_frames_per_second()
	HomeData.apply_document(original);home.restore_layout();home.save_room()
	completed=true;report["completed"]=true;write_report()
	print("DEVICE_CHECK_COMPLETE ",output)
	get_tree().quit()
