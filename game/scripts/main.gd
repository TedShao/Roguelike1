extends Node2D

@export var encounter_scenes: Array[PackedScene] = []
@export var skill_catalog: Array[SkillSpec] = []
@export_range(0.0, 1.0, 0.01) var move_seconds: float = 0.14
@export_range(0.0, 1.0, 0.01) var hit_seconds: float = 0.10

var room: FixedRoom
var model: BattleModel
var room_index: int = 0
var busy: bool = false
var selected: String = "move"
var armed: bool = false
var hover_point: Vector2 = Vector2(-9999, -9999)
var pending: Dictionary = {}
var shadow_target: Vector2i = Vector2i(-999, -999)
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
	%Next.pressed.connect(advance_room)
	%Restart.pressed.connect(restart_run)
	%Loadout.pressed.connect(show_loadout)
	%ApplyLoadout.pressed.connect(apply_loadout)
	%LowerPressure.pressed.connect(lower_pressure)
	for choice in %Choices.get_children():
		for spec in skill_catalog:
			if spec.skill_id == String(choice.name):
				choice.text = spec.display_name
				choice.tooltip_text = spec.description
		choice.toggled.connect(func(_value): update_picker())
	bind_room()
	show_loadout()

func bind_room(carry: Dictionary = {}) -> void:
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
	selected = "move"
	armed = false
	pending.clear()
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
	%Turn.text = "行动 %02d   ·   屏障 %d   ·   敌人 %d" % [model.turn, model.shield, model.living_count()]
	if model.active_left > 0:
		%Overdrive.text = "透支生效 %d 回合  ·  双倍输出 / 承伤" % model.active_left
	elif model.overdrive_cd > 0:
		%Overdrive.text = "透支冷却  %d 回合" % model.overdrive_cd
	else:
		%Overdrive.text = "✓ 下次行动开启透支" if armed else "R  透支 · 持续 %d / 随后冷却 %d" % [model.rules.overdrive_duration, model.rules.overdrive_cooldown]
	%Overdrive.disabled = busy or model.outcome != "playing" or model.active_left > 0 or model.overdrive_cd > 0
	for index in range(2):
		var button: Button = %Slot1 if index == 0 else %Slot2
		var spec: SkillSpec = model.skills[loadout[index]]
		var cd: int = model.cooldowns.get(spec.skill_id, 0)
		button.text = "%d  %s%s" % [index + 1, spec.display_name, " · 冷却 %d" % cd if cd > 0 else ""]
		button.tooltip_text = spec.description
		button.disabled = busy or model.outcome != "playing" or cd > 0
	for button in [%Move, %Attack, %Wait, %Steady]:
		button.disabled = busy or model.outcome != "playing"
	%Restart.disabled = busy
	%Next.visible = model.outcome == "cleared"
	%Next.disabled = busy or room_index + 1 >= encounter_scenes.size()
	%Next.text = "三房战斗样片完成" if room_index + 1 >= encounter_scenes.size() else "前往下一间固定房"
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
	room.refresh_overlays(model.danger())
	if model.outcome == "dead":
		%Hint.text = "本轮结束。查看右侧行动记录，重新开始可再次选择两项基础技能。"
	elif model.outcome == "cleared":
		%Hint.text = "清场完成。可免费重配与降压；透支持续／冷却保留到下一房。"
	elif pending.is_empty():
		%Hint.text = "选择行动，再点目标预览；再次点击同一目标执行。WASD / 方向键直接走一步。"

	if not busy:
		update_hover(hover_point)

func choose(kind: String) -> void:
	if busy or model == null or model.outcome != "playing":
		return
	selected = kind
	pending.clear()
	shadow_target = Vector2i(-999, -999)
	room.refresh_overlays(model.danger())
	var explanation: String = "相邻单体物理 %d。" % model.rules.basic_damage if kind == "basic" else "选择相邻空格。"
	if model.skills.has(kind):
		explanation = model.skills[kind].description
	%Hint.text = explanation + "\n点击目标预览，再次点击执行；Esc 取消。"
	if kind == "S06" or kind == "S15":
		# Defensive skills are intentional button actions; no meaningless target click.
		submit({"kind": kind})

func toggle_overdrive() -> void:
	if busy or model == null or model.outcome != "playing" or model.active_left > 0 or model.overdrive_cd > 0:
		return
	armed = not armed
	pending.clear()
	refresh()
	%Hint.text = "下一次有效行动开启透支；取消瞄准不支付压力。" if armed else "已取消尚未开启的透支。"

func submit(action: Dictionary) -> void:
	if busy or model == null or %LoadoutPanel.visible:
		return
	action["overdrive"] = armed
	var preview: Dictionary = model.preview(action)
	if not preview.valid:
		%Hint.text = preview.reason
		return
	busy = true
	var result: Dictionary = model.execute(action)
	armed = false
	pending.clear()
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

func _unhandled_input(event: InputEvent) -> void:
	if model == null or busy or %LoadoutPanel.visible:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if event.is_action_pressed("ui_cancel"):
			pending.clear()
			armed = false
			shadow_target = Vector2i(-999, -999)
			refresh()
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
			pending.clear()
			shadow_target = Vector2i(-999, -999)
			refresh()
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
		%Inspect.text = "%s · %d/%d\n%s" % [enemy.spec.display_name, enemy.hp, enemy.spec.max_health, enemy.spec.description]
	else:
		%Inspect.text = "查看敌人\n悬停角色可读行为；红色叉格为已锁定的危险区域。"

func board_click(point: Vector2) -> void:
	var gate: FixedInteractable = room.get_node("Props/ExitGate")
	if gate.interaction_id == "exit" and gate.contains_world_point(point):
		if model.outcome == "cleared":
			advance_room()
		else:
			%Hint.text = "先清除本房敌人，出口才可使用。"
		return
	if model.outcome != "playing":
		return
	var cell: Vector2i = room.world_to_cell(point)
	var action: Dictionary = {"kind": selected, "target": cell, "overdrive": armed}
	if selected == "S17" and shadow_target != Vector2i(-999, -999):
		action.target = shadow_target
		action.landing = cell
	elif selected not in ["move", "S05", "S09"]:
		var index: int = picked_enemy(point)
		if index < 0:
			%Hint.text = "请选择敌人的交互范围；尚未消耗行动。"
			return
		action.target = model.enemies[index].cell
		if selected == "S17":
			shadow_target = action.target
			%Hint.text = "已选影袭目标，再选择其四邻空格作为落点。"
			return
	var preview: Dictionary = model.preview(action)
	if not preview.valid:
		%Hint.text = preview.reason
		return
	if action == pending:
		submit(action)
		return
	pending = action
	var markers: Array = preview.targets.duplicate()
	for step in preview.path:
		if step not in markers:
			markers.append(step)
	room.refresh_overlays(model.danger(), markers)
	%Hint.text = "预览：直接伤害 %d · 行动后压力 %d%s\n再次点击同一位置执行；右键 / Esc 取消。" % [preview.damage, preview.pressure, " · 将超载损失 %d 生命" % model.rules.overload_damage if preview.overload else ""]

func append_log(line: String) -> void:
	log_lines.append(line)
	while log_lines.size() > 45:
		log_lines.remove_at(0)
	%CombatLog.text = "\n".join(log_lines)

func show_loadout() -> void:
	if busy or model == null:
		return
	if model.turn > 0 and model.outcome != "cleared":
		return
	for choice in %Choices.get_children():
		choice.set_pressed_no_signal(String(choice.name) in loadout)
	%LoadoutPanel.show()
	update_picker()

func update_picker() -> void:
	var count: int = 0
	for choice in %Choices.get_children():
		if choice.button_pressed:
			count += 1
	%PickerHint.text = "选择两项基础技能  %d / 2。其余成长与符文系统在下一阶段接入。" % count
	%ApplyLoadout.disabled = count != 2

func apply_loadout() -> void:
	var chosen: Array[String] = []
	for choice in %Choices.get_children():
		if choice.button_pressed:
			chosen.append(String(choice.name))
	if chosen.size() != 2:
		return
	loadout = chosen
	model.equipped = loadout.duplicate()
	model.cooldowns.clear()
	for id in loadout:
		model.cooldowns[id] = 0
	%LoadoutPanel.hide()
	selected = "move"
	refresh()

func lower_pressure() -> void:
	if not busy and model.outcome == "cleared":
		model.pressure = clampi(int(%PressureValue.value), 0, model.pressure)
		refresh()

func advance_room() -> void:
	if busy or model == null or model.outcome != "cleared" or room_index + 1 >= encounter_scenes.size():
		return
	var carry: Dictionary = {"health": model.health, "pressure": model.pressure, "active": model.active_left, "cooldown": model.overdrive_cd, "turn": model.turn}
	room_index += 1
	replace_room(encounter_scenes[room_index])
	bind_room(carry)

func restart_run() -> void:
	if busy:
		return
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
