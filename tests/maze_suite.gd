extends SceneTree

const Pilot = preload("res://tests/maze_pilot.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void:
	run.call_deferred()
func verify(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)
func run() -> void:
	var game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	game.move_seconds = 0.0
	game.hit_seconds = 0.0
	game.apply_loadout()
	var traces: Array = []
	for scene in game.encounter_scenes:
		game.replace_room(scene)
		game.bind_room()
		verify(game.room.validation_errors().is_empty(), "Valid " + game.room.room_id)
		verify(game.room.cells().size() == 247, "19x13 authored bounds " + game.room.room_id)
		var walk: Array[Vector2i] = []
		for cell in game.room.cells():
			if not game.room.blocked(cell): walk.append(cell)
		var reached: Array[Vector2i] = [game.model.player]
		var cursor: int = 0
		while cursor < reached.size():
			var cell: Vector2i = reached[cursor]
			cursor += 1
			for direction in BattleModel.DIRECTIONS:
				var next: Vector2i = cell + direction
				if next in walk and next not in reached: reached.append(next)
		verify(reached.size() == walk.size() and walk.size() >= 150, "All 150+ floor cells reachable " + game.room.room_id)
		var gate: Node2D = game.room.get_node("Props/ExitGate")
		verify(game.room.world_to_cell(gate.global_position) in reached, "Exit reachable " + game.room.room_id)
		var start: int = Time.get_ticks_msec()
		var path: Array = []
		while game.model.outcome == "playing" and game.model.turn < 100:
			var action: Dictionary = Pilot.choose(game.model, game.skill_catalog)
			if action.is_empty(): break
			var result: Dictionary = game.model.execute(action)
			verify(result.valid, "Pilot action legal")
			path.append({"turn":game.model.turn,"action":action,"hp":game.model.health,"pressure":game.model.pressure})
		verify(game.model.outcome == "cleared", "Unmodified rules clear " + game.room.room_id)
		traces.append({"room":game.room.room_id,"walkable":walk.size(),"outcome":game.model.outcome,"turns":game.model.turn,"hp":game.model.health,"elapsed_ms":Time.get_ticks_msec()-start,"actions":path})
	# Save a real edited copy, then load it through the production controller.
	var edited: FixedRoom = load("res://game/scenes/rooms/maze_a.tscn").instantiate()
	root.add_child(edited)
	var edited_gate: Node2D = edited.get_node("Props/ExitGate")
	edited_gate.position = edited.cell_to_local(Vector2i(16, 2))
	edited_gate.get_node("InteractionArea/CollisionShape2D").shape.size = Vector2(38, 40)
	var packed := PackedScene.new()
	verify(packed.pack(edited) == OK, "Pack edited maze")
	verify(ResourceSaver.save(packed, "res://artifacts/edited-maze.tscn") == OK, "Save edited maze")
	edited.free()
	game.replace_room(load("res://artifacts/edited-maze.tscn"))
	game.bind_room()
	var live_gate: Node2D = game.room.get_node("Props/ExitGate")
	verify(live_gate.position == Vector2(792, 120), "Saved gate move survives startup")
	verify(live_gate.get_node("InteractionArea/CollisionShape2D").shape.size == Vector2(38, 40), "Saved click shape survives startup")
	verify(live_gate.contains_world_point(live_gate.global_position), "Moved gate still interactive")
	var icon_hashes: Array[int] = []
	for spec in game.skill_catalog:
		verify(spec.icon != null, "Skill icon loaded after script: " + spec.skill_id)
		var icon_hash: int = hash(spec.icon.get_image().get_data())
		verify(icon_hash not in icon_hashes, "Skill image is unique: " + spec.skill_id)
		icon_hashes.append(icon_hash)
	var report: Dictionary = {"checks":checks,"failures":failures,"traces":traces,"scope":"AI lookahead test, not human playtest; no stat changes"}
	FileAccess.open("res://artifacts/kenney-maze-tests.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MAZE_TEST ",JSON.stringify({"checks":checks,"failures":failures,"rooms":traces.map(func(t): return {"room":t.room,"turns":t.turns,"hp":t.hp,"outcome":t.outcome})}))
	game.free()
	quit(0 if failures.is_empty() else 1)
