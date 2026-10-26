extends SceneTree

var failed: bool = false

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: int = root.get_texture().get_image().save_png("res://artifacts/" + name + ".png")
	verify(result == OK, "Screenshot saved: " + name)

func run() -> void:
	var game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.apply_loadout()
	await capture("d1-room-a")
	var gate: FixedInteractable = game.room.get_node("Props/ExitGate")
	verify(gate.position == Vector2(548, 352), "Editor-saved exit position survives production startup")
	game.choose("S02")
	# Event coordinates must be consumed directly, even if the OS pointer is elsewhere.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.room.to_global(game.room.cell_to_local(Vector2i(3, 3)))
	game._unhandled_input(click)
	verify(not game.pending.is_empty() and game.model.turn == 0, "Mouse event previews target without spending a turn")
	await game.submit({"kind": "S02", "target": Vector2i(3, 3)})
	await game.submit({"kind": "S04", "target": Vector2i(3, 2)})
	await game.submit({"kind": "basic", "target": Vector2i(2, 2)})
	await capture("d1-room-a-cleared")
	verify(game.model.health == 30 and game.model.turn == 3 and game.model.outcome == "cleared", "Rendered A trace")
	var restart: Button = game.get_node("HUD/Root/Sidebar/Column/Restart")
	verify(restart.get_global_rect().end.y <= root.get_visible_rect().end.y, "Post-clear restart button remains inside viewport")
	game.board_click(gate.global_position)
	verify(game.room.room_id == "B", "Moved gate interaction opens B")
	await game.submit({"kind": "wait"})
	await capture("d1-room-b-telegraph")
	verify(game.model.danger().size() == 3, "Rendered heavy telegraph has three cells")
	game.restart_run()
	game.apply_loadout()
	verify(game.room.get_node("Props/ExitGate").position == Vector2(548, 352), "Restart preserves editor modification")
	var font: Font = load("res://game/ui/theme.tres").default_font
	for character in "敌人稳神击杀锁定压力甩锅蓄力":
		verify(font.has_char(character.unicode_at(0)), "Chinese font covers " + character)
	print("RENDER_SMOKE " + ("FAIL" if failed else "PASS") + " | A clear, event input, saved exit, B telegraph, UI bounds, restart")
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
