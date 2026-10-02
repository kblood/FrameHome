# SPDX-License-Identifier: GPL-3.0-or-later
class_name HomeUI
extends RefCounted

var home: Node
var root: PanelContainer
var games: VBoxContainer
var search: LineEdit
var status: Label
var object_list: ItemList
var selected_label: Label
var grip_controls: VBoxContainer
var point_select: OptionButton
var point_index := 0
var editor_busy := false
var shelf_slot := 0
var shelf_mode := false
var library_ids: Array[String] = []
var pin_button: Button

func build(owner: Node) -> Control:
	home=owner;root=PanelContainer.new()
	var theme := Theme.new();theme.default_font_size=23;root.theme=theme
	var bg := StyleBoxFlat.new();bg.bg_color=Color("14202d");bg.corner_radius_top_left=18;bg.corner_radius_top_right=18
	bg.content_margin_left=20;bg.content_margin_right=20;bg.content_margin_top=16;bg.content_margin_bottom=16
	root.add_theme_stylebox_override("panel",bg)
	var column := VBoxContainer.new();root.add_child(column)
	var title := Label.new();title.text="FRAMEHOME";title.add_theme_font_size_override("font_size",34);column.add_child(title)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.text=Catalog.status;column.add_child(status)
	var tabs := TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(tabs)
	var game_tab := VBoxContainer.new();game_tab.name="Games";tabs.add_child(game_tab)
	search=LineEdit.new();search.placeholder_text="Search installed games / apps";game_tab.add_child(search)
	search.text_changed.connect(func(_text): refresh_games())
	var keyboard := GridContainer.new();keyboard.columns=10;keyboard.visible=false
	button(game_tab,"Search keyboard",func(): keyboard.visible=not keyboard.visible)
	game_tab.add_child(keyboard)
	for key in "1234567890qwertyuiopasdfghjklzxcvbnm":
		var key_button := button(keyboard,key.to_upper(),func(): search.text+=key;refresh_games())
		key_button.custom_minimum_size=Vector2(64,42)
	button(keyboard,"Space",func(): search.text+=" ";refresh_games())
	button(keyboard,"⌫",func(): search.text=search.text.left(-1);refresh_games())
	button(keyboard,"Clear",func(): search.text="";refresh_games())
	var actions := HBoxContainer.new();game_tab.add_child(actions)
	button(actions,"Reload",func(): Catalog.refresh())
	var systems := CheckButton.new();systems.text="Show tools";systems.button_pressed=HomeData.settings.show_tools
	systems.toggled.connect(func(v): HomeData.settings.show_tools=v;refresh_games());actions.add_child(systems)
	var shelf := HBoxContainer.new();game_tab.add_child(shelf)
	var toggle := CheckButton.new();toggle.name="ShelfMode";toggle.text="Place in bookshelf";shelf.add_child(toggle)
	toggle.toggled.connect(func(v): shelf_mode=v;refresh_games())
	var slots := OptionButton.new();shelf.add_child(slots)
	for i in range(20): slots.add_item("Slot %d" % (i+1))
	slots.item_selected.connect(func(i): shelf_slot=i)
	var scroll := ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;game_tab.add_child(scroll)
	games=VBoxContainer.new();games.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(games)
	var object_tab := VBoxContainer.new();object_tab.name="Room";tabs.add_child(object_tab)
	var add := HBoxContainer.new();object_tab.add_child(add)
	var model := OptionButton.new();model.size_flags_horizontal=Control.SIZE_EXPAND_FILL;add.add_child(model)
	for id in AssetLibrary.MASSES:
		if id=="cartridge": continue
		library_ids.append(id);model.add_item(str(id).capitalize())
	button(add,"Add",func(): home.add_library_object(library_ids[model.selected]))
	button(object_tab,"Import GLB / glTF…",func(): file_dialog("model",FileDialog.FILE_MODE_OPEN_FILE))
	var imported := OptionButton.new();imported.name="Imports";object_tab.add_child(imported)
	for name in HomeData.imported: imported.add_item(HomeData.imported[name].label);imported.set_item_metadata(imported.item_count-1,name)
	button(object_tab,"Place imported model",func():
		if imported.selected>=0: home.add_import(imported.get_item_metadata(imported.selected)))
	object_list=ItemList.new();object_list.custom_minimum_size.y=300;object_list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	object_tab.add_child(object_list);object_list.item_selected.connect(func(i):
		home.selected=object_list.get_item_metadata(i);refresh_selection())
	selected_label=Label.new();selected_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;object_tab.add_child(selected_label)
	var edit := HBoxContainer.new();object_tab.add_child(edit)
	pin_button=button(edit,"Pin / unpin",func():
		if home.selected is HomeProp:
			home.checkpoint();home.selected.set_pinned(not home.selected.pinned);home.save_room();refresh_selection())
	button(edit,"Remove",func(): home.remove_selected())
	button(edit,"Undo",func(): home.undo())
	var packages := HBoxContainer.new();object_tab.add_child(packages)
	button(packages,"Export room…",func(): file_dialog("export",FileDialog.FILE_MODE_SAVE_FILE))
	button(packages,"Import room…",func(): file_dialog("room",FileDialog.FILE_MODE_OPEN_FILE))
	var grip_tab := ScrollContainer.new();grip_tab.name="Grip editor";tabs.add_child(grip_tab)
	grip_controls=VBoxContainer.new();grip_controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grip_tab.add_child(grip_controls)
	build_settings(tabs)
	build_toys(tabs)
	Catalog.catalog_changed.connect(refresh_games);HomeData.changed.connect(refresh_objects)
	Catalog.artwork_changed.connect(func(_id): refresh_games())
	refresh_games();refresh_objects();refresh_selection()
	return root

func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new();b.text=text;b.custom_minimum_size.y=48;b.pressed.connect(action);parent.add_child(b);return b

func text(parent: Node, value: String, font_size := 22) -> Label:
	var label := Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size);parent.add_child(label);return label

func refresh_games() -> void:
	if not is_instance_valid(games): return
	for child in games.get_children(): games.remove_child(child);child.queue_free()
	status.text=Catalog.status
	var needle := search.text.to_lower()
	var count := 0
	for app in Catalog.apps:
		if app.system and not HomeData.settings.show_tools: continue
		if not needle.is_empty() and needle not in app.name.to_lower(): continue
		var row := HBoxContainer.new();games.add_child(row)
		var cover := TextureRect.new();cover.custom_minimum_size=Vector2(65,80);cover.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;cover.texture=Catalog.cover(app.id);row.add_child(cover)
		var name := text(row,app.name,21);name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name.custom_minimum_size.x=200
		button(row,"Open",func(): home.launch_game(app.id))
		button(row,"Shelf" if shelf_mode else "Cartridge",func():
			if shelf_mode: home.assign_shelf(shelf_slot,app.id)
			else: home.make_cartridge(app.id))
		count+=1
	if count==0: text(games,"No matching installed apps. Steam must be installed on the machine running FrameHome.")

func refresh_objects() -> void:
	if not object_list: return
	object_list.clear()
	for prop in home.props:
		if not is_instance_valid(prop): continue
		object_list.add_item(Catalog.find_app(prop.app_id).name if not prop.app_id.is_empty() else prop.model_id.capitalize())
		object_list.set_item_metadata(object_list.item_count-1,prop)
	for panel in home.panels:
		if is_instance_valid(panel):
			object_list.add_item(panel.uid.capitalize()+" window");object_list.set_item_metadata(object_list.item_count-1,panel)

func refresh_selection() -> void:
	if not grip_controls: return
	for child in grip_controls.get_children(): grip_controls.remove_child(child);child.queue_free()
	var prop = home.selected
	if not is_instance_valid(prop): selected_label.text="Select any built-in or imported object";return
	selected_label.text="Selected: "+str(prop.uid)
	if not prop is HomeProp:
		text(grip_controls,"Select an object in Room. Windows use their blue bar and green resize corner.");return
	text(grip_controls,"Grip editor · "+prop.model_id.capitalize(),28)
	text(grip_controls,"Edit any built-in or imported model. The marker shows the controller pose. Release and grab again after editing.")
	var hand := CheckButton.new();hand.text="Attach to hand when pulled close";hand.button_pressed=prop.handheld()
	grip_controls.add_child(hand);hand.toggled.connect(func(value):
		var p: Dictionary=HomeData.grips.get(prop.grip_key(),{}).duplicate(true)
		p["handheld"]=value;HomeData.grips[prop.grip_key()]=p;HomeData.save())
	var points := HomeData.profile_points(prop.grip_key(),prop.default_grips)
	point_index=clampi(point_index,0,maxi(0,points.size()-1))
	point_select=OptionButton.new();grip_controls.add_child(point_select)
	for point in points: point_select.add_item(point.get("name","Grip")+" · "+point.get("hand","both"))
	point_select.select(point_index);point_select.item_selected.connect(func(i): point_index=i;refresh_selection())
	var add_row := HBoxContainer.new();grip_controls.add_child(add_row)
	button(add_row,"Add point",func():
		points.append({"name":"Grip %d" % (points.size()+1),"hand":"both","p":[0,0,0],"q":[0,0,0,1]})
		store_points(prop,points);point_index=points.size()-1;refresh_selection())
	button(add_row,"Remove point",func():
		if points.size()>1: points.remove_at(point_index);store_points(prop,points);refresh_selection())
	var side := OptionButton.new();for_side_options(side);grip_controls.add_child(side)
	side.select(["both","left","right"].find(points[point_index].get("hand","both")))
	side.item_selected.connect(func(i): points[point_index]["hand"]=["both","left","right"][i];store_points(prop,points))
	var pose: Transform3D = HomeData.read_pose(points[point_index])
	var angles := pose.basis.get_euler()*180/PI
	for axis in range(3):
		var row := HBoxContainer.new();grip_controls.add_child(row);text(row,["X","Y","Z"][axis]+" metres")
		spin(row,pose.origin[axis],-.0-4,4,.005,func(value):
			var p=HomeData.read_pose(points[point_index]);p.origin[axis]=value
			points[point_index].merge(HomeData.pose(p),true);store_points(prop,points))
		text(row,"Rotation °")
		spin(row,angles[axis],-180,180,5,func(value):
			var p=HomeData.read_pose(points[point_index]);var e=p.basis.get_euler();e[axis]=deg_to_rad(value)
			p.basis=Basis.from_euler(e);points[point_index].merge(HomeData.pose(p),true);store_points(prop,points))
	var capture := HBoxContainer.new();grip_controls.add_child(capture)
	for side_name in ["left","right"]:
		button(capture,"Capture "+side_name+" (3 sec)",func(): home.capture_grip(prop,point_index,side_name))
	button(grip_controls,"Reset model grips",func(): HomeData.grips.erase(prop.grip_key());HomeData.save();refresh_selection())
	if prop.model_path.begins_with("user://"):
		text(grip_controls,"Default size for future instances · longest side (metres)")
		spin(grip_controls,HomeData.imported[prop.model_id].get("size",.6),.03,4,.05,func(v):
			HomeData.imported[prop.model_id]["size"]=v;HomeData.save())
		text(grip_controls,"Lower detail: import an optimized GLB, then choose it as the alternate mesh.")
		var alternate := OptionButton.new();alternate.add_item("Original model");alternate.set_item_metadata(0,"")
		for file in HomeData.imported:
			alternate.add_item(HomeData.imported[file].label);alternate.set_item_metadata(alternate.item_count-1,file)
			if HomeData.grips.get(prop.grip_key(),{}).get("detail_model","")==file: alternate.select(alternate.item_count-1)
		grip_controls.add_child(alternate)
		alternate.item_selected.connect(func(i):
			var current: Dictionary=HomeData.grips.get(prop.grip_key(),{}).duplicate(true)
			current["detail_model"]=alternate.get_item_metadata(i);HomeData.grips[prop.grip_key()]=current;HomeData.save())

func for_side_options(option: OptionButton) -> void:
	for value in ["Both hands","Left hand","Right hand"]: option.add_item(value)

func store_points(prop: HomeProp, points: Array) -> void:
	var profile: Dictionary=HomeData.grips.get(prop.grip_key(),{}).duplicate(true)
	profile["points"]=points.duplicate(true);HomeData.grips[prop.grip_key()]=profile
	HomeData.save();home.show_grip_marker(prop,HomeData.read_pose(points[point_index]))

func spin(parent: Node, value: float, low: float, high: float, step: float, action: Callable) -> void:
	var input := SpinBox.new();input.min_value=low;input.max_value=high;input.step=step;input.value=value
	input.custom_minimum_size.x=145;input.value_changed.connect(action);parent.add_child(input)

func build_settings(tabs: TabContainer) -> void:
	var settings := VBoxContainer.new();settings.name="Controls";tabs.add_child(settings)
	text(settings,"Left stick moves relative to your headset. Right stick turns. Both work together.")
	text(settings,"While holding something: left stick still moves; right stick up/down changes distance. For windows, left/right rotates; grab the green corner to resize.")
	for entry in [["turn_mode",["smooth","snap"]],["move_mode",["walk","teleport"]]]:
		var row := HBoxContainer.new();settings.add_child(row)
		for value in entry[1]:
			button(row,str(value).capitalize(),func(): HomeData.settings[entry[0]]=value;HomeData.save();notice("Selected "+value))
	text(settings,"Smooth turn degrees / second")
	spin(settings,rad_to_deg(HomeData.settings.turn_speed),30,150,5,func(v): HomeData.settings.turn_speed=deg_to_rad(v);HomeData.save())
	text(settings,"Walking metres / second")
	spin(settings,HomeData.settings.walk_speed,.3,2,.1,func(v): HomeData.settings.walk_speed=v;HomeData.save())
	text(settings,"Desktop: WASD moves; Q/E turns; right mouse looks; left mouse clicks; G grabs/drops; wheel changes held distance. Esc releases the mouse.")
	button(settings,"Bring tools window here",func(): home.recenter_tools())
	button(settings,"Save room",func(): home.save_room();notice("Room saved"))
	button(settings,"Restore original furniture",func(): home.reset_room())

func build_toys(tabs: TabContainer) -> void:
	var toys := VBoxContainer.new();toys.name="Toys";tabs.add_child(toys)
	text(toys,"Add the bow, paintball gun or balloon inflator from Room. Grip the handle before using trigger.")
	for kind in ["paint","balloon"]:
		text(toys,kind.capitalize()+" color")
		var grid := GridContainer.new();grid.columns=4;toys.add_child(grid)
		for i in range(8):
			var b := button(grid,AssetLibrary.COLOR_NAMES[i],func():
				HomeData.settings[kind+"_color"]=i
				if kind=="balloon": HomeData.settings.balloon_random=false
				HomeData.save())
			b.modulate=AssetLibrary.PALETTE[i]
	var random := CheckButton.new();random.text="Random balloon colors";random.button_pressed=HomeData.settings.balloon_random
	toys.add_child(random);random.toggled.connect(func(value): HomeData.settings.balloon_random=value;HomeData.save())
	text(toys,"Bow: with the other hand free, hold trigger near the string, pull back, then release. Paintball: trigger fires. Balloon: hold to inflate, release to float. Arrows and paintballs pop balloons.")
	for kind in ["arrows","paint","balloons"]:
		button(toys,"Clear "+kind,func(): home.toys.clear_kind(kind))

func file_dialog(mode: String, file_mode: int) -> void:
	var dialog := FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=file_mode
	dialog.use_native_dialog=false;dialog.size=Vector2i(850,850)
	dialog.filters=PackedStringArray(["*.glb,*.gltf ; glTF model"]) if mode=="model" else PackedStringArray(["*.framehome ; FrameHome room"])
	root.add_child(dialog);dialog.popup_centered()
	dialog.file_selected.connect(func(path):
		if mode=="model":
			notice(HomeData.import_model(path));home.refresh_import_options()
		elif mode=="export": home.save_room();notice(HomeData.export_room(path))
		else:
			var message := HomeData.import_room(path);notice(message)
			if message=="Room imported": home.restore_layout()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)

func notice(message: String) -> void:
	status.text=message
