# SPDX-License-Identifier: GPL-3.0-or-later
extends Node3D

var props: Array[HomeProp] = []
var panels: Array[HomePanel] = []
var selected: Node3D
var player: CharacterBody3D
var rig: XROrigin3D
var camera: XRCamera3D
var left_hand: HomeHand
var right_hand: HomeHand
var ui: HomeUI
var toys: RoomToys
var tools_panel: HomePanel
var tv_viewport: SubViewport
var tv_image: TextureRect
var tv_title: Label
var inserted: HomeProp
var headset: HomeProp
var console: HomeProp
var shelf: HomeProp
var shelf_carts: Dictionary = {}
var xr_active := false
var input_focused := true
var turn_latched := false
var teleport_latched := false
var teleport_valid := false
var teleport_position := Vector3.ZERO
var teleport_marker: MeshInstance3D
var desktop_held: Node3D
var desktop_distance := 1.0
var desktop_panel: HomePanel
var desktop_down := false
var desktop_pitch := 0.0
var don_time := 0.0
var last_launch := ""
var autosave_timer := 0.0
var grip_marker: Node3D
var restoring := false

func _ready() -> void:
	setup_environment();setup_player()
	ui=HomeUI.new();toys=RoomToys.new();toys.home=self;add_child(toys)
	build_default_props()
	tools_panel=HomePanel.new();add_child(tools_panel)
	tools_panel.configure("tools",Vector2(1.05,1.18),ui.build(self));panels.append(tools_panel)
	tools_panel.position=Vector3(1.15,1.55,-1.3);tools_panel.look_at(Vector3(0,1.5,0),Vector3.UP,true)
	create_recent_panel()
	if not HomeData.layout.is_empty(): restore_layout()
	else: save_room()
	ui.refresh_objects();ui.refresh_games()
	Catalog.artwork_changed.connect(func(id):
		if inserted and inserted.app_id==id: update_monitor())
	Catalog.catalog_changed.connect(update_monitor)
	get_viewport().msaa_3d=Viewport.MSAA_2X
	print("FrameHome initialized; XR=",xr_active,"; platform=",OS.get_name())

func setup_environment() -> void:
	var world := WorldEnvironment.new();var environment := Environment.new();world.environment=environment
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("7d94a6")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("d2deee");environment.ambient_light_energy=.6
	add_child(world)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-25,0);sun.light_energy=1.2
	sun.shadow_enabled=true;sun.directional_shadow_max_distance=12;add_child(sun)
	static_box(Vector3(6,.08,6),Vector3(0,-.04,0),Color("716358"))
	for sign in [-1,1]:
		static_box(Vector3(.08,2.75,6),Vector3(sign*3,1.375,0),Color("aaa59b"))
		static_box(Vector3(6,2.75,.08),Vector3(0,1.375,sign*3),Color("b9b2a5"))
	teleport_marker=AssetLibrary.box_mesh(Vector3(.4,.006,.4),Color("4ccba1"));teleport_marker.visible=false;add_child(teleport_marker)

func static_box(dimensions: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.position=at;add_child(body)
	var mesh := AssetLibrary.box_mesh(dimensions,color);body.add_child(mesh)
	var col := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=dimensions;col.shape=shape;body.add_child(col)

func setup_player() -> void:
	player=CharacterBody3D.new();player.collision_layer=0;player.collision_mask=1;add_child(player)
	var shape := CapsuleShape3D.new();shape.radius=.2;shape.height=1.6
	var collider := CollisionShape3D.new();collider.shape=shape;collider.position.y=.85;player.add_child(collider)
	rig=XROrigin3D.new();player.add_child(rig)
	camera=XRCamera3D.new();camera.near=.03;rig.add_child(camera)
	var xr := XRServer.find_interface("OpenXR")
	if "--desktop" not in OS.get_cmdline_user_args() and xr and xr.is_initialized():
		xr_active=true;get_viewport().use_xr=true;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr.session_focused.connect(func(): input_focused=true)
		xr.session_visible.connect(func(): input_focused=false;reset_inputs())
		xr.session_stopping.connect(func(): input_focused=false;reset_inputs();save_room())
	else: camera.position.y=1.65
	for side in ["left","right"]:
		var hand := HomeHand.new();hand.home=self;hand.side=side;rig.add_child(hand)
		var aim := XRController3D.new();aim.tracker=side+"_hand";aim.pose="aim";rig.add_child(aim);hand.aim=aim
		if side=="left": left_hand=hand
		else: right_hand=hand

func build_default_props() -> void:
	for entry in AssetLibrary.DEFAULTS:
		var prop := spawn_prop(entry[0],entry[0],AssetLibrary.path_for(entry[0]),Transform3D(Basis(Vector3.UP,PI),entry[1]))
		if entry[0]=="headset": prop.set_pinned(true)
	setup_fixtures()

func spawn_prop(id: String, uid: String, path: String, pose: Transform3D, model_scale := 1.0) -> HomeProp:
	var prop := HomeProp.new();prop.home=self;prop.configure(id,path,uid,model_scale)
	add_child(prop);prop.global_transform=pose;props.append(prop)
	match id:
		"console": console=prop
		"headset": headset=prop
		"shelf": shelf=prop
	return prop

func setup_fixtures() -> void:
	for prop in props:
		if prop.model_id=="tv": create_monitor(prop)
	create_shelf_config()

func create_shelf_config() -> void:
	if is_instance_valid(shelf):
		var button := Button.new();button.text="⚙";button.add_theme_font_size_override("font_size",80)
		button.pressed.connect(func():
			recenter_tools();ui.shelf_mode=true;ui.refresh_games()
			var toggle = ui.root.find_child("ShelfMode",true,false)
			if toggle: toggle.button_pressed=true
			ui.notice("Choose a shelf slot in Games, then select Shelf next to a game"))
		var panel := HomePanel.new();add_child(panel);panel.configure("shelf_config",Vector2(.07,.07),button)
		panel.viewport.size=Vector2i(128,128)
		(panel.panel_shape.shape as BoxShape3D).size=Vector3(.08,.08,.025)
		panel.bar.visible=false;panel.corner.visible=false
		panel.set_meta("fixture",shelf);panel.set_meta("offset",Transform3D(Basis(Vector3.UP,PI),Vector3(-.44,.61,-.15)))
		panels.append(panel)

func create_monitor(prop: HomeProp) -> void:
	tv_viewport=SubViewport.new();tv_viewport.size=Vector2i(1280,720);tv_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	prop.add_child(tv_viewport)
	var bg := ColorRect.new();bg.color=Color("101a24");bg.size=Vector2(1280,720);tv_viewport.add_child(bg)
	tv_image=TextureRect.new();tv_image.position=Vector2(40,35);tv_image.size=Vector2(470,550)
	tv_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;tv_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;tv_viewport.add_child(tv_image)
	tv_title=Label.new();tv_title.position=Vector2(550,85);tv_title.size=Vector2(680,500)
	tv_title.add_theme_font_size_override("font_size",48);tv_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tv_title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;tv_viewport.add_child(tv_title)
	var screen := MeshInstance3D.new();var quad := QuadMesh.new();quad.size=Vector2(.64,.36);screen.mesh=quad
	screen.position=Vector3(0,.05,-.0435);screen.rotation.y=PI
	var mat := StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_texture=tv_viewport.get_texture()
	screen.material_override=mat;prop.add_child(screen);update_monitor()

func create_recent_panel() -> void:
	var content := VBoxContainer.new();ui.text(content,"Recent games",36)
	for id in HomeData.recent: ui.button(content,Catalog.find_app(id).name,func(): launch_game(id))
	if HomeData.recent.is_empty(): ui.text(content,"Launched games appear here")
	var panel := HomePanel.new();add_child(panel);panel.configure("recent",Vector2(.6,.55),content)
	panel.position=Vector3(-1.3,1.6,-1.25);panel.look_at(Vector3(0,1.5,0),Vector3.UP,true);panels.append(panel)

func _physics_process(dt: float) -> void:
	if not is_instance_valid(camera): return
	if input_focused: locomotion(minf(dt,.05))
	for panel in panels:
		if panel.has_meta("fixture"):
			var fixture = panel.get_meta("fixture")
			if is_instance_valid(fixture): panel.global_transform=fixture.global_transform*panel.get_meta("offset")
	if inserted:
		if not is_instance_valid(inserted): inserted=null;update_monitor()
		elif inserted.held_by: inserted.set_pinned(false);inserted=null;update_monitor()
		elif is_instance_valid(console): inserted.global_transform=console.global_transform*slot_pose()
	for slot in shelf_carts.keys():
		var cart = shelf_carts[slot]
		if not is_instance_valid(cart) or cart.held_by:
			if is_instance_valid(cart): cart.set_pinned(false)
			shelf_carts.erase(slot);HomeData.shelf_slots.erase(str(slot))
		elif is_instance_valid(shelf): cart.global_transform=shelf.global_transform*shelf_pose(int(slot))
	if is_instance_valid(headset):
		headset.visible=is_instance_valid(inserted) and is_instance_valid(console)
		headset.collision_layer=2 if headset.visible and headset.held_by==null else 0
		if headset.visible and headset.held_by==null and desktop_held!=headset:
			headset.global_transform=console.global_transform*Transform3D(Basis.IDENTITY,Vector3(.09,.42,0))
		if headset.visible and headset.held_by and headset.global_position.distance_to(camera.global_position)<.18:
			don_time+=dt
			if don_time>.65: launch_game(inserted.app_id);don_time=-10
		else: don_time=0
	if not xr_active: desktop_pointer(dt)
	autosave_timer+=dt
	if autosave_timer>10: autosave_timer=0;save_room()

func locomotion(dt: float) -> void:
	var move := left_hand.get_vector2("primary") if xr_active and left_hand.get_is_active() else Vector2.ZERO
	var turn := right_hand.get_vector2("primary").x if xr_active and right_hand.get_is_active() else 0.0
	if left_hand.pointed_panel and left_hand.is_button_pressed("primary_click"): move=Vector2.ZERO
	if right_hand.pointed_panel and right_hand.is_button_pressed("primary_click"): turn=0
	if not xr_active and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		move=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
		turn=float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
	if move.length()<.18: move=Vector2.ZERO
	if right_hand.held or left_hand.held or desktop_held: turn=0
	var yaw := 0.0
	if absf(turn)>.25:
		if HomeData.settings.turn_mode=="smooth": yaw=-turn*HomeData.settings.turn_speed*dt
		elif not turn_latched: yaw=-signf(turn)*PI/6
	turn_latched=absf(turn)>.25
	if yaw!=0:
		var pivot := camera.global_position;rig.rotate_y(yaw);player.global_position+=pivot-camera.global_position
	if HomeData.settings.move_mode=="teleport" and xr_active:
		teleport(move.y>.5);move=Vector2.ZERO
	else: teleport_marker.visible=false
	var forward := -camera.global_basis.z;forward.y=0;forward=forward.normalized()
	var right := forward.cross(Vector3.UP)
	var travel: Vector3 = (forward*move.y+right*move.x).limit_length(1)*float(HomeData.settings.walk_speed)
	player.velocity=Vector3(travel.x,-1,travel.z);player.move_and_slide()
	player.global_position.y=0

func teleport(active: bool) -> void:
	if active:
		var start := left_hand.aim.global_position;var velocity := -left_hand.aim.global_basis.z*5
		teleport_valid=false
		for i in range(35):
			var end := start+velocity*.06;velocity.y-=9.81*.06
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,1))
			if not hit.is_empty():
				teleport_valid=hit.normal.y>.8 and absf(hit.position.x)<2.7 and absf(hit.position.z)<2.7
				teleport_position=hit.position;break
			start=end
		teleport_marker.visible=teleport_valid;teleport_marker.global_position=teleport_position+Vector3.UP*.006
	elif teleport_latched and teleport_valid:
		var offset := camera.global_position-player.global_position;offset.y=0
		player.global_position=teleport_position-offset;teleport_marker.visible=false;teleport_valid=false
	teleport_latched=active

func _unhandled_input(event: InputEvent) -> void:
	if xr_active: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:
			Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		if event.button_index==MOUSE_BUTTON_LEFT: desktop_down=event.pressed
		if event.pressed and not desktop_held and desktop_panel:
			var scroll := 1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else (-1.0 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else 0.0)
			var hit := desktop_hit()
			if not hit.is_empty(): desktop_panel.pointer(hit.position,desktop_down,scroll)
		if event.pressed and desktop_held:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP: desktop_distance=maxf(.08,desktop_distance-.15)
			if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: desktop_distance=minf(8,desktop_distance+.15)
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		rig.rotate_y(-event.relative.x*.003);desktop_pitch=clampf(desktop_pitch-event.relative.y*.003,-1.3,1.3);camera.rotation.x=desktop_pitch
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		if event.keycode==KEY_G: desktop_grab()

func desktop_hit() -> Dictionary:
	var cursor := get_viewport().get_mouse_position()
	if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED: cursor=get_viewport().get_visible_rect().size/2
	var from := camera.project_ray_origin(cursor);var to := from+camera.project_ray_normal(cursor)*8
	var query := PhysicsRayQueryParameters3D.create(from,to,7)
	if desktop_held is CollisionObject3D: query.exclude=[desktop_held.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func desktop_pointer(_dt: float) -> void:
	var hit := desktop_hit()
	var panel: HomePanel = hit.collider if not hit.is_empty() and hit.collider is HomePanel and desktop_held==null else null
	if panel!=desktop_panel:
		if desktop_panel: desktop_panel.release_pointer()
		desktop_panel=panel
	if panel: panel.pointer(hit.position,desktop_down)
	if desktop_held:
		desktop_held.global_position=camera.global_position-camera.global_basis.z*desktop_distance
		if desktop_held is HomeProp and desktop_held.clear_at(desktop_held.global_transform): desktop_held.last_clear_pose=desktop_held.global_transform
		if desktop_held is HomePanel:
			desktop_held.look_at(camera.global_position,Vector3.UP,true);desktop_held.dock_to_wall()

func desktop_grab() -> void:
	if desktop_held:
		if desktop_held is HomeProp: desktop_held.end_hold(Vector3.ZERO)
		else: desktop_held.held_by=null
		desktop_held=null;save_room();return
	var hit := desktop_hit()
	if hit.is_empty() or not (hit.collider is HomeProp or hit.collider is HomePanel): return
	if hit.collider.has_meta("fixture"): return
	checkpoint();desktop_held=hit.collider;selected=desktop_held
	desktop_distance=camera.global_position.distance_to(desktop_held.global_position)
	if desktop_held is HomeProp: desktop_held.begin_hold(camera)
	else: desktop_held.held_by=camera
	ui.refresh_selection()

func prop_released(prop: HomeProp) -> void:
	if prop.model_id=="cartridge" and is_instance_valid(console) and prop.global_position.distance_to((console.global_transform*slot_pose()).origin)<.13:
		if inserted and inserted!=prop: inserted.set_pinned(false);inserted.global_position.x+=.3
		inserted=prop;prop.set_pinned(true);prop.global_transform=console.global_transform*slot_pose();update_monitor()

func slot_pose() -> Transform3D:
	return Transform3D(Basis.IDENTITY,Vector3(-.10,.04+.095+.006,0))

func shelf_pose(slot: int) -> Transform3D:
	var ys := [.114,.416,.718,1.020]
	return Transform3D(Basis.IDENTITY,Vector3(-.38+(slot%5)*.19,ys[slot/5]-.7+.095+.004,-.04))

func assign_shelf(slot: int, app_id: String) -> void:
	if not is_instance_valid(shelf): ui.notice("Add a shelf first");return
	checkpoint()
	if shelf_carts.has(slot) and is_instance_valid(shelf_carts[slot]): remove_prop(shelf_carts[slot])
	var cart := make_cartridge(app_id,false)
	cart.set_pinned(true);cart.global_transform=shelf.global_transform*shelf_pose(slot)
	shelf_carts[slot]=cart;HomeData.shelf_slots[str(slot)]={"app":app_id,"uid":cart.uid};save_room()

func make_cartridge(app_id: String, record := true) -> HomeProp:
	if record: checkpoint()
	var pos := camera.global_position-camera.global_basis.z*.7;pos.y=1.1
	var prop := spawn_prop("cartridge","cart_"+str(Time.get_ticks_usec()),AssetLibrary.path_for("cartridge"),Transform3D(Basis(Vector3.UP,PI),pos))
	prop.set_app(app_id);ui.refresh_objects();save_room();return prop

func add_library_object(id: String) -> void:
	if id in ["console","headset","tv","shelf"]:
		for existing in props:
			if existing.model_id==id:
				selected=existing;ui.refresh_selection();ui.notice("Already in the room: "+id);return
	checkpoint()
	var p := camera.global_position-camera.global_basis.z*1.2;p.y=.8
	var prop := spawn_prop(id,id+"_"+str(Time.get_ticks_usec()),AssetLibrary.path_for(id),Transform3D(Basis(Vector3.UP,PI),p))
	if id=="tv": create_monitor(prop)
	if id=="shelf": create_shelf_config()
	selected=prop;ui.refresh_objects();ui.refresh_selection();save_room()

func add_import(file: String) -> void:
	if not HomeData.valid_asset_name(file): return
	checkpoint()
	var path := "user://imports/"+file
	var alternate: String=HomeData.grips.get("import:"+file,{}).get("detail_model","")
	if HomeData.valid_asset_name(alternate): path="user://imports/"+alternate
	var model := AssetLibrary.load_model(path)
	if model==null: ui.notice("Could not load model");return
	var bounds := AssetLibrary.bounds(model);model.free()
	var size: float=HomeData.imported[file].get("size",.6)
	var factor := size/maxf(bounds.size[bounds.size.max_axis_index()],.001)
	var p := camera.global_position-camera.global_basis.z*1.1
	selected=spawn_prop(file,"import_"+str(Time.get_ticks_usec()),path,Transform3D(Basis.IDENTITY,p),factor)
	ui.refresh_objects();ui.refresh_selection();save_room()

func refresh_import_options() -> void:
	var imports := ui.root.find_child("Imports",true,false) as OptionButton
	if not imports: return
	imports.clear()
	for file in HomeData.imported:
		imports.add_item(HomeData.imported[file].label);imports.set_item_metadata(imports.item_count-1,file)

func remove_selected() -> void:
	if selected is HomeProp:
		checkpoint();remove_prop(selected);selected=null;ui.refresh_objects();ui.refresh_selection();save_room()

func remove_prop(prop: HomeProp) -> void:
	if prop.held_by is HomeHand: prop.held_by.release()
	if desktop_held==prop: desktop_held=null
	if inserted==prop: inserted=null;update_monitor()
	for panel in panels.duplicate():
		if panel.get_meta("fixture",null)==prop: panels.erase(panel);panel.queue_free()
	prop.collision_layer=0;prop.collision_mask=0;prop.freeze=true
	props.erase(prop);prop.queue_free()

func update_monitor() -> void:
	if not is_instance_valid(tv_title): return
	tv_title.text=Catalog.find_app(inserted.app_id).name+"\n\nPut on the virtual headset to launch" if is_instance_valid(inserted) else "Insert a cartridge\n\nYour Steam library, in your room"
	tv_image.texture=Catalog.cover(inserted.app_id) if is_instance_valid(inserted) else null

func launch_game(id: String) -> void:
	if id==last_launch: return
	save_room();var error := Catalog.launch(id)
	if error!=OK: ui.notice("Steam could not launch this installed app: "+str(error));return
	last_launch=id;ui.notice("Opening "+Catalog.find_app(id).name)
	if HomeData.settings.quit_on_launch:
		# Release the scene application's OpenXR session for the selected VR game.
		await get_tree().create_timer(.7).timeout
		get_tree().quit()

func save_room() -> void:
	if restoring or ui==null: return
	HomeData.layout=[]
	for prop in props:
		if is_instance_valid(prop):
			var saved := prop.snapshot();saved["inserted"]=prop==inserted;HomeData.layout.append(saved)
	for panel in panels:
		if is_instance_valid(panel) and not panel.has_meta("fixture"): HomeData.layout.append(panel.snapshot())
	HomeData.save()

func checkpoint() -> void:
	save_room();HomeData.checkpoint()

func restore_layout() -> void:
	restoring=true;reset_inputs();toys.clear_all();selected=null;inserted=null
	for prop in props.duplicate(): remove_prop(prop)
	props.clear();console=null;headset=null;shelf=null;shelf_carts.clear()
	for entry in HomeData.layout:
		if not entry is Dictionary: continue
		if entry.get("panel",false):
			for panel in panels:
				if panel.uid==entry.uid:
					panel.global_transform=HomeData.read_pose(entry.pose);panel.apply_size(float(entry.get("panel_scale",1)))
			continue
		var path := str(entry.get("path",""))
		if not ((path.begins_with("res://assets/furniture/") or path.begins_with("user://imports/")) and path.ends_with(".glb") and not ".." in path): continue
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path): continue
		var prop := spawn_prop(entry.get("model","custom"),entry.get("uid","object"),path,HomeData.read_pose(entry.get("pose",{})),clampf(float(entry.get("scale",1)),.001,100))
		prop.set_pinned(entry.get("pinned",false))
		if not str(entry.get("app","")).is_empty(): prop.set_app(entry.app)
		if entry.get("inserted",false): inserted=prop
	setup_fixtures()
	for slot in HomeData.shelf_slots:
		for prop in props:
			if prop.uid==HomeData.shelf_slots[slot].get("uid",""): shelf_carts[int(slot)]=prop
	restoring=false;ui.refresh_objects();refresh_import_options();update_monitor()

func undo() -> void:
	if HomeData.undo(): restore_layout()

func reset_room() -> void:
	checkpoint();HomeData.layout=[];HomeData.shelf_slots={};restore_layout();build_default_props();ui.refresh_objects();save_room()

func recenter_tools() -> void:
	tools_panel.global_position=camera.global_position-camera.global_basis.z*1.4
	tools_panel.look_at(camera.global_position,Vector3.UP,true)

func capture_grip(prop: HomeProp, index: int, side: String) -> void:
	ui.notice("Place the "+side+" controller at the grip · capturing in 3 seconds")
	await get_tree().create_timer(3).timeout
	var hand := left_hand if side=="left" else right_hand
	if not is_instance_valid(prop) or not hand.get_is_active(): ui.notice("Controller is not tracked");return
	var local := prop.global_transform.affine_inverse()*hand.global_transform
	if local.origin.length()>prop.size.length()+.2: ui.notice("Controller too far from the object");return
	local.origin/=prop.model_scale
	var points := HomeData.profile_points(prop.grip_key(),prop.default_grips)
	if index>=points.size(): return
	checkpoint();points[index].merge(HomeData.pose(local),true);points[index]["hand"]=side
	ui.store_points(prop,points);ui.refresh_selection();ui.notice("Captured "+side+" grip")

func show_grip_marker(prop: HomeProp, pose: Transform3D) -> void:
	if is_instance_valid(grip_marker): grip_marker.queue_free()
	grip_marker=Node3D.new();prop.add_child(grip_marker);pose.origin*=prop.model_scale;grip_marker.transform=pose
	for axis in range(3):
		var dim := Vector3.ONE*.006;dim[axis]=.12
		var line := AssetLibrary.box_mesh(dim,[Color.RED,Color.GREEN,Color.BLUE][axis]);line.position[axis]=.06;grip_marker.add_child(line)

func reset_inputs() -> void:
	if left_hand: left_hand.reset_input()
	if right_hand: right_hand.reset_input()
	turn_latched=false;teleport_latched=false;teleport_valid=false
	if desktop_panel: desktop_panel.release_pointer();desktop_panel=null
	desktop_down=false
	if desktop_held:
		if desktop_held is HomeProp: desktop_held.end_hold(Vector3.ZERO)
		desktop_held=null
	if toys: toys.cancel_draw()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: input_focused=false;reset_inputs();save_room()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN: input_focused=true
	elif what==NOTIFICATION_WM_CLOSE_REQUEST: save_room()
