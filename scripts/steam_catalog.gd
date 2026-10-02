# SPDX-License-Identifier: GPL-3.0-or-later
extends Node

signal catalog_changed
signal artwork_changed(app_id: String)
var apps: Array[Dictionary] = []
var roots: Array[String] = []
var status := "Finding installed Steam games…"
var artwork: Dictionary = {}
var artwork_queue: Array[String] = []
var artwork_failed: Dictionary = {}
var downloading := false
const HIDDEN_IDS := ["228980","250820","1070560","1391110","1628350"]

func _ready() -> void:
	call_deferred("refresh")

func refresh() -> void:
	roots.clear();apps.clear()
	var candidates: Array[String] = []
	var override := OS.get_environment("FRAMEHOME_STEAM_ROOT")
	if not override.is_empty(): candidates.append(override)
	if OS.get_name() == "Windows":
		candidates.append(OS.get_environment("PROGRAMFILES(X86)")+"/Steam")
		candidates.append("C:/Program Files (x86)/Steam")
	else:
		var base := OS.get_environment("HOME")
		candidates.append_array([base+"/.local/share/Steam",base+"/.steam/steam",base+"/.steam/root"])
	for candidate in candidates:
		if not DirAccess.dir_exists_absolute(candidate+"/steamapps"): continue
		if candidate in roots: continue
		roots.append(candidate)
		var folders := parse_vdf(FileAccess.get_file_as_string(candidate+"/steamapps/libraryfolders.vdf")) if FileAccess.file_exists(candidate+"/steamapps/libraryfolders.vdf") else {}
		for entry in folders.get("libraryfolders",{}).values():
			var path: String = entry.get("path","") if entry is Dictionary else str(entry)
			if DirAccess.dir_exists_absolute(path+"/steamapps") and path not in roots: roots.append(path)
	var seen: Dictionary = {}
	for root in roots:
		for file in DirAccess.get_files_at(root+"/steamapps"):
			if not file.begins_with("appmanifest_") or not file.ends_with(".acf"): continue
			var data: Dictionary = parse_vdf(FileAccess.get_file_as_string(root+"/steamapps/"+file)).get("AppState",{})
			var id := str(data.get("appid",""))
			if not id.is_valid_int() or id in seen: continue
			seen[id] = true
			var title := str(data.get("name","Steam app "+id))
			var system := id in HIDDEN_IDS or "steam linux runtime" in title.to_lower() or "redistributable" in title.to_lower()
			system=system or title.to_lower() in ["fex","lepton","lepton development","steamvr"] or title.to_lower().begins_with("proton")
			apps.append({"id":id,"name":title,"root":root,"system":system,"installed":true})
	apps.sort_custom(func(a,b): return a.name.naturalnocasecmp_to(b.name)<0)
	status = "%d installed Steam apps" % apps.size() if not roots.is_empty() else "Steam library not found · set FRAMEHOME_STEAM_ROOT"
	catalog_changed.emit()

func find_app(id: String) -> Dictionary:
	for app in apps:
		if app.id == id: return app
	return {"id":id,"name":"Unavailable Steam app "+id,"installed":false,"system":false}

func launch(id: String) -> Error:
	if not id.is_valid_int() or not find_app(id).get("installed",false): return ERR_DOES_NOT_EXIST
	# Numeric IDs only; never execute a command taken from an imported room/manifest.
	var result := OS.shell_open("steam://rungameid/"+id)
	if result == OK:
		HomeData.recent.erase(id);HomeData.recent.push_front(id)
		HomeData.recent.resize(mini(HomeData.recent.size(),8));HomeData.save()
	return result

func cover(id: String) -> Texture2D:
	if artwork.has(id): return artwork[id]
	var candidates: Array[String] = ["user://covers/"+id+".jpg"]
	for root in roots:
		var cache := root+"/appcache/librarycache"
		if DirAccess.dir_exists_absolute(cache):
			for file in DirAccess.get_files_at(cache):
				if file.begins_with(id+"_") and file.get_extension() in ["jpg","png"]: candidates.append(cache+"/"+file)
		if DirAccess.dir_exists_absolute(cache+"/"+id):
			for file in DirAccess.get_files_at(cache+"/"+id):
				if file.get_extension() in ["jpg","png"]: candidates.append(cache+"/"+id+"/"+file)
	var best: Image = null
	var area := 0
	for path in candidates:
		if not FileAccess.file_exists(path): continue
		if "logo" in path or "icon" in path: continue
		var image := Image.load_from_file(path)
		if image != null and image.get_width()*image.get_height()>area:
			area = image.get_width()*image.get_height();best=image
	if best != null:
		if best.get_width()>1024 or best.get_height()>1024:
			var ratio := 1024.0/maxi(best.get_width(),best.get_height())
			best.resize(roundi(best.get_width()*ratio),roundi(best.get_height()*ratio),Image.INTERPOLATE_LANCZOS)
		artwork[id] = ImageTexture.create_from_image(best)
		return artwork[id]
	if id.is_valid_int() and id not in artwork_queue and not artwork_failed.has(id):
		artwork_queue.append(id);call_deferred("download_next")
	return null

func download_next() -> void:
	if downloading or artwork_queue.is_empty(): return
	downloading = true
	var id: String = artwork_queue.pop_front()
	var request := HTTPRequest.new();add_child(request)
	request.timeout=10;request.body_size_limit=5*1024*1024
	# Steam's public artwork endpoint is best effort. Names remain readable if art is unavailable.
	var error := request.request("https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/"+id+"/library_600x900.jpg")
	if error == OK:
		var response: Array = await request.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200:
			var image := Image.new()
			if image.load_jpg_from_buffer(response[3]) == OK:
				var f := FileAccess.open("user://covers/"+id+".jpg",FileAccess.WRITE)
				if f: f.store_buffer(response[3]);f.close()
				artwork[id] = ImageTexture.create_from_image(image)
				artwork_changed.emit(id)
	artwork_failed[id]=true
	request.queue_free();downloading=false;call_deferred("download_next")

# Text KeyValues parser: quoted values, escaped characters, braces and // comments.
func parse_vdf(text: String) -> Dictionary:
	var tokens: Array[String] = []
	var i := 0
	while i < text.length():
		var c := text[i]
		if c in [" ","\t","\r","\n"]: i+=1;continue
		if c=="/" and i+1<text.length() and text[i+1]=="/":
			while i<text.length() and text[i]!="\n": i+=1
			continue
		if c in ["{","}"]: tokens.append(c);i+=1;continue
		var value := ""
		if c=='"':
			i+=1
			while i<text.length() and text[i]!='"':
				if text[i]=="\\" and i+1<text.length(): i+=1
				value+=text[i];i+=1
			i+=1
		else:
			while i<text.length() and text[i] not in [" ","\t","\r","\n","{","}"]:
				value+=text[i];i+=1
		tokens.append(value)
	var cursor := [0]
	return parse_object(tokens,cursor,0)

func parse_object(tokens: Array[String], cursor: Array, depth: int) -> Dictionary:
	var result: Dictionary = {}
	if depth>32: return result
	while cursor[0]<tokens.size():
		var key := tokens[cursor[0]];cursor[0]+=1
		if key=="}": break
		if cursor[0]>=tokens.size(): break
		var value := tokens[cursor[0]];cursor[0]+=1
		result[key] = parse_object(tokens,cursor,depth+1) if value=="{" else value
	return result
