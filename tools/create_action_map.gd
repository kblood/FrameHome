# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

func _initialize() -> void:
	var map := OpenXRActionMap.new()
	map.create_default_action_sets()
	# Explicit Frame bindings; retain default Touch/Index/Simple profiles for PC VR.
	var actions: Dictionary = {}
	for action_set in map.action_sets:
		for action in action_set.actions: actions[action.resource_name]=action
	var frame := OpenXRInteractionProfile.new()
	frame.interaction_profile_path="/interaction_profiles/valve/frame_controller_valve"
	var bindings: Array[OpenXRIPBinding] = []
	for side in ["left","right"]:
		var prefix: String = "/user/hand/"+side
		var paths := {"trigger":"/input/trigger/value","trigger_click":"/input/trigger/click",
			"grip":"/input/squeeze/value","grip_click":"/input/squeeze/click",
			"primary":"/input/thumbstick","primary_click":"/input/thumbstick/click",
			"grip_pose":"/input/grip/pose","aim_pose":"/input/aim/pose","haptic":"/output/haptic",
			"ax_button":"/input/a/click" if side=="right" else "/input/dpad_down/click",
			"by_button":"/input/b/click" if side=="right" else "/input/dpad_up/click"}
		for action_name in paths:
			if not actions.has(action_name): continue
			var binding := OpenXRIPBinding.new();binding.action=actions[action_name]
			binding.binding_path=prefix+paths[action_name];bindings.append(binding)
	frame.bindings=bindings
	map.add_interaction_profile(frame)
	var error := ResourceSaver.save(map,"res://openxr_action_map.tres")
	if error!=OK: push_error("Cannot write OpenXR action map")
	quit(error)
