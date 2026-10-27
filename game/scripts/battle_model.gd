class_name BattleModel
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var room: FixedRoom
var rules: BattleRules
var skills: Dictionary = {}
var equipped: Array[String] = []
var cooldowns: Dictionary = {}
var player: Vector2i
var health: int
var pressure: int = 0
var shield: int = 0
var shield_left: int = 0
var guard: int = 0
var guard_left: int = 0
var active_left: int = 0
var overdrive_cd: int = 0
var turn: int = 0
var enemies: Array[Dictionary] = []
var outcome: String = "playing"
var events: Array[Dictionary] = []
var messages: PackedStringArray = []

func _init(authored_room: FixedRoom, catalog: Array[SkillSpec], loadout: Array[String]) -> void:
	room = authored_room
	rules = room.rules
	health = rules.player_health
	player = room.player_cell()
	for skill in catalog:
		skills[skill.skill_id] = skill
	equipped = loadout.duplicate()
	for id in equipped:
		cooldowns[id] = 0
	for actor in room.enemy_actors():
		enemies.append({"id": enemies.size(), "node": actor, "cell": room.world_to_cell(actor.global_position),
			"hp": actor.enemy_spec.max_health, "spec": actor.enemy_spec, "state": "observe", "locked": []})
	if enemies.is_empty():
		outcome = "cleared"

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func enemy_at(cell: Vector2i) -> int:
	for enemy in enemies:
		if enemy.hp > 0 and enemy.cell == cell:
			return enemy.id
	return -1

func free_cell(cell: Vector2i, ignore_enemy: int = -1, allow_player: bool = false) -> bool:
	if room.blocked(cell) or (cell == player and not allow_player):
		return false
	var index: int = enemy_at(cell)
	return index == -1 or index == ignore_enemy

## Symmetric supercover from cell center to center, including both corner-touch cells.
func visible(from: Vector2i, to: Vector2i) -> bool:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	var nx: int = absi(dx)
	var ny: int = absi(dy)
	var sx: int = signi(dx)
	var sy: int = signi(dy)
	var x: int = from.x
	var y: int = from.y
	var ix: int = 0
	var iy: int = 0
	while ix < nx or iy < ny:
		var lhs: int = (1 + 2 * ix) * ny
		var rhs: int = (1 + 2 * iy) * nx
		if lhs == rhs:
			if room.blocked(Vector2i(x + sx, y)) or room.blocked(Vector2i(x, y + sy)):
				return false
			x += sx
			y += sy
			ix += 1
			iy += 1
		elif lhs < rhs:
			x += sx
			ix += 1
		else:
			y += sy
			iy += 1
		if room.blocked(Vector2i(x, y)):
			return false
	return true

func path_to(start: Vector2i, goal: Vector2i, ignore_enemy: int = -1, maximum: int = 4096) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if start == goal:
		return [start]
	if not free_cell(goal, ignore_enemy):
		return empty
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var lengths: Dictionary = {start: 0}
	var cursor: int = 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if lengths[current] >= maximum:
			continue
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if previous.has(next) or not free_cell(next, ignore_enemy):
				continue
			previous[next] = current
			lengths[next] = lengths[current] + 1
			if next == goal:
				var result: Array[Vector2i] = [goal]
				var back: Vector2i = goal
				while back != start:
					back = previous[back]
					result.push_front(back)
				return result
			frontier.append(next)
	return empty

func preview(action: Dictionary) -> Dictionary:
	var kind: String = action.get("kind", "")
	var target: Vector2i = action.get("target", player)
	if outcome != "playing":
		return {"valid": false, "reason": "本场已经结束。"}
	if action.get("overdrive", false) and (active_left > 0 or overdrive_cd > 0):
		return {"valid": false, "reason": "透支仍在持续或冷却。"}
	var valid: bool = false
	var reason: String = "目标或路径不合法。"
	var targets: Array = []
	var damage: int = 0
	var path: Array[Vector2i] = []
	var enemy_id: int = enemy_at(target)
	if kind == "wait" or kind == "steady":
		valid = true
	elif kind == "move":
		valid = distance(player, target) == 1 and free_cell(target)
		path = [player, target]
	elif kind == "basic":
		valid = enemy_id >= 0 and distance(player, target) == 1
		damage = rules.basic_damage
		targets = [target]
	elif skills.has(kind) and kind in equipped:
		var skill: SkillSpec = skills[kind]
		if cooldowns.get(kind, 0) > 0:
			return {"valid": false, "reason": "技能还需等待 %d 次行动。" % cooldowns[kind]}
		damage = skill.damage
		match kind:
			"S06", "S15":
				valid = true
			"S05":
				path = path_to(player, target, -1, skill.reach)
				valid = target != player and not path.is_empty() and visible(player, target)
			"S09":
				valid = distance(player, target) == 1
				var direction: Vector2i = target - player
				var side := Vector2i(-direction.y, direction.x)
				for cell in [target, target + side, target - side]:
					if not room.blocked(cell) and visible(player, cell):
						targets.append(cell)
			"S10":
				valid = enemy_id >= 0 and distance(player, target) <= skill.reach and (player.x == target.x or player.y == target.y)
				if valid:
					var direction := Vector2i(signi(target.x - player.x), signi(target.y - player.y))
					var cursor: Vector2i = player
					path = [player]
					while cursor + direction != target:
						cursor += direction
						if not free_cell(cursor):
							valid = false
							break
						path.append(cursor)
				targets = [target]
			"S17":
				var landing: Vector2i = action.get("landing", Vector2i(-999, -999))
				path = path_to(player, landing, -1, skill.path_limit)
				valid = enemy_id >= 0 and distance(player, target) <= skill.reach and visible(player, target) and distance(target, landing) == 1 and not path.is_empty()
				targets = [target]
			_:
				valid = enemy_id >= 0 and distance(player, target) <= skill.reach and visible(player, target)
				targets = [target]
				if valid and kind == "S18" and float(enemies[enemy_id].hp) / enemies[enemy_id].spec.max_health <= 0.4:
					damage = ceili(damage * 1.5)
	else:
		reason = "未装备这项技能。"
	if active_left > 0 or action.get("overdrive", false):
		damage *= 2
	if not valid:
		if kind == "move":
			reason = "普通移动只能到相邻空格，不会自动寻路。"
		elif kind == "basic":
			reason = "普攻需要相邻敌人；远处敌人需先接近或使用技能。"
		elif kind == "S17":
			reason = "影袭需要可见敌人和可达的相邻落点。"
		elif kind == "S09":
			reason = "横扫请选择自身上下左右相邻格作为方向。"
		elif skills.has(kind):
			reason = "目标超出射程、被墙遮挡或路径被占用。"
	# Read-only player-action consequences. Enemy responses are intentionally not simulated.
	var push_path: Array[Vector2i] = []
	var collision: int = 0
	var interrupt: bool = false
	var hits: int = 0
	for enemy in enemies:
		if enemy.hp > 0 and enemy.cell in targets:
			hits += 1
	if valid and kind == "S02" and enemies[enemy_id].hp > damage:
		var pushed: Vector2i = target
		for step in range(skills[kind].push_distance):
			var next: Vector2i = pushed + target - player
			if not free_cell(next, enemy_id):
				collision = skills[kind].collision_damage * (2 if active_left > 0 or action.get("overdrive", false) else 1)
				break
			pushed = next
			push_path.append(pushed)
		interrupt = not push_path.is_empty() and enemies[enemy_id].state == "prepared"
	var after_pressure: int = pressure
	if pressure >= rules.pressure_warning:
		after_pressure += rules.pressure_growth
	if action.get("overdrive", false):
		after_pressure += rules.overdrive_pressure
	if kind == "steady":
		after_pressure = maxi(0, after_pressure - rules.steady_reduction)
	return {"valid": valid, "reason": "可执行" if valid else reason, "targets": targets,
		"damage": damage, "path": path, "pressure": after_pressure,
		"overload": after_pressure >= rules.overload_threshold, "hits": hits,
		"push_path": push_path, "collision": collision, "interrupt": interrupt}

func shadow_landings(target: Vector2i) -> Array:
	var result: Array = []
	if enemy_at(target) < 0:
		return result
	for direction in DIRECTIONS:
		var landing: Vector2i = target + direction
		if preview({"kind": "S17", "target": target, "landing": landing}).valid:
			result.append(landing)
	return result

func intent_text(index: int) -> String:
	var enemy: Dictionary = enemies[index]
	var spec: EnemySpec = enemy.spec
	if enemy.state == "recover":
		return "下次响应：恢复，不攻击。"
	if enemy.state == "prepared":
		return "下次响应：攻击叉格，%s；锁地不追踪。" % ("压力 +%d" % spec.pressure if spec.kind == "speaker" else "基础伤害 %d" % spec.damage)
	return spec.description

func execute(action: Dictionary) -> Dictionary:
	var checked: Dictionary = preview(action)
	if not checked.valid:
		return checked
	events.clear()
	messages.clear()
	turn += 1
	var old_cooldowns: Array = []
	for id in cooldowns:
		if cooldowns[id] > 0:
			old_cooldowns.append(id)
	var was_cooling: bool = overdrive_cd > 0
	if pressure >= rules.pressure_warning:
		pressure += rules.pressure_growth
	if action.get("overdrive", false):
		active_left = rules.overdrive_duration
		pressure += rules.overdrive_pressure
		messages.append("透支开启：连续 %d 回合，输出与敌伤 ×2。" % rules.overdrive_duration)
	var kind: String = action.kind
	var target: Vector2i = action.get("target", player)
	if skills.has(kind):
		cooldowns[kind] = skills[kind].cooldown
	var multiplier: int = 2 if active_left > 0 else 1
	match kind:
		"move":
			move_player(target)
		"wait":
			messages.append("等待。")
		"steady":
			pressure = maxi(0, pressure - rules.steady_reduction)
			messages.append("稳神：压力降低 %d。" % rules.steady_reduction)
		"S05", "S10", "S17":
			var path: Array = checked.path
			if not path.is_empty() and path.back() != player:
				move_player(path.back())
			if kind != "S05":
				damage_enemy(enemy_at(target), checked.damage, kind)
		"S06":
			guard = skills[kind].protection
			guard_left = skills[kind].protection_responses
			messages.append("硬撑：本响应每次攻击减 %d。" % guard)
		"S15":
			if skills[kind].protection > shield:
				shield = skills[kind].protection
				shield_left = skills[kind].protection_responses
			messages.append("结界：剩余屏障 %d，覆盖 %d 次响应。" % [shield, shield_left])
		"S09":
			for enemy in enemies:
				if enemy.hp > 0 and enemy.cell in checked.targets:
					damage_enemy(enemy.id, checked.damage, kind)
		"S02":
			var index: int = enemy_at(target)
			damage_enemy(index, checked.damage, kind)
			if enemies[index].hp > 0:
				var direction: Vector2i = target - player
				for step in range(skills[kind].push_distance):
					var next: Vector2i = enemies[index].cell + direction
					if not free_cell(next, index):
						damage_enemy(index, skills[kind].collision_damage * multiplier, "碰撞")
						break
					move_enemy(index, next, true)
		_:
			damage_enemy(enemy_at(target), checked.damage, kind)
	check_overload()
	if health > 0 and living_count() > 0:
		for enemy in enemies:
			if enemy.hp <= 0:
				continue
			enemy_response(enemy.id)
			check_overload()
			if health <= 0:
				break
	for id in old_cooldowns:
		cooldowns[id] = maxi(0, cooldowns[id] - 1)
	if shield_left > 0:
		shield_left -= 1
		if shield_left == 0:
			shield = 0
	if guard_left > 0:
		guard_left -= 1
		if guard_left == 0:
			guard = 0
	if active_left > 0:
		active_left -= 1
		if active_left == 0:
			overdrive_cd = rules.overdrive_cooldown
	elif was_cooling:
		overdrive_cd = maxi(0, overdrive_cd - 1)
	if health <= 0:
		outcome = "dead"
		messages.append("倒下了。生命归零优先于清场。")
	elif living_count() == 0:
		outcome = "cleared"
		shield = 0
		shield_left = 0
		guard = 0
		guard_left = 0
		for id in cooldowns:
			cooldowns[id] = 0
		messages.append("清场。可调整基础技能／降低压力；透支计时跨房保留。")
	return {"valid": true, "events": events.duplicate(true), "messages": messages.duplicate(), "outcome": outcome}

func damage_enemy(index: int, amount: int, source: String) -> void:
	if index < 0 or enemies[index].hp <= 0:
		return
	var enemy: Dictionary = enemies[index]
	enemy.hp = maxi(0, enemy.hp - amount)
	events.append({"type": "hit", "id": index, "amount": amount})
	messages.append("%s → %s %d 伤害%s" % [source, enemy.spec.display_name, amount, "，击杀" if enemy.hp == 0 else ""])
	if enemy.hp == 0:
		enemy.locked = []

func hurt_player(amount: int, source: String) -> void:
	var raw: int = amount * (2 if active_left > 0 else 1)
	var after_guard: int = maxi(0, raw - guard)
	var absorbed: int = mini(shield, after_guard)
	shield -= absorbed
	var loss: int = after_guard - absorbed
	health = maxi(0, health - loss)
	events.append({"type": "hit", "id": -1, "amount": loss})
	messages.append("%s %d → 守护 %d／屏障 %d → 生命 −%d" % [source, raw, mini(guard, raw), absorbed, loss])

func check_overload() -> void:
	if pressure >= rules.overload_threshold:
		health = maxi(0, health - rules.overload_damage)
		pressure = rules.overload_reset
		events.append({"type": "hit", "id": -1, "amount": rules.overload_damage})
		messages.append("超载：直接失去 %d 生命，压力回到 %d。" % [rules.overload_damage, pressure])

func move_player(cell: Vector2i) -> void:
	player = cell
	events.append({"type": "move", "id": -1, "cell": cell})

func move_enemy(index: int, cell: Vector2i, forced: bool = false) -> void:
	enemies[index].cell = cell
	events.append({"type": "move", "id": index, "cell": cell})
	if forced and enemies[index].state == "prepared":
		enemies[index].state = "recover"
		enemies[index].locked = []
		messages.append("强制位移打断蓄力；该敌人下次响应只恢复。")

func enemy_response(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	var spec: EnemySpec = enemy.spec
	if enemy.state == "recover":
		enemy.state = "observe"
		messages.append("%s 恢复。" % spec.display_name)
		return
	if enemy.state == "prepared":
		if player in enemy.locked:
			if spec.kind == "speaker":
				pressure += spec.pressure
				messages.append("传话筒：压力 +%d。" % spec.pressure)
			else:
				hurt_player(spec.damage, spec.display_name)
		else:
			messages.append("%s 的锁地攻击落空。" % spec.display_name)
		enemy.locked = []
		enemy.state = "recover"
		return
	var cell: Vector2i = enemy.cell
	if spec.kind == "chaser" and distance(cell, player) == 1:
		hurt_player(spec.damage, spec.display_name)
		return
	var in_range: bool = distance(cell, player) <= spec.reach and visible(cell, player)
	if spec.kind == "heavy" and in_range and (cell.x == player.x or cell.y == player.y):
		var direction := Vector2i(signi(player.x - cell.x), signi(player.y - cell.y))
		for step in range(1, spec.reach + 1):
			var target: Vector2i = cell + direction * step
			if room.blocked(target):
				break
			enemy.locked.append(target)
		enemy.state = "prepared"
		messages.append("抬杠者锁定直线，下一响应重击 %d。" % spec.damage)
		return
	if spec.kind == "speaker" and in_range:
		enemy.locked = [player]
		for direction in DIRECTIONS:
			if not room.blocked(player + direction):
				enemy.locked.append(player + direction)
		enemy.state = "prepared"
		messages.append("传话筒锁定十字，下一响应施压 %d。" % spec.pressure)
		return
	var candidates: Array = []
	for direction in DIRECTIONS:
		var goal: Vector2i = player + direction
		var path: Array[Vector2i] = path_to(cell, goal, index)
		if not path.is_empty():
			candidates.append({"goal": goal, "path": path})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.path.size() != b.path.size():
			return a.path.size() < b.path.size()
		return a.goal.y < b.goal.y or (a.goal.y == b.goal.y and a.goal.x < b.goal.x))
	if not candidates.is_empty() and candidates[0].path.size() > 1:
		move_enemy(index, candidates[0].path[1])

func living_count() -> int:
	var count: int = 0
	for enemy in enemies:
		if enemy.hp > 0:
			count += 1
	return count

func danger() -> Array:
	var result: Array = []
	for enemy in enemies:
		if enemy.hp > 0:
			for cell in enemy.locked:
				if cell not in result:
					result.append(cell)
	return result
