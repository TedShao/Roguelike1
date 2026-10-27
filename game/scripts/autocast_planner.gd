class_name AutocastPlanner
extends RefCounted

## Chooses from visible, currently legal actions. Never advances time or simulates enemies.
static func choose(model: BattleModel, skill_id: String) -> Dictionary:
	if model.outcome != "playing" or skill_id not in model.equipped or model.cooldowns.get(skill_id, 0) > 0:
		return {}
	if skill_id in ["S06", "S15"]:
		# A shield against pressure-only attacks cannot help. Do not cycle it for nothing.
		var attacks: Array[int] = []
		for enemy in model.enemies:
			if enemy.hp <= 0 or enemy.state == "recover": continue
			if (enemy.spec.kind == "chaser" and model.distance(enemy.cell, model.player) == 1) or (enemy.spec.kind == "heavy" and enemy.state == "prepared" and model.player in enemy.locked):
				attacks.append(enemy.spec.damage * (2 if model.active_left > 0 else 1))
		var loss_now: int = incoming_loss(attacks, model.guard, model.shield)
		var skill: SkillSpec = model.skills[skill_id]
		var loss_after: int = incoming_loss(attacks, maxi(model.guard, skill.protection) if skill_id == "S06" else model.guard, maxi(model.shield, skill.protection) if skill_id == "S15" else model.shield)
		return {"kind": skill_id} if loss_after < loss_now else {}
	var options: Array[Dictionary] = []
	if skill_id == "S05":
		if model.player not in model.danger(): return {}
		var reach: int = model.skills[skill_id].reach
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				var target: Vector2i = model.player + Vector2i(x, y)
				if target not in model.danger():
					options.append({"kind": skill_id, "target": target})
	elif skill_id == "S09":
		for direction in BattleModel.DIRECTIONS:
			options.append({"kind": skill_id, "target": model.player + direction})
	else:
		for enemy in model.enemies:
			if enemy.hp <= 0: continue
			if skill_id == "S17":
				for landing in model.shadow_landings(enemy.cell):
					options.append({"kind": skill_id, "target": enemy.cell, "landing": landing})
			else:
				options.append({"kind": skill_id, "target": enemy.cell})
	var best: Dictionary = {}
	var best_score: Array = []
	for action in options:
		var preview: Dictionary = model.preview(action)
		if not preview.valid or (skill_id != "S05" and preview.hits == 0): continue
		var kills: int = 0
		var useful_damage: int = 0
		for enemy in model.enemies:
			if enemy.hp > 0 and enemy.cell in preview.targets:
				var damage: int = preview.damage + preview.collision
				kills += 1 if damage >= enemy.hp else 0
				useful_damage += mini(enemy.hp, damage)
		var landing: Vector2i = preview.path.back() if not preview.path.is_empty() else model.player
		# Avoid taking an automatic movement action into a known locked cell.
		if landing != model.player and landing in model.danger(): continue
		var score: Array = [kills, preview.hits, useful_damage, -model.distance(model.player, action.target), -landing.y, -landing.x]
		if best.is_empty() or better(score, best_score):
			best = action
			best_score = score
	return best

static func incoming_loss(attacks: Array[int], guard: int, shield: int) -> int:
	var sum: int = 0
	for amount in attacks:
		sum += maxi(0, amount - guard)
	return maxi(0, sum - shield)

static func better(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if a[i] != b[i]: return a[i] > b[i]
	return false
