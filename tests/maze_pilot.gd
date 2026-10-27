# Test-only deterministic one-response lookahead. No production gameplay hooks.
extends RefCounted

const STATE = ["cooldowns", "player", "health", "pressure", "shield", "shield_left", "guard", "guard_left", "active_left", "overdrive_cd", "turn", "enemies", "outcome"]

static func choose(model: BattleModel, catalog: Array[SkillSpec]) -> Dictionary:
	var actions: Array[Dictionary] = [{"kind": "wait"}, {"kind": "steady"}]
	for direction in BattleModel.DIRECTIONS:
		actions.append({"kind": "move", "target": model.player + direction})
	for enemy in model.enemies:
		if enemy.hp <= 0:
			continue
		for kind in ["basic"] + model.equipped:
			actions.append({"kind": kind, "target": enemy.cell})
	var best: Dictionary = {}
	var best_score: float = -INF
	for action in actions:
		for boost in [false, true]:
			var candidate: Dictionary = action.duplicate()
			candidate.overdrive = boost
			if not model.preview(candidate).valid:
				continue
			var trial := BattleModel.new(model.room, catalog, model.equipped)
			for key in STATE:
				var value = model.get(key)
				trial.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
			trial.execute(candidate)
			var remaining_hp: int = 0
			var nearest: int = 99
			for enemy in trial.enemies:
				if enemy.hp > 0:
					remaining_hp += enemy.hp
					nearest = mini(nearest, trial.distance(trial.player, enemy.cell))
			var score: float = trial.health * 100.0 - remaining_hp * 15.0 - trial.living_count() * 500.0 - trial.pressure - nearest * 2.0
			if trial.player in trial.danger(): score -= 24.0
			if trial.outcome == "dead": score -= 100000.0
			if candidate.kind == "wait": score -= 0.5
			if score > best_score:
				best_score = score
				best = candidate
	return best
