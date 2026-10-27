extends Node2D

@export var encounter_scenes: Array[PackedScene] = []
@export var skill_catalog: Array[SkillSpec] = []
@export_range(0.0, 1.0, 0.01) var move_seconds: float = 0.14
@export_range(0.0, 1.0, 0.01) var hit_seconds: float = 0.10
@export_range(0.1, 2.0, 0.05) var autocast_delay_seconds: float = 0.4

var room: FixedRoom
var model: BattleModel
var room_index: int = 0
var busy: bool = false
var selected: String = "smart"
var armed: bool = false
var hover_point: Vector2 = Vector2(-9999, -9999)
var shadow_target: Vector2i = Vector2i(-999, -999)
var auto_skills: Array[String] = []
var auto_queued: bool = false
var auto_epoch: int = 0
var loadout: Array[String] = ["S02", "S04"]
var log_lines: PackedStringArray = []

func _ready() -> void:
	room = $RoomHost.get_child(0) as FixedRoom
	for index in range(encounter_scenes.size()):
		if encounter_scenes[index].resource_path == room.scene_file_path:
			room_index = index
	%Attack.pressed.connect(func(): choose("basic"))
	%Move.pressed.connect(func(): choose("move"))
	%Wait.pressed.connect(func(): submit({"kind": "wait"}))
	%Steady.pressed.connect(func(): submit({"kind": "steady"}))
	%Overdrive.pressed.connect(toggle_overdrive)
	%Slot1.pressed.connect(func(): choose(loadout[0]))
	%Slot2.pressed.connect(func(): choose(loadout[1]))
	%Slot1.gui_input.connect(slot_input.bind(0))
	%Slot2.gui_input.connect(slot_input.bind(1))
	%Next.pressed.connect(advance_room)
	%Restart.pressed.connect(request_restart)
	%RestartConfirm.confirmed.connect(restart_run)
	%RestartConfirm.canceled.connect(func(): refresh(); queue_autocast())
	%CancelLoadout.pressed.connect(cancel_loadout)
	%Loadout.pressed.connect(show_loadout)
	%ApplyLoadout.pressed.connect(apply_loadout)
	%LowerPressure.pressed.connect(lower_pressure)
	for choice in %Choices.get_children():
		choice.toggled.connect(func(_value): update_picker())
	%ApplyLoadout.focus_mode = Control.FOCUS_ALL
	bind_room()
	show_loadout()

func bind_room(carry: Dictionary = {}) -> void:
	room.invalidate_navigation_cache()
	var errors: PackedStringArray = room.validation_errors()
	if not errors.is_empty():
		busy = true
		%Hint.text = "场景配置错误：\n" + "\n".join(errors)
		push_error(%Hint.text)
		return
	model = BattleModel.new(room, skill_catalog, loadout)
	if not carry.is_empty():
		model.health = carry.health
		model.pressure = carry.pressure
		model.active_left = carry.active
		model.overdrive_cd = carry.cooldown
		model.turn = carry.turn
	selected = "smart"
	armed = false
	shadow_target = Vector2i(-999, -999)
	# Intentionally no position/scale/texture assignment on room, props, walls or spawns.
	%RoomTitle.text = "%s · %s" % [room.room_id, room.display_name]
	%RoomNote.text = room.encounter_note
	log_lines.clear()
	append_log("进入固定房间 %s。一次有效行动后，每个存活敌人响应一次。" % room.room_id)
	refresh()

func refresh() -> void:
	if model == null:
		return
	%Health.text = "生命  %02d / %02d" % [model.health, model.rules.player_health]
	%HealthBar.max_value = model.rules.player_health
	%HealthBar.value = model.health
	%Pressure.text = "压力  %d / %d" % [model.pressure, model.rules.overload_threshold]
	%PressureBar.max_value = model.rules.overload_threshold
	%PressureBar.value = model.pressure
	%Pressure.tooltip_text = "压力 ≥%d：行动开始 +%d；达到 %d：失去 %d 生命并回落至 %d。稳神消耗一次行动，降低 %d。" % [model.rules.pressure_warning, model.rules.pressure_growth, model.rules.overload_threshold, model.rules.overload_damage, model.rules.overload_reset, model.rules.steady_reduction]
	%PressureBar.tooltip_text = %Pressure.tooltip_text
	%Turn.text = "行动 %02d · 屏障 %d（%d响应）· 敌人 %d" % [model.turn, model.shield, model.shield_left, model.living_count()]
	if model.active_left > 0:
		%Overdrive.text = "透支生效 %d 回合\n双倍输出 / 双倍承伤" % model.active_left
	elif model.overdrive_cd > 0:
		%Overdrive.text = "透支冷却  %d 回合" % model.overdrive_cd
	else:
		%Overdrive.text = "✓ 下次行动开启透支\n双倍输出 / 双倍承伤" if armed else "R · 透支\n持续 %d 回合 / 随后冷却 %d" % [model.rules.overdrive_duration, model.rules.overdrive_cooldown]
	%Overdrive.disabled = busy or model.outcome != "playing" or model.active_left > 0 or model.overdrive_cd > 0
	for index in range(2):
		var button: Button = %Slot1 if index == 0 else %Slot2
		var spec: SkillSpec = model.skills[loadout[index]]
		var cd: int = model.cooldowns.get(spec.skill_id, 0)
		button.text = "%d · %s\n%s" % [index + 1, spec.display_name, "冷却 %d 回合" % cd if cd > 0 else "可用"]
		button.set_autocast(spec.skill_id in auto_skills)
		button.tooltip_text = spec.description + ("\n自动施放已开启；再次右键关闭。" if spec.skill_id in auto_skills else "\n右键开启自动施放；每次施放仍消耗回合。")
		button.icon = spec.icon
		button.disabled = busy or model.outcome != "playing" or cd > 0
	for button in [%Move, %Attack, %Wait, %Steady]:
		button.disabled = busy or model.outcome != "playing"
	%Restart.disabled = busy
	%Next.visible = model.outcome == "cleared"
	%Next.disabled = busy or room_index + 1 >= encounter_scenes.size()
	%Next.text = "本轮探索完成" if room_index + 1 >= encounter_scenes.size() else "前往下一地牢"
	%Loadout.visible = model.outcome == "cleared"
	%PressureEdit.visible = model.outcome == "cleared"
	%PressureValue.max_value = model.pressure
	%PressureValue.value = mini(int(%PressureValue.value), model.pressure)
	if not busy:
		room.get_node("PlayerSpawn/Player").set_vitals(model.health, "透支" if model.active_left > 0 else "")
		for enemy in model.enemies:
			var actor: BattleActor = enemy.node
			actor.visible = enemy.hp > 0
			var status: String = "蓄力" if enemy.state == "prepared" else ("恢复" if enemy.state == "recover" else "")
			actor.set_vitals(enemy.hp, status)
	update_action_buttons()
	if model.outcome == "dead":
		%Hint.text = "本轮结束。查看右侧行动记录，重新开始可再次选择两项基础技能。"
	elif model.outcome == "cleared":
		%Hint.text = "清场：可免费重配／降压。技能冷却已重置。\n跨房保留：透支剩 %d 回合，冷却 %d 回合。" % [model.active_left, model.overdrive_cd]
	else:
		%Hint.text = default_hint()

	if not busy and not modal_open():
		update_hover(hover_point)
	else:
		room.refresh_overlays([] if busy else model.danger())

func choose(kind: String) -> void:
	if not can_choose():
		return
	if model.skills.has(kind) and model.cooldowns.get(kind, 0) > 0:
		%Hint.text = "这项技能还需 %d 次行动；悬停其它目标或选择其它行动。" % model.cooldowns[kind]
		return
	auto_epoch += 1
	selected = kind
	shadow_target = Vector2i(-999, -999)
	if kind in ["S06", "S15"]:
		# Self skills keep the existing one-button action rule.
		submit({"kind": kind})
	else:
		refresh()

func toggle_overdrive() -> void:
	if not can_choose() or model.active_left > 0 or model.overdrive_cd > 0:
		return
	auto_epoch += 1
	armed = not armed
	refresh()
	queue_autocast()

func submit(action: Dictionary) -> void:
	if busy or model == null or modal_open():
		return
	action["overdrive"] = armed
	var preview: Dictionary = model.preview(action)
	if not preview.valid:
		%Hint.text = preview.reason
		return
	auto_epoch += 1
	busy = true
	append_log("—— 行动 %d ——" % (model.turn + 1))
	var result: Dictionary = model.execute(action)
	armed = false
	selected = "smart"
	shadow_target = Vector2i(-999, -999)
	refresh()
	if action.kind == "basic" or String(action.kind).begins_with("S"):
		room.get_node("PlayerSpawn/Player").play_attack()
	for event in result.events:
		var actor: BattleActor = room.get_node("PlayerSpawn/Player") if event.id == -1 else model.enemies[event.id].node
		if event.type == "move":
			var target_position: Vector2 = room.to_global(room.cell_to_local(event.cell))
			if move_seconds > 0:
				var tween: Tween = create_tween()
				tween.tween_property(actor, "global_position", target_position, move_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				await tween.finished
			else:
				actor.global_position = target_position
		else:
			actor.play_hit()
			if hit_seconds > 0:
				await get_tree().create_timer(hit_seconds).timeout
	for line in result.messages:
		append_log(line)
	busy = false
	refresh()
	queue_autocast()

func _unhandled_input(event: InputEvent) -> void:
	if model == null or busy or modal_open():
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if event.is_action_pressed("ui_cancel"):
			cancel_action()
			return
		for entry in [["move_up", Vector2i.UP], ["move_right", Vector2i.RIGHT], ["move_down", Vector2i.DOWN], ["move_left", Vector2i.LEFT]]:
			if event.is_action_pressed(entry[0]):
				submit({"kind": "move", "target": model.player + entry[1]})
				return
		if event.is_action_pressed("wait_turn"):
			submit({"kind": "wait"})
		elif event.is_action_pressed("steady"):
			submit({"kind": "steady"})
		elif event.is_action_pressed("overdrive"):
			toggle_overdrive()
		elif event.is_action_pressed("slot_1"):
			choose(loadout[0])
		elif event.is_action_pressed("slot_2"):
			choose(loadout[1])
	if event is InputEventMouseMotion:
		update_hover(get_canvas_transform().affine_inverse() * event.position)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_action()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			board_click(get_canvas_transform().affine_inverse() * event.position)

func picked_enemy(point: Vector2) -> int:
	for enemy in model.enemies:
		if enemy.hp > 0 and enemy.node.contains_world_point(point):
			return enemy.id
	return -1

func update_hover(point: Vector2) -> void:
	hover_point = point
	room.hover_cell = room.world_to_cell(point)
	room.queue_redraw()
	var gate: FixedInteractable = room.get_node("Props/ExitGate")
	gate.set_hovered(gate.contains_world_point(point))
	var index: int = picked_enemy(point)
	if index >= 0:
		var enemy: Dictionary = model.enemies[index]
		%Inspect.text = "%s · %d/%d\n%s" % [enemy.spec.display_name, enemy.hp, enemy.spec.max_health, model.intent_text(index)]
	else:
		var threats := PackedStringArray()
		for enemy in model.enemies:
			if enemy.hp > 0 and room.hover_cell in enemy.locked:
				threats.append("%s：%s" % [enemy.spec.display_name, model.intent_text(enemy.id)])
		%Inspect.text = "\n".join(threats) if not threats.is_empty() else "叉格＝敌方锁地攻击，下一次响应执行。\n圆点＝可选位置；方框＝技能区域；箭线＝位移路径。"
	if not can_choose():
		room.refresh_overlays(model.danger())
		return
	var candidates: Array = selection_cells()
	room.refresh_overlays(model.danger(), [], candidates)
	%Hint.text = default_hint()
	if gate.contains_world_point(point):
		%Hint.text = "出口尚未开放：先清除本房敌人。"
		return
	if not room.inside_bounds(room.hover_cell):
		return
	if selected == "S17" and shadow_target == Vector2i(-999, -999):
		if index >= 0:
			var landings: Array = model.shadow_landings(model.enemies[index].cell)
			%Hint.text = "影袭：单击选定敌人，再单击圆点落地施放。" if not landings.is_empty() else "影袭：该目标没有合法落点或不在射程内。"
		return
	var action: Dictionary = action_at(point)
	var preview: Dictionary = model.preview(action)
	if not preview.valid:
		%Hint.text = preview.reason + "（未消耗行动）\n" + default_hint()
		return
	room.refresh_overlays(model.danger(), preview.targets, candidates, preview.path, preview.push_path)
	%Hint.text = preview_text(action, preview)

func board_click(point: Vector2) -> void:
	if busy or modal_open() or model == null:
		return
	var gate: FixedInteractable = room.get_node("Props/ExitGate")
	if model.outcome == "cleared" and gate.interaction_id == "exit" and gate.contains_world_point(point):
		advance_room()
		return
	if model.outcome != "playing":
		return
	var cell: Vector2i = room.world_to_cell(point)
	if not room.inside_bounds(cell):
		return
	if selected == "S17" and shadow_target == Vector2i(-999, -999):
		var index: int = picked_enemy(point)
		if index < 0 or model.shadow_landings(model.enemies[index].cell).is_empty():
			%Hint.text = "影袭：先选射程内有合法落点的敌人；右键取消。"
			return
		shadow_target = model.enemies[index].cell
		update_hover(point)
		return
	# Hover is the preview. A single click is the commitment, with no hidden first-click state.
	submit(action_at(point))

func modal_open() -> bool:
	return %LoadoutPanel.visible or %RestartConfirm.visible

func can_choose() -> bool:
	return model != null and not busy and not modal_open() and model.outcome == "playing"

func cancel_action() -> void:
	auto_epoch += 1
	selected = "smart"
	armed = false
	shadow_target = Vector2i(-999, -999)
	refresh()
	queue_autocast()

func action_at(point: Vector2) -> Dictionary:
	var cell: Vector2i = room.world_to_cell(point)
	var index: int = picked_enemy(point)
	var kind: String = selected
	if kind == "smart":
		kind = "basic" if index >= 0 else "move"
	if kind not in ["move", "S05", "S09"] and index >= 0:
		cell = model.enemies[index].cell
	var action: Dictionary = {"kind": kind, "target": cell, "overdrive": armed}
	if kind == "S17" and shadow_target != Vector2i(-999, -999):
		action.target = shadow_target
		action.landing = room.world_to_cell(point)
	return action

func selection_cells() -> Array:
	var cells: Array = []
	if selected == "smart":
		return cells
	if selected == "S17":
		if shadow_target != Vector2i(-999, -999):
			return model.shadow_landings(shadow_target)
		for enemy in model.enemies:
			if enemy.hp > 0 and not model.shadow_landings(enemy.cell).is_empty():
				cells.append(enemy.cell)
		return cells
	# Use actual legality, including walls, range, occupancy and cooldown.
	var reach: int = model.skills[selected].reach if model.skills.has(selected) else 1
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var cell: Vector2i = model.player + Vector2i(x, y)
			if model.preview({"kind": selected, "target": cell, "overdrive": armed}).valid:
				cells.append(cell)
	return cells

func default_hint() -> String:
	var text: String = "左键：相邻敌人普攻／空格走一步。1 / 2 选技能，再点目标施放。"
	if selected != "smart":
		var title: String = model.skills[selected].display_name if model.skills.has(selected) else ("普攻" if selected == "basic" else "移动")
		text = "%s：悬停看效果，左键直接执行；右键取消。" % title
	if shadow_target != Vector2i(-999, -999):
		text = "影袭目标已选：单击圆点落地施放；右键重新选择。"
	if armed:
		text += "\n已预约透支：下一行动输出／承伤 ×2，压力 +%d。" % model.rules.overdrive_pressure
	return text

func update_action_buttons() -> void:
	for pair in [[%Move, "move"], [%Attack, "basic"], [%Slot1, loadout[0]], [%Slot2, loadout[1]]]:
		pair[0].set_pressed_no_signal(selected == pair[1])
	var title: String = "智能左键" if selected == "smart" else (model.skills[selected].display_name if model.skills.has(selected) else ("普攻" if selected == "basic" else "移动"))
	%Subtitle.text = "当前：%s · 悬停预览 / 单击执行" % title

func preview_text(action: Dictionary, preview: Dictionary) -> String:
	var parts := PackedStringArray()
	var kind: String = action.kind
	if preview.damage > 0:
		parts.append("命中 %d 人 · 每人 %d 伤害" % [preview.hits, preview.damage])
		if preview.hits == 0:
			parts.append("空挥仍消耗行动和冷却")
	if not preview.path.is_empty() and preview.path.back() != model.player:
		parts.append("移动 %d 格" % (preview.path.size() - 1))
	if kind == "S02" and preview.hits > 0:
		parts.append("推移 %d 格 · 碰撞 %d" % [preview.push_path.size(), preview.collision])
		if preview.interrupt: parts.append("打断蓄力")
	if model.skills.has(kind):
		parts.append("随后冷却 %d 次行动" % model.skills[kind].cooldown)
	if model.active_left > 0 or armed:
		parts.append("本回合输出／承伤 ×2")
	if preview.overload:
		parts.append("响应前超载：生命 −%d，压力→%d" % [model.rules.overload_damage, model.rules.overload_reset])
	else:
		parts.append("响应前压力 %d" % preview.pressure)
	parts.append("单击执行；敌人随后响应")
	return " · ".join(parts)

func request_restart() -> void:
	if busy or modal_open():
		return
	auto_epoch += 1
	%RestartConfirm.popup_centered()
	room.refresh_overlays(model.danger())

func cancel_loadout() -> void:
	if model.outcome != "cleared":
		return
	%LoadoutPanel.hide()
	%LoadoutShade.hide()
	refresh()

func append_log(line: String) -> void:
	line = line.replace("basic →", "普攻 →")
	for spec in skill_catalog:
		line = line.replace(spec.skill_id + " →", spec.display_name + " →")
	log_lines.append(line)
	while log_lines.size() > 45:
		log_lines.remove_at(0)
	%CombatLog.text = "\n".join(log_lines)

func show_loadout() -> void:
	if busy or model == null or %RestartConfirm.visible:
		return
	if model.turn > 0 and model.outcome != "cleared":
		return
	for choice in %Choices.get_children():
		choice.set_pressed_no_signal(String(choice.name) in loadout)
		choice.update_selection()
	cancel_action()
	%CancelLoadout.visible = model.outcome == "cleared"
	%ApplyLoadout.text = "应用这两项能力" if model.outcome == "cleared" else "带上这两项能力，进入地窟"
	%LoadoutPanel.show()
	%LoadoutShade.show()
	update_picker()
	%Choices.get_child(0).grab_focus()
	room.refresh_overlays(model.danger())

func update_picker() -> void:
	var count: int = 0
	for choice in %Choices.get_children():
		if choice.button_pressed:
			count += 1
	%PickerHint.text = "已选择 %d / 2   ·   点击卡片选择，再次点击取消   ·   清场后可免费重配" % count
	%ApplyLoadout.disabled = count != 2

func apply_loadout() -> void:
	if not %LoadoutPanel.visible or (model.turn > 0 and model.outcome != "cleared"):
		return
	var chosen: Array[String] = []
	for choice in %Choices.get_children():
		if choice.button_pressed:
			chosen.append(String(choice.name))
	if chosen.size() != 2:
		return
	loadout = chosen
	auto_skills.assign(auto_skills.filter(func(id): return id in loadout))
	model.equipped = loadout.duplicate()
	model.cooldowns.clear()
	for id in loadout:
		model.cooldowns[id] = 0
	%LoadoutPanel.hide()
	%LoadoutShade.hide()
	selected = "smart"
	refresh()
	queue_autocast()

func lower_pressure() -> void:
	if not busy and model.outcome == "cleared":
		model.pressure = clampi(int(%PressureValue.value), 0, model.pressure)
		refresh()

func advance_room() -> void:
	if busy or model == null or modal_open() or model.outcome != "cleared" or room_index + 1 >= encounter_scenes.size():
		return
	var carry: Dictionary = {"health": model.health, "pressure": model.pressure, "active": model.active_left, "cooldown": model.overdrive_cd, "turn": model.turn}
	room_index += 1
	replace_room(encounter_scenes[room_index])
	bind_room(carry)
	queue_autocast()

func restart_run() -> void:
	if busy:
		return
	%RestartConfirm.hide()
	auto_epoch += 1
	auto_skills.clear()
	room_index = 0
	replace_room(encounter_scenes[0])
	bind_room()
	show_loadout()

func replace_room(scene: PackedScene) -> void:
	# Reinstantiate the saved scene, with its authored transforms and resources intact.
	$RoomHost.remove_child(room)
	room.queue_free()
	room = scene.instantiate() as FixedRoom
	$RoomHost.add_child(room)

func slot_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if busy and not (loadout[index] in auto_skills):
		return
	if modal_open(): return
	# Right-clicking an enabled slot can always stop subsequent actions, even during animation.
	var id: String = loadout[index]
	auto_epoch += 1
	if id in auto_skills:
		auto_skills.erase(id)
	else:
		auto_skills.append(id)
		selected = "smart"
		shadow_target = Vector2i(-999, -999)
	(%Slot1 if index == 0 else %Slot2).accept_event()
	refresh()
	queue_autocast()

func queue_autocast() -> void:
	if auto_queued or auto_skills.is_empty(): return
	auto_queued = true
	run_autocast.call_deferred()

func run_autocast() -> void:
	var epoch: int = auto_epoch
	await get_tree().create_timer(autocast_delay_seconds).timeout
	auto_queued = false
	if epoch != auto_epoch:
		queue_autocast()
		return
	if not can_choose() or selected != "smart" or armed: return
	for id in loadout:
		if id not in auto_skills: continue
		var action: Dictionary = AutocastPlanner.choose(model, id)
		if not action.is_empty():
			append_log("自动施放：%s" % model.skills[id].display_name)
			await submit(action)
			return
