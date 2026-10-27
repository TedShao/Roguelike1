extends SceneTree
const Pilot = preload("res://tests/maze_pilot.gd")
var failed: bool = false
var checks: int = 0
func _initialize() -> void:
	run.call_deferred()
func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png("res://artifacts/" + name + ".png") == OK, "Screenshot " + name)
func click_at(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		Input.parse_input_event(event)
		await process_frame
func run() -> void:
	var game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await capture("kenney-skill-book")
	var card: Button = game.get_node("%Choices").get_node("S02")
	verify(not card is CheckButton and card.button_pressed, "Skill card is a click button, initially selected")
	var at: Vector2 = card.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await create_timer(0.16).timeout
	verify(card.get_node("Icon").scale.x > 1.05, "Actual GUI hover animates icon")
	await click_at(at)
	verify(not card.button_pressed and not card.get_node("Selected").visible, "Click deselects card")
	verify(game.get_node("%ApplyLoadout").disabled, "One selected skill cannot start")
	verify(card.get_node("ClickParticles").emitting, "Click triggers particles")
	await capture("kenney-card-click")
	await click_at(at)
	verify(card.button_pressed and card.get_node("Selected").visible, "Second click selects card")
	await click_at(game.get_node("%ApplyLoadout").get_global_rect().get_center())
	verify(not game.get_node("%LoadoutPanel").visible and game.model.turn == 0, "Start button applies skills without spending a combat turn")
	await capture("kenney-maze-a")
	# Keyboard movement through the input map, then restart before the continuous run.
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_D
	Input.parse_input_event(key)
	await create_timer(0.7).timeout
	verify(game.model.turn == 1 and game.model.player == Vector2i(3, 9), "Keyboard moves one grid cell")
	game.restart_run()
	game.apply_loadout()
	game.move_seconds = 0.0
	game.hit_seconds = 0.0
	var trace: Array = []
	for index in 3:
		var initial_turn: int = game.model.turn
		var danger_captured: bool = false
		while game.model.outcome == "playing" and game.model.turn - initial_turn < 100:
			var action: Dictionary = Pilot.choose(game.model, game.skill_catalog)
			game.armed = action.get("overdrive", false)
			await game.submit(action)
			if not danger_captured and not game.model.danger().is_empty():
				await capture("kenney-maze-%s-telegraph" % game.room.room_id.to_lower())
				danger_captured = true
		verify(game.model.outcome == "cleared", "Continuous production run clears " + game.room.room_id)
		await capture("kenney-maze-%s-cleared" % game.room.room_id.to_lower())
		verify(game.get_node("%Restart").get_global_rect().end.y < 770.0, "Post-clear controls fit sidebar")
		trace.append({"room":game.room.room_id,"turns":game.model.turn-initial_turn,"hp":game.model.health,"pressure":game.model.pressure})
		if index < 2:
			var active: int = game.model.active_left
			var cooldown: int = game.model.overdrive_cd
			var pressure: int = game.model.pressure
			await click_at(game.get_node("%Next").get_global_rect().get_center())
			verify(game.room_index == index+1, "Next button enters next authored maze")
			verify(game.model.active_left == active and game.model.overdrive_cd == cooldown and game.model.pressure == pressure, "Cross-room state retained")
	game.restart_run()
	game.show_loadout()
	for size in [Vector2i(1280,800), Vector2i(1920,1080)]:
		root.size = size
		await create_timer(0.12).timeout
		await capture("kenney-ui-%dx%d" % [size.x,size.y])
		verify(game.get_node("%LoadoutPanel").get_global_rect().end.y <= root.get_visible_rect().size.y, "Skill book fits logical viewport")
	var font: Font = load("res://game/ui/theme.tres").default_font
	for character in "敌人稳神击杀锁定压力甩锅蓄力":
		verify(font.has_char(character.unicode_at(0)), "Chinese font covers " + character)
	print("RENDER_SMOKE ",JSON.stringify({"passed":not failed,"checks":checks,"continuous_run":trace,"scope":"actual renderer and injected GUI input, not a human enjoyment test"}))
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
