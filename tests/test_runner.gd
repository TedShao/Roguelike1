extends SceneTree

var failures: PackedStringArray = []
var checks: int = 0
var catalog: Array[SkillSpec] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("TEST FAIL: " + message)

func fixture(letter: String, loadout: Array[String]) -> BattleModel:
	var scene: PackedScene = load("res://game/scenes/rooms/room_%s.tscn" % letter)
	var room: FixedRoom = scene.instantiate()
	root.add_child(room)
	check(room.validation_errors().is_empty(), "%s authored room validates" % letter)
	return BattleModel.new(room, catalog, loadout)

func dispose(model: BattleModel) -> void:
	model.room.free()

func step(model: BattleModel, action: Dictionary, context: String) -> void:
	var result: Dictionary = model.execute(action)
	check(result.valid, context + " action legal")

func run() -> void:
	for id in ["s02", "s04", "s05", "s06", "s09", "s10", "s13", "s15", "s17", "s18"]:
		catalog.append(load("res://game/data/skills/%s.tres" % id))
	# Independent expectations transcribed from the design's three complete paper traces.
	var a: BattleModel = fixture("a", ["S02", "S04"])
	step(a, {"kind": "S02", "target": Vector2i(3, 3)}, "A1")
	check(a.enemies[1].hp == 0 and a.enemies[0].cell == Vector2i(3, 2), "A push/collision kill and stable chase")
	step(a, {"kind": "S04", "target": Vector2i(3, 2)}, "A2")
	check(a.enemies[0].hp == 2 and a.enemies[0].cell == Vector2i(2, 2), "A ranged hit and move without extra attack")
	step(a, {"kind": "basic", "target": Vector2i(2, 2)}, "A3")
	check(a.outcome == "cleared" and a.health == 30 and a.turn == 3, "A paper result 30 HP in 3 turns")
	check(a.cooldowns.S02 == 0 and a.cooldowns.S04 == 0, "clear resets ordinary cooldowns")
	dispose(a)
	var b: BattleModel = fixture("b", ["S04", "S05"])
	var actions_b: Array = [
		{"kind": "wait"}, {"kind": "move", "target": Vector2i(1, 4)},
		{"kind": "S04", "target": Vector2i(2, 4)}, {"kind": "basic", "target": Vector2i(2, 4)},
		{"kind": "move", "target": Vector2i(1, 3)}, {"kind": "move", "target": Vector2i(1, 4)},
		{"kind": "S04", "target": Vector2i(2, 3)}, {"kind": "move", "target": Vector2i(1, 3)},
		{"kind": "move", "target": Vector2i(1, 4)}, {"kind": "S04", "target": Vector2i(2, 3)},
		{"kind": "move", "target": Vector2i(2, 4)}, {"kind": "basic", "target": Vector2i(2, 3)}]
	for i in range(actions_b.size()):
		step(b, actions_b[i], "B%d" % (i + 1))
		if i == 0:
			check(b.danger() == [Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)], "heavy locks all three cells")
		if i == 3:
			check(b.cooldowns.S04 == 1, "C2 skill remains unavailable on the second subsequent choice")
	check(b.outcome == "cleared" and b.health == 27 and b.turn == 12, "B corrected deterministic route: 27 HP in 12 turns")
	dispose(b)
	var c: BattleModel = fixture("c", ["S04", "S05"])
	var actions_c: Array = [{"kind": "S04", "target": Vector2i(2, 1)},
		{"kind": "S05", "target": Vector2i(1, 3)}, {"kind": "wait"},
		{"kind": "S04", "target": Vector2i(2, 1)}, {"kind": "basic", "target": Vector2i(2, 3)},
		{"kind": "basic", "target": Vector2i(2, 3)}]
	for i in range(actions_c.size()):
		step(c, actions_c[i], "C%d" % (i + 1))
	check(c.outcome == "cleared" and c.health == 24 and c.pressure == 0 and c.turn == 6, "C paper result 24 HP / 0 pressure in 6 turns")
	dispose(c)
	await process_frame
	test_timing_and_defense()
	test_targets_and_death()
	test_remaining_skills()
	await test_authored_configuration()
	if "--inject-failure" in OS.get_cmdline_user_args():
		check(false, "intentional failure verifies non-zero exit")
	var report: Dictionary = {"checks": checks, "failures": Array(failures), "passed": failures.is_empty(),
		"scope": "Godot native rules + serialized scene edit persistence; not player enjoyment or full chapter"}
	var file := FileAccess.open("res://artifacts/test-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TEST_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func test_timing_and_defense() -> void:
	var m: BattleModel = fixture("a", ["S06", "S15"])
	var invalid: Dictionary = m.execute({"kind": "move", "target": Vector2i(5, 3), "overdrive": true})
	check(not invalid.valid and m.turn == 0 and m.pressure == 0 and m.active_left == 0, "invalid action never activates overdrive or spends time")
	# Controlled timing fixture: enemies recover each response; no combat damage masks the clock.
	for i in range(8):
		for enemy in m.enemies:
			enemy.state = "recover"
		step(m, {"kind": "wait", "overdrive": i == 0}, "clock T%d" % (i + 1))
		if i < 2:
			check(m.active_left == 2 - i and m.overdrive_cd == 0, "active clock %d" % i)
		else:
			check(m.active_left == 0 and m.overdrive_cd == 7 - i, "cooldown clock %d" % i)
	check(m.preview({"kind": "wait", "overdrive": true}).valid, "T9 may activate again")
	m.health = 30
	m.active_left = 3
	m.shield = 8
	m.shield_left = 2
	m.hurt_player(8, "fixture heavy")
	check(m.health == 22 and m.shield == 0, "double incoming damage before shield: 16 - 8 = 8")
	m.active_left = 0
	m.health = 30
	m.enemies[0].hp = 0
	m.enemies[1].cell = Vector2i(3, 3)
	m.enemies[1].state = "observe"
	m.shield = 0
	m.cooldowns.S15 = 0
	step(m, {"kind": "S15"}, "shield first response")
	check(m.shield == 5 and m.shield_left == 1 and m.health == 30, "base barrier survives first response")
	step(m, {"kind": "basic", "target": Vector2i(3, 3)}, "shield next attack")
	check(m.health == 30 and m.shield == 0, "barrier protects following attack then expires")
	dispose(m)

func test_targets_and_death() -> void:
	var m: BattleModel = fixture("a", ["S09", "S17"])
	check(not m.visible(Vector2i(4, 2), Vector2i(5, 4)), "supercover blocks wall crossing")
	check(m.visible(Vector2i(4, 2), Vector2i(2, 3)) == m.visible(Vector2i(2, 3), Vector2i(4, 2)), "LOS symmetric")
	check(m.preview({"kind": "S17", "target": Vector2i(4, 2), "landing": Vector2i(3, 2)}).valid, "shadow strike validates target and walkable landing path")
	check(not m.preview({"kind": "S17", "target": Vector2i(4, 2), "landing": Vector2i(1, 1)}).valid, "shadow strike rejects nonadjacent landing")
	m.enemies[0].cell = Vector2i(3, 2)
	step(m, {"kind": "S09", "target": Vector2i(3, 3)}, "fan")
	check(m.enemies[0].hp == 4 and m.enemies[1].hp == 4, "fan hits each snapshot target once")
	dispose(m)
	m = fixture("a", ["S02", "S04"])
	m.enemies[0].hp = 0
	m.enemies[1].hp = 5
	m.health = 6
	m.pressure = 95
	step(m, {"kind": "basic", "target": Vector2i(3, 3)}, "last kill overload")
	check(m.living_count() == 0 and m.outcome == "dead" and m.health == 0, "overload death wins over final kill")
	dispose(m)
	m = fixture("b", ["S02", "S04"])
	m.enemies[0].state = "prepared"
	m.enemies[0].locked = [Vector2i(2, 4)]
	m.move_enemy(0, Vector2i(1, 2), true)
	check(m.enemies[0].state == "recover" and m.enemies[0].locked.is_empty(), "forced displacement interrupts telegraph")
	dispose(m)

func test_remaining_skills() -> void:
	var m: BattleModel = fixture("b", ["S10", "S13"])
	step(m, {"kind": "S10", "target": Vector2i(2, 2)}, "lunge")
	check(m.player == Vector2i(2, 3) and m.enemies[0].hp == 11, "lunge stops before target then damages once")
	dispose(m)
	m = fixture("a", ["S13", "S18"])
	step(m, {"kind": "S13", "target": Vector2i(3, 3)}, "spellblade")
	check(m.enemies[1].hp == 1 and m.cooldowns.S13 == 1, "spellblade damage and one subsequent cooldown turn")
	m.enemies[1].hp = 4
	check(m.preview({"kind": "S18", "target": Vector2i(3, 3)}).damage == 11, "execution includes exact 40 percent threshold and rounds up")
	m.enemies[1].hp = 5
	check(m.preview({"kind": "S18", "target": Vector2i(3, 3)}).damage == 7, "execution does not boost above threshold")
	dispose(m)
	m = fixture("a", ["S06", "S02"])
	step(m, {"kind": "S06"}, "guard")
	check(m.health == 30 and m.guard == 0, "guard reduces current response then expires")
	dispose(m)
	m = fixture("a", ["S02", "S04"])
	m.enemies[0].hp = 0
	m.enemies[1].hp = 20
	step(m, {"kind": "S02", "target": Vector2i(3, 3), "overdrive": true}, "overdrive collision")
	check(m.enemies[1].hp == 0 and m.pressure == 20 and m.active_left == 2, "direct 12 plus collision 8 each multiply once; clear carries active clock")
	dispose(m)
	m = fixture("a", ["S17", "S04"])
	step(m, {"kind": "S17", "target": Vector2i(4, 2), "landing": Vector2i(3, 2)}, "shadow strike")
	check(m.player == Vector2i(3, 2) and m.enemies[0].hp == 3, "shadow strike reaches legal landing and hits selected target")
	dispose(m)

func test_authored_configuration() -> void:
	# Actual serialized edits, loaded through the production controller, including refresh.
	var source: PackedScene = load("res://game/scenes/rooms/room_a.tscn")
	var edited: FixedRoom = source.instantiate()
	var gate: FixedInteractable = edited.get_node("Props/ExitGate")
	edited.set_editable_instance(gate, true)
	gate.position = Vector2(548, 352)
	gate.scale = Vector2(0.85, 0.85)
	gate.get_node("Sprite2D").texture = load("res://game/art/prototype/heavy.svg")
	gate.get_node("Sprite2D").scale = Vector2(1.1, 0.9)
	gate.get_node("InteractionArea/CollisionShape2D").shape = RectangleShape2D.new()
	gate.get_node("InteractionArea/CollisionShape2D").shape.size = Vector2(112, 118)
	gate.get_node("Prompt").text = "已保存的出口测试"
	edited.get_node("PlayerSpawn").position = edited.cell_to_local(Vector2i(1, 3))
	edited.get_node("Walls/Wall_5_3").position += Vector2(0, 68)
	var packed := PackedScene.new()
	check(packed.pack(edited) == OK, "pack editor-style scene modifications")
	var path: String = "res://artifacts/edited-room-verification.tscn"
	check(ResourceSaver.save(packed, path) == OK, "persist actual edited .tscn")
	edited.free()
	var reloaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var game: Node2D = load("res://game/scenes/main.tscn").instantiate()
	var old: Node = game.get_node("RoomHost").get_child(0)
	game.get_node("RoomHost").remove_child(old)
	old.free()
	game.get_node("RoomHost").add_child(reloaded.instantiate())
	game.encounter_scenes[0] = reloaded
	root.add_child(game)
	await process_frame
	var live: FixedRoom = game.room
	gate = live.get_node("Props/ExitGate")
	check(gate.position == Vector2(548, 352), "controller preserves authored exit position")
	check(gate.scale == Vector2(0.85, 0.85), "controller preserves whole-object scale")
	check(gate.get_node("Sprite2D").texture.resource_path.ends_with("heavy.svg"), "controller preserves authored texture")
	check(gate.get_node("Sprite2D").scale == Vector2(1.1, 0.9), "controller preserves sprite dimensions")
	check(gate.get_node("InteractionArea/CollisionShape2D").shape.size == Vector2(112, 118), "controller preserves interaction shape size")
	check(gate.get_node("Prompt").text == "已保存的出口测试", "controller preserves authored prompt")
	check(gate.contains_world_point(gate.to_global(Vector2(50, 0))), "actual authored expanded interaction region is used")
	check(not gate.contains_world_point(gate.to_global(Vector2(60, 0))), "point beyond authored interaction shape is rejected")
	check(game.model.player == Vector2i(1, 3), "player starts from edited marker")
	check(not live.blocked(Vector2i(5, 3)) and live.blocked(Vector2i(5, 4)), "logical walls read edited CollisionShape2D placement")
	var sprite_before: Vector2 = gate.get_node("Sprite2D").global_position
	var shape_before: Vector2 = gate.get_node("InteractionArea/CollisionShape2D").global_position
	var prompt_before: Vector2 = gate.get_node("Prompt").global_position
	gate.position += Vector2(20, 10)
	check(gate.get_node("Sprite2D").global_position - sprite_before == Vector2(20, 10), "moving parent moves visual")
	check(gate.get_node("InteractionArea/CollisionShape2D").global_position - shape_before == Vector2(20, 10), "moving parent moves interaction")
	check(gate.get_node("Prompt").global_position - prompt_before == Vector2(20, 10), "moving parent moves prompt")
	game.restart_run()
	await process_frame
	check(game.room.get_node("Props/ExitGate").position == Vector2(548, 352), "restart reloads authored edits without default-layout reset")
	game.get_node("HUD/Root/LoadoutPanel").hide()
	game.model.active_left = 2
	game.model.outcome = "cleared"
	game.advance_room()
	check(game.model.active_left == 2 and game.model.overdrive_cd == 0, "active turns persist across room transition")
	game.model.active_left = 0
	game.model.overdrive_cd = 4
	game.model.outcome = "cleared"
	game.advance_room()
	check(game.model.overdrive_cd == 4, "cooldown persists across room transition")
	game.free()
	await process_frame
