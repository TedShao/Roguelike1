extends SceneTree
var game
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.position = point
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame

func key(code: Key, echo: bool = false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.echo = echo
	Input.parse_input_event(e)
	await process_frame
	e = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame

func hover(point: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = point
	Input.parse_input_event(e)
	await process_frame

func point(cell: Vector2i) -> Vector2:
	return game.room.to_global(game.room.cell_to_local(cell))

func slot(index: int) -> Vector2:
	return game.get_node("%%Slot%d" % index).get_global_rect().get_center()

func fixture(ids: Array[String] = ["S02", "S04"], letter: String = "a") -> void:
	game.auto_epoch += 1
	game.auto_skills.clear()
	game.get_node("%LoadoutPanel").hide()
	game.get_node("%LoadoutShade").hide()
	game.get_node("%RestartConfirm").hide()
	game.loadout = ids
	game.replace_room(load("res://game/scenes/rooms/room_%s.tscn" % letter))
	game.bind_room()
	game.move_seconds = 0
	game.hit_seconds = 0
	game.autocast_delay_seconds = 0.12
	await process_frame

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/" + name + ".png") == OK, name + " screenshot")

func run() -> void:
	game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await fixture()
	var before: int = game.model.enemies[1].hp
	await hover(point(Vector2i(3, 3)))
	check(game.model.turn == 0 and game.model.enemies[1].hp == before, "Hover preview never mutates battle")
	check("5 伤害" in game.get_node("%Hint").text, "Smart hover previews basic attack")
	await click(point(Vector2i(3, 3)))
	check(game.model.turn == 1 and game.model.enemies[1].hp == before - 5, "One left click executes basic attack")
	await fixture()
	await click(point(Vector2i(1, 3)))
	check(game.model.turn == 1 and game.model.player == Vector2i(1, 3), "One left click moves one cell")
	await click(point(Vector2i(5, 5)))
	check(game.model.turn == 1, "Distant click does not auto-walk or spend a turn")
	await fixture()
	await key(KEY_1)
	check(game.selected == "S02" and game.model.turn == 0, "Digit selects skill without a turn")
	await hover(point(Vector2i(3, 3)))
	check("碰撞 4" in game.get_node("%Hint").text, "Hover explains collision")
	await click(point(Vector2i(3, 3)))
	check(game.model.turn == 1 and game.model.enemies[1].hp == 0 and game.selected == "smart", "One target click casts and returns to smart control")
	await key(KEY_1)
	check(game.selected == "smart" and game.model.turn == 1, "Keyboard cannot select a cooling skill")
	await key(KEY_R)
	await key(KEY_2)
	await click(point(Vector2i(1, 3)), MOUSE_BUTTON_RIGHT)
	check(not game.armed and game.selected == "smart" and game.model.turn == 1, "Right cancel clears aim and pending overdrive without turn")
	await key(KEY_R)
	await key(KEY_ESCAPE)
	check(not game.armed and game.selected == "smart", "Escape matches right cancel")
	await fixture()
	await key(KEY_A, true)
	check(game.model.turn == 0, "Held-key repeat is ignored")
	await key(KEY_A)
	check(game.model.turn == 1, "Single keyboard input moves once")
	await fixture(["S17", "S04"])
	await key(KEY_1)
	var target := Vector2i(3, 3)
	var landings: Array = game.model.shadow_landings(target)
	check(not landings.is_empty(), "Shadow fixture offers landing")
	await click(point(target))
	check(game.model.turn == 0 and game.shadow_target == target, "Shadow enemy click selects only")
	check(game.room.candidate_cells == landings, "Shadow shows legal landing cells")
	await click(point(Vector2i(0, 0)))
	check(game.model.turn == 0 and game.shadow_target == target, "Invalid landing does not spend a turn")
	await click(point(landings[0]))
	check(game.model.turn == 1 and game.model.player == landings[0], "Second shadow click lands and attacks, no third confirmation")
	# Test-only boundary fixtures, not a balance or human enjoyment claim.
	await fixture()
	game.model.enemies[1].state = "prepared"
	var preview: Dictionary = game.model.preview({"kind":"S02", "target":Vector2i(3,3)})
	check(preview.collision == 4 and preview.push_path.size() == 1 and preview.interrupt, "Push preview follows displacement and interrupt")
	game.model.enemies[1].hp = 6
	preview = game.model.preview({"kind":"S02", "target":Vector2i(3,3)})
	check(preview.collision == 0 and preview.push_path.is_empty(), "Direct kill prevents push and collision in preview")
	game.model.pressure = 95
	preview = game.model.preview({"kind":"wait"})
	check(preview.overload and preview.pressure == 105 and game.model.pressure == 95, "Pressure preview is pre-response, read-only")
	# Right-click toggles the actual GUI button; there is no separate auto button.
	await fixture()
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	check("S02" in game.auto_skills and game.get_node("%Slot1").auto_enabled, "Right click enables automatic skill border")
	await create_timer(0.18).timeout
	check(game.model.turn == 1 and game.model.enemies[1].hp == 0 and game.model.cooldowns.S02 == 2, "Automatic cast consumes full turn and starts cooldown")
	check(game.model.enemies[0].cell == Vector2i(3,2), "Enemy responds to automatic cast")
	check(game.get_node("%Slot1").disabled, "Skill button is cooling")
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	check("S02" not in game.auto_skills and not game.get_node("%Slot1").auto_enabled, "Right click on cooling button disables auto and border")
	var turns: int = game.model.turn
	await create_timer(0.3).timeout
	check(game.model.turn == turns, "Disabled auto does not execute queued action")
	await fixture()
	game.autocast_delay_seconds = 0.25
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	await click(slot(2), MOUSE_BUTTON_RIGHT)
	await create_timer(1.1).timeout
	check(game.model.turn == 2 and game.model.enemies[1].hp == 0 and game.model.enemies[0].hp == 2, "Multiple auto skills cast left to right with separate responses")
	await create_timer(0.4).timeout
	check(game.model.turn == 2, "No auto wait to advance cooldowns")
	await click(point(game.model.enemies[0].cell))
	check(game.model.outcome == "cleared", "Manual smart attack still works between auto casts")
	turns = game.model.turn
	await create_timer(0.4).timeout
	check(game.model.turn == turns, "No auto casts after clear")
	await fixture()
	game.model.enemies[0].hp = 6
	var pick: Dictionary = AutocastPlanner.choose(game.model, "S04")
	check(pick.target == game.model.enemies[0].cell, "Automatic attack prefers a legal kill over nearer nonlethal hit")
	await fixture()
	game.armed = true
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	await create_timer(0.25).timeout
	check(game.model.turn == 0 and game.armed, "Auto never consumes a manually armed overdrive")
	await fixture()
	game.hit_seconds = 0.15
	game.move_seconds = 0.15
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	await create_timer(0.16).timeout
	check(game.busy and game.model.turn == 1, "Automatic action locks input during animation")
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	check(game.auto_skills.is_empty() and not game.get_node("%Slot1").auto_enabled, "Right click stops future auto casts during current animation")
	await click(point(Vector2i(1,3)))
	await create_timer(0.7).timeout
	check(game.model.turn == 1, "Inputs during animation do not queue extra actions")
	# Read-only targeting, protection, no auto travel or empty swings.
	await fixture(["S05", "S09"])
	check(AutocastPlanner.choose(game.model, "S05").is_empty(), "No automatic travel in safety")
	game.model.enemies[1].hp = 0
	check(AutocastPlanner.choose(game.model, "S09").is_empty(), "No automatic empty sweep")
	await fixture(["S06", "S15"])
	check(not AutocastPlanner.choose(game.model, "S06").is_empty(), "Guard casts against imminent adjacent attack")
	game.model.shield = 30
	check(AutocastPlanner.choose(game.model, "S06").is_empty(), "Guard does not cast when existing shield already absorbs attacks")
	await fixture(["S05", "S15"], "b")
	game.model.execute({"kind":"wait"})
	var escape: Dictionary = AutocastPlanner.choose(game.model, "S05")
	check(not escape.is_empty() and escape.target not in game.model.danger(), "Auto escape chooses legal non-locked landing")
	await fixture()
	game.autocast_delay_seconds = 0.2
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	await key(KEY_2)
	await create_timer(0.3).timeout
	check(game.model.turn == 0 and game.selected == "S04", "Manual aim pauses automatic casting")
	await key(KEY_R)
	await key(KEY_ESCAPE)
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	check(game.auto_skills.is_empty(), "Cancel preserves right-click control of auto mode")
	await fixture()
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	game.request_restart()
	await create_timer(0.2).timeout
	check(game.model.turn == 0 and game.get_node("%RestartConfirm").visible, "Restart confirmation blocks auto actions")
	game.get_node("%RestartConfirm").hide()
	game.auto_skills.clear()
	await fixture()
	game.model.outcome = "cleared"
	game.model.turn = 8
	game.show_loadout()
	game.get_node("%Choices/S02").set_pressed_no_signal(false)
	game.get_node("%Choices/S05").set_pressed_no_signal(true)
	game.cancel_loadout()
	check(game.loadout == ["S02","S04"] and game.model.turn == 8, "Cancel reconfiguration preserves committed loadout and time")
	await fixture(["S04", "S02"])
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	await create_timer(0.25).timeout
	check(game.model.turn == 1 and game.model.cooldowns.S04 == 2, "Auto ranged skill enters normal cooldown")
	await game.submit({"kind":"wait"})
	await create_timer(0.2).timeout
	check(game.model.turn == 2 and game.model.cooldowns.S04 == 1, "One manual action cannot finish C2 cooldown")
	await game.submit({"kind":"wait"})
	await create_timer(0.25).timeout
	check(game.model.turn == 4 and game.model.cooldowns.S04 == 2, "Auto resumes exactly after cooldown becomes ready through actions")
	await fixture()
	game.auto_skills.assign(["S02"])
	game.model.outcome = "dead"
	game.queue_autocast()
	await create_timer(0.25).timeout
	check(game.model.turn == 0, "No auto cast after death")
	# Final screenshots use the real large map; bring one enemy close only for interface evidence.
	game.restart_run()
	game.apply_loadout()
	game.model.enemies[0].cell = game.model.player + Vector2i.RIGHT
	game.model.enemies[0].node.global_position = point(game.model.enemies[0].cell)
	game.refresh()
	await key(KEY_1)
	await hover(point(game.model.enemies[0].cell))
	await capture("refined-target-preview")
	game.autocast_delay_seconds = 2.0
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	await create_timer(0.2).timeout
	await capture("refined-autocast-border")
	var border_rect := Rect2i(game.get_node("%Slot1").get_global_rect())
	var border_before: int = hash(root.get_texture().get_image().get_region(border_rect).get_data())
	var phase_before: float = game.get_node("%Slot1").phase
	await create_timer(0.23).timeout
	await RenderingServer.frame_post_draw
	check(game.get_node("%Slot1").phase != phase_before, "Enabled ring animation advances")
	check(hash(root.get_texture().get_image().get_region(border_rect).get_data()) != border_before, "Actual rendered border changes over time")
	await click(slot(1), MOUSE_BUTTON_RIGHT)
	phase_before = game.get_node("%Slot1").phase
	await create_timer(0.2).timeout
	check(not game.get_node("%Slot1").auto_enabled and game.get_node("%Slot1").phase == phase_before, "Second right click removes border and stops animation")
	game.auto_skills.clear()
	game.auto_epoch += 1
	game.model.outcome = "cleared"
	game.model.turn = 4
	game.show_loadout()
	await capture("refined-loadout-cancel")
	check(game.get_node("%CancelLoadout").get_global_rect().end.y <= root.get_visible_rect().size.y, "Battle-end loadout cancel fits viewport")
	print("INTERACTION_SUITE ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"injected GUI input and explicit boundary fixtures, not human playtesting"}))
	game.auto_skills.clear()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
