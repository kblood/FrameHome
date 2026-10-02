# SPDX-License-Identifier: GPL-3.0-or-later
class_name RoomToys
extends Node3D

var home: Node
var arrows: Array[Dictionary] = []
var paintballs: Array[Dictionary] = []
var marks: Array[Node3D] = []
var balloons: Array[Dictionary] = []
var inflating: Dictionary = {}
var drawn: Node3D
var drawing_bow: HomeProp
var draw_owner: HomeHand
var draw_armed := false
var previous_trigger := false
var draw_amount := 0.0
var bow_strings: Dictionary = {}
var random_color := 0
var serial := 0

func _ready() -> void:
	random_color=randi_range(0,7)

func model(path: String) -> Node3D:
	var item := AssetLibrary.load_model(path)
	if item==null: item=Node3D.new()
	add_child(item);return item

func _physics_process(dt: float) -> void:
	if not home.input_focused: cancel_draw();return
	update_bow(dt);update_arrows(dt);update_paint(dt);update_balloons(dt)

func cycle_color(kind: String) -> void:
	var key := "paint_color" if kind=="paintball_gun" else "balloon_color"
	HomeData.settings[key]=(int(HomeData.settings[key])+1)%8
	if kind=="balloon_inflator": HomeData.settings.balloon_random=false
	HomeData.save();home.ui.notice(AssetLibrary.COLOR_NAMES[int(HomeData.settings[key])])

func cast(a: Vector3,b: Vector3,ignore: Array[RID]=[],include_balloons := true) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(a,b,3 | (8 if include_balloons else 0),ignore)
	ray.collide_with_areas=include_balloons;ray.hit_from_inside=true
	return get_world_3d().direct_space_state.intersect_ray(ray)

func fire_paint(tool: HomeProp) -> void:
	var color := int(HomeData.settings.paint_color)
	var p := tool.to_global(Vector3(0,.035,.215))
	var blocked := cast(tool.global_position,p,[tool.get_rid()])
	if not blocked.is_empty(): paint_hit(blocked,color);return
	var shot := model("res://assets/toys/paintball_"+AssetLibrary.COLOR_IDS[color]+".glb")
	shot.global_position=p
	paintballs.append({"node":shot,"v":tool.global_basis.z*14,"age":0.0,"color":color,"ignore":tool.get_rid()})
	while paintballs.size()>32: paintballs.pop_front().node.queue_free()

func paint_hit(hit: Dictionary,color: int) -> void:
	if hit.collider is Area3D and hit.collider.has_meta("balloon"):
		pop_balloon(hit.collider);return
	var mark := model("res://assets/toys/splat_"+AssetLibrary.COLOR_IDS[color]+".glb")
	var normal: Vector3=hit.normal
	if normal.length_squared()<.5: normal=Vector3.UP
	mark.global_position=hit.position+normal*(.0015+(serial%128)*.000005);serial+=1
	mark.look_at(mark.global_position+normal,Vector3.RIGHT if absf(normal.y)>.99 else Vector3.UP,true)
	mark.scale=Vector3(.065,.065,1)
	if is_instance_valid(hit.collider): mark.reparent(hit.collider,true)
	marks.append(mark)
	while marks.size()>96:
		var old: Node3D=marks.pop_front()
		if is_instance_valid(old): old.queue_free()

func update_paint(dt: float) -> void:
	for shot in paintballs.duplicate():
		shot.age+=dt
		var start: Vector3=shot.node.global_position
		var end: Vector3=start+shot.v*dt+Vector3.DOWN*4.905*dt*dt
		shot.v+=Vector3.DOWN*9.81*dt
		var ignore: Array[RID]=[shot.ignore]
		var hit := cast(start,end,ignore)
		if not hit.is_empty(): paint_hit(hit,shot.color);shot.node.queue_free();paintballs.erase(shot)
		elif shot.age>4: shot.node.queue_free();paintballs.erase(shot)
		else: shot.node.global_position=end

func inflate(tool: HomeProp,pressed: bool,dt: float) -> void:
	if not pressed:
		if not inflating.is_empty(): release_balloon(tool.global_basis.z)
		return
	var radius := minf(float(inflating.get("radius",.035))+dt*.11,.22)
	var nozzle := tool.to_global(Vector3(0,.055,.215))
	var p := nozzle+tool.global_basis.z*(radius+.025)
	var shape := SphereShape3D.new();shape.radius=radius*1.2
	var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform.origin=p
	query.collision_mask=3;query.exclude=[tool.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		home.ui.notice("Move the inflator into open space");return
	if inflating.is_empty():
		var color := random_color if HomeData.settings.balloon_random else int(HomeData.settings.balloon_color)
		var body := Area3D.new();body.collision_layer=8;body.collision_mask=0;body.set_meta("balloon",true);add_child(body)
		var visual := model("res://assets/toys/balloon_"+AssetLibrary.COLOR_IDS[color]+".glb");visual.reparent(body,false)
		var collision := CollisionShape3D.new();collision.shape=SphereShape3D.new();body.add_child(collision)
		inflating={"node":body,"visual":visual,"shape":collision,"radius":radius,"v":Vector3.ZERO,"age":0.0}
	inflating.radius=radius;inflating.node.global_position=p;inflating.visual.scale=Vector3.ONE*(radius/.14)
	inflating.shape.shape.radius=radius
	if radius>=.22: release_balloon(tool.global_basis.z)

func release_balloon(direction: Vector3) -> void:
	if inflating.is_empty(): return
	inflating.v=direction*.45+Vector3.UP*.18;balloons.append(inflating);inflating={};random_color=randi_range(0,7)
	while balloons.size()>24: balloons.pop_front().node.queue_free()

func update_balloons(dt: float) -> void:
	for balloon in balloons.duplicate():
		if not is_instance_valid(balloon.node): balloons.erase(balloon);continue
		balloon.age+=dt
		if balloon.age>90 or balloon.node.global_position.y>6:
			balloon.node.queue_free();balloons.erase(balloon);continue
		balloon.v=(balloon.v+Vector3.UP*.24*dt)*exp(-.5*dt)
		var shape := SphereShape3D.new();shape.radius=balloon.radius*1.2
		var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform.origin=balloon.node.global_position
		query.motion=balloon.v*dt;query.collision_mask=3
		var motion := get_world_3d().direct_space_state.cast_motion(query)
		balloon.node.global_position+=query.motion*motion[0]
		if motion[0]<1:
			var hit := cast(balloon.node.global_position,balloon.node.global_position+balloon.v.normalized()*shape.radius,[],false)
			var normal: Vector3=hit.get("normal",-balloon.v.normalized())
			balloon.v=balloon.v.bounce(normal)*.4

func pop_balloon(node: Area3D) -> void:
	for balloon in balloons.duplicate():
		if balloon.node==node: balloons.erase(balloon)
	if inflating.get("node")==node: inflating={}
	node.queue_free();home.ui.notice("Pop!")

func update_bow(_dt: float) -> void:
	var held_bow: HomeProp
	var owner: HomeHand
	for hand in [home.left_hand,home.right_hand]:
		if hand.held is HomeProp and hand.held.model_id=="bow" and hand.attached:
			held_bow=hand.held;owner=hand;break
	if draw_owner!=owner:
		cancel_draw();draw_armed=false;previous_trigger=false;draw_owner=owner
	for prop in home.props:
		if prop.model_id=="bow" and is_instance_valid(prop): update_string(prop,prop.to_global(Vector3(.106325,.049,0)))
	if not held_bow or not home.xr_active: return
	var other: HomeHand=home.right_hand if owner==home.left_hand else home.left_hand
	if not other.get_is_active() or other.held: cancel_draw();draw_armed=false;return
	var trigger := other.get_float("trigger")>.65
	if not trigger: draw_armed=true
	var rest := held_bow.to_global(Vector3(.106325,.049,0))
	if draw_armed and trigger and not previous_trigger and other.global_position.distance_to(rest)<.18:
		drawing_bow=held_bow;drawn=model("res://assets/furniture/arrow.glb")
	if is_instance_valid(drawn):
		var local := held_bow.to_local(other.global_position)
		if local.x<.066 or local.x>.91 or absf(local.y-.049)>.3 or absf(local.z)>.3:
			cancel_draw();draw_armed=false
		else:
			draw_amount=clampf(local.x-.106325,0,.65)
			var center := held_bow.to_global(Vector3(.106325+draw_amount,local.y,local.z))
			var direction := (held_bow.to_global(Vector3(-.077225,.049,0))-center).normalized()
			drawn.global_position=center;drawn.look_at(center+direction,Vector3.UP,true)
			update_string(held_bow,center)
			if not trigger and previous_trigger:
				if draw_amount>.06:
					var arrow := {"node":drawn,"v":direction*(5+18*draw_amount/.65),"age":0.0,"stuck":false,"ignore":held_bow.get_rid()}
					arrows.append(arrow);drawn=null
					var hit := cast(center,center+direction*.72,[held_bow.get_rid()])
					if not hit.is_empty(): arrow_hit(arrow,hit,direction)
					while arrows.size()>16:
						var old: Dictionary=arrows.pop_front()
						if is_instance_valid(old.node): old.node.queue_free()
				else: cancel_draw()
	previous_trigger=trigger

func update_string(bow: HomeProp, center: Vector3) -> void:
	var id := bow.get_instance_id()
	if not bow_strings.has(id):
		var lines: Array[MeshInstance3D]=[]
		for i in range(2):
			var line := AssetLibrary.box_mesh(Vector3(.002,.002,1),Color("c4baa1"));bow.add_child(line);lines.append(line)
		bow_strings[id]=lines
	var lines: Array=bow_strings[id]
	for i in range(2):
		if not is_instance_valid(lines[i]): return
		var a := bow.to_global(Vector3(.106325,.573 if i==0 else -.573,0))
		var line: MeshInstance3D=lines[i];line.global_position=(a+center)/2
		line.look_at(center,Vector3.RIGHT);line.scale=Vector3(1,1,a.distance_to(center))

func update_arrows(dt: float) -> void:
	for arrow in arrows.duplicate():
		if not is_instance_valid(arrow.node): arrows.erase(arrow);continue
		if arrow.stuck: continue
		arrow.age+=dt
		if arrow.age>12: arrow.node.queue_free();arrows.erase(arrow);continue
		var node: Node3D=arrow.node;var a := node.global_position+node.global_basis.z*.72
		var p: Vector3=node.global_position+arrow.v*dt+Vector3.DOWN*4.905*dt*dt
		arrow.v+=Vector3.DOWN*9.81*dt;var direction: Vector3=arrow.v.normalized()
		var b := p+direction*.72
		var hit := cast(a,b,[arrow.ignore])
		if not hit.is_empty() and hit.collider is Area3D and hit.collider.has_meta("balloon"):
			pop_balloon(hit.collider)
			hit=cast(a,b,[arrow.ignore],false)
		if not hit.is_empty(): arrow_hit(arrow,hit,direction)
		if not arrow.stuck: node.global_position=p;node.look_at(p+direction,Vector3.UP,true)

func arrow_hit(arrow: Dictionary, hit: Dictionary, direction: Vector3) -> void:
	if hit.collider is Area3D and hit.collider.has_meta("balloon"):
		pop_balloon(hit.collider);return
	var node: Node3D=arrow.node
	node.global_position=hit.position-direction*.705;node.look_at(node.global_position+direction,Vector3.UP,true)
	arrow.stuck=true;node.reparent(hit.collider,true)
	home.ui.notice("Arrow stuck · clear it from Toys")

func cancel_draw() -> void:
	if is_instance_valid(drawn): drawn.queue_free()
	drawn=null;drawing_bow=null;draw_amount=0

func clear_kind(kind: String) -> void:
	if kind=="arrows":
		for arrow in arrows:
			if is_instance_valid(arrow.node): arrow.node.queue_free()
		arrows.clear()
	elif kind=="paint":
		for shot in paintballs:
			if is_instance_valid(shot.node): shot.node.queue_free()
		paintballs.clear()
		for mark in marks:
			if is_instance_valid(mark): mark.queue_free()
		marks.clear()
	elif kind=="balloons":
		for balloon in balloons:
			if is_instance_valid(balloon.node): balloon.node.queue_free()
		balloons.clear()
		if not inflating.is_empty(): inflating.node.queue_free();inflating={}

func clear_all() -> void:
	cancel_draw()
	for kind in ["arrows","paint","balloons"]: clear_kind(kind)
