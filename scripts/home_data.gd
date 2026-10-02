# SPDX-License-Identifier: GPL-3.0-or-later
extends Node

signal changed
var settings: Dictionary = {"turn_mode":"smooth", "move_mode":"walk", "turn_speed":1.6,
	"walk_speed":1.25, "paint_color":5, "balloon_color":0, "balloon_random":true,
	"show_tools":false, "quit_on_launch":true}
var grips: Dictionary = {}
var layout: Array = []
var shelf_slots: Dictionary = {}
var recent: Array = []
var imported: Dictionary = {}
var undo_stack: Array = []
const SAVE := "user://home.json"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://imports")
	DirAccess.make_dir_recursive_absolute("user://covers")
	if FileAccess.file_exists(SAVE):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if data is Dictionary:
			apply_document(data)

func document() -> Dictionary:
	return {"format":"framehome", "version":1, "settings":settings, "grips":grips,
		"layout":layout,"shelf_slots":shelf_slots,"recent":recent,"imported":imported}

func apply_document(data: Dictionary) -> void:
	if data.get("format", "") != "framehome" or int(data.get("version", 0)) != 1:
		return
	settings.merge(data.get("settings", {}), true)
	grips = data.get("grips", {})
	layout = data.get("layout", [])
	shelf_slots = data.get("shelf_slots", {})
	recent = data.get("recent", [])
	imported = data.get("imported", {})
	changed.emit()

func save() -> void:
	var f := FileAccess.open(SAVE + ".tmp", FileAccess.WRITE)
	if f == null:
		push_warning("Cannot save FrameHome: " + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(document(), "\t"))
	f.close()
	DirAccess.rename_absolute(SAVE + ".tmp", SAVE)

func checkpoint() -> void:
	undo_stack.append(document().duplicate(true))
	if undo_stack.size() > 20:
		undo_stack.pop_front()

func undo() -> bool:
	if undo_stack.is_empty(): return false
	apply_document(undo_stack.pop_back())
	save()
	return true

func vector(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func read_vector(v: Array, fallback := Vector3.ZERO) -> Vector3:
	if v.size() != 3: return fallback
	var p := Vector3(float(v[0]),float(v[1]),float(v[2]))
	return p if p.is_finite() else fallback

func pose(t: Transform3D) -> Dictionary:
	var q := t.basis.orthonormalized().get_rotation_quaternion()
	return {"p":vector(t.origin),"q":[q.x,q.y,q.z,q.w],"scale":vector(t.basis.get_scale())}

func read_pose(data: Dictionary) -> Transform3D:
	var q: Array = data.get("q",[0,0,0,1])
	if q.size() != 4: q = [0,0,0,1]
	var quat := Quaternion(float(q[0]),float(q[1]),float(q[2]),float(q[3]))
	if not quat.is_finite() or quat.length_squared() < 0.01: quat = Quaternion.IDENTITY
	var s := read_vector(data.get("scale",[1,1,1]),Vector3.ONE).clamp(Vector3.ONE*0.05,Vector3.ONE*8)
	return Transform3D(Basis(quat.normalized()).scaled(s), read_vector(data.get("p",[0,0,0])))

func grip_for(key: String, side: String, defaults: Array) -> Transform3D:
	var profile: Dictionary = grips.get(key,{})
	var points: Array = profile.get("points", defaults)
	for point in points:
		if point.get("hand","both") in ["both",side]: return read_pose(point)
	return Transform3D.IDENTITY

func profile_points(key: String, defaults: Array) -> Array:
	return grips.get(key,{}).get("points",defaults).duplicate(true)

func import_model(path: String) -> String:
	if path.get_extension().to_lower() not in ["glb","gltf"]:
		return "Choose a GLB or glTF model"
	if FileAccess.get_file_as_bytes(path).size() > 30*1024*1024:
		return "Model exceeds 30 MB; optimize it first"
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path,state) != OK: return "Could not read glTF and its dependencies"
	var scene := document.generate_scene(state)
	if scene == null: return "No usable scene in model"
	# Re-export a self-contained GLB so external buffers/textures need not remain beside it.
	var export_state := GLTFState.new()
	var hash_id := FileAccess.get_sha256(path).substr(0,16)
	var filename := hash_id + ".glb"
	var error := document.append_from_scene(scene,export_state)
	if error == OK: error = document.write_to_filesystem(export_state,"user://imports/"+filename)
	scene.free()
	if error != OK: return "Could not package imported model"
	imported[filename] = {"label":path.get_file().get_basename(),"size":0.6}
	save()
	changed.emit()
	return "Imported " + path.get_file()

func export_room(path: String) -> String:
	var zip := ZIPPacker.new()
	if zip.open(path) != OK: return "Cannot create room package"
	zip.start_file("home.json");zip.write_file(JSON.stringify(document()).to_utf8_buffer());zip.close_file()
	for file in imported:
		if not valid_asset_name(file): continue
		zip.start_file("assets/"+file)
		zip.write_file(FileAccess.get_file_as_bytes("user://imports/"+file));zip.close_file()
	zip.close()
	return "Room exported"

func import_room(path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return "Cannot read room package"
	var bytes := zip.read_file("home.json")
	if bytes.size() > 4*1024*1024: zip.close();return "Room manifest too large"
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or data.get("format","") != "framehome" or int(data.get("version",0)) != 1:
		zip.close();return "Unsupported room package"
	var imports = data.get("imported",{})
	if not imports is Dictionary or imports.size() > 32:
		zip.close();return "Too many imported models"
	var staged: Dictionary = {}
	var total := 0
	for file in imports:
		if not valid_asset_name(file) or not zip.file_exists("assets/"+file):
			zip.close();return "Invalid or missing model in room package"
		var model := zip.read_file("assets/"+file)
		total += model.size()
		if model.size() > 30*1024*1024 or total > 180*1024*1024:
			zip.close();return "Room models exceed size limits"
		staged[file] = model
	zip.close()
	checkpoint()
	for file in staged:
		var out := FileAccess.open("user://imports/"+file,FileAccess.WRITE)
		if out == null: return "Cannot write imported model"
		out.store_buffer(staged[file]);out.close()
	apply_document(data);save()
	return "Room imported"

func valid_asset_name(file: String) -> bool:
	return file == file.get_file() and file.ends_with(".glb") and not ".." in file and not ":" in file
