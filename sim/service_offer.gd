class_name ServiceOffer
extends RefCounted
## Three cards: one safe card for the next stage's top stat, then two general cards.
## The general draw is hash(championship seed, stage index, "service").
## A general card leaves the pool after that stat has been raised three times.

const GENERAL_DRAW := 2
const RAISE_CAP := 3


static func service_seed(championship_seed: int, stage_index: int) -> int:
	return StageSolver.mix_seed([championship_seed, stage_index, "service"])


static func top_stat(stage: StageDef) -> String:
	# Equal weights keep the earlier stat in STAT_NAMES.
	var best := String(Entry.STAT_NAMES[0])
	var best_weight := stage.weight(best)
	for index in range(1, Entry.STAT_NAMES.size()):
		var stat_name := String(Entry.STAT_NAMES[index])
		var weight := stage.weight(stat_name)
		if weight > best_weight:
			best = stat_name
			best_weight = weight
	return best


static func build(
	catalog: Catalog,
	entry: Entry,
	next_stage: StageDef,
	championship_seed: int,
	stage_index: int
) -> Array[CardDef]:
	var offer: Array[CardDef] = []
	var safe_card := _safe_card(catalog, entry, top_stat(next_stage))
	if safe_card != null:
		offer.append(safe_card)
	var drawn := _draw(
		_general_pool(catalog, entry),
		service_seed(championship_seed, stage_index),
		GENERAL_DRAW
	)
	for card in drawn:
		offer.append(card)
	return offer


static func pick_ai(offer: Array[CardDef], next_stage: StageDef) -> String:
	var best_id := ""
	var best_score := 0.0
	var found := false
	for card in offer:
		if card == null:
			continue
		var score := dot(card, next_stage)
		if not found or score > best_score or (is_equal_approx(score, best_score) and card.id < best_id):
			found = true
			best_score = score
			best_id = card.id
	return best_id


static func dot(card: CardDef, stage: StageDef) -> float:
	var score := 0.0
	for stat_name in Entry.STAT_NAMES:
		score += float(card.delta(stat_name)) * stage.weight(stat_name)
	return score


static func _safe_card(catalog: Catalog, entry: Entry, stat_name: String) -> CardDef:
	var chosen: CardDef = null
	for card in catalog.cards:
		if card == null or not card.safe or entry.owns(card.id):
			continue
		if card.delta(stat_name) <= 0:
			continue
		if not _exclusive_stat(card, stat_name):
			continue
		if chosen == null or card.id < chosen.id:
			chosen = card
	return chosen


static func _exclusive_stat(card: CardDef, stat_name: String) -> bool:
	for other in Entry.STAT_NAMES:
		if other == stat_name:
			continue
		if card.delta(other) != 0:
			return false
	return true


static func _general_pool(catalog: Catalog, entry: Entry) -> Array[CardDef]:
	var pool: Array[CardDef] = []
	for card in catalog.cards:
		if card == null or card.safe or entry.owns(card.id):
			continue
		if _blocked_by_cap(catalog, entry, card):
			continue
		pool.append(card)
	pool.sort_custom(func(a: CardDef, b: CardDef) -> bool:
		return a.id < b.id
	)
	return pool


static func _blocked_by_cap(catalog: Catalog, entry: Entry, card: CardDef) -> bool:
	for stat_name in Entry.STAT_NAMES:
		var amount := card.delta(stat_name)
		if amount > 0 and _raised(catalog, entry, stat_name) + amount > RAISE_CAP:
			return true
	return false


static func _raised(catalog: Catalog, entry: Entry, stat_name: String) -> int:
	var total := 0
	for card_id in entry.card_ids:
		var card := catalog.card(card_id)
		if card == null:
			continue
		var amount := card.delta(stat_name)
		if amount > 0:
			total += amount
	return total


static func _draw(pool: Array[CardDef], seed_value: int, count: int) -> Array[CardDef]:
	var bag: Array[CardDef] = []
	bag.assign(pool)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(bag.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var swap: CardDef = bag[index]
		bag[index] = bag[swap_index]
		bag[swap_index] = swap
	var picked: Array[CardDef] = []
	var take := mini(count, bag.size())
	for index in take:
		picked.append(bag[index])
	picked.sort_custom(func(a: CardDef, b: CardDef) -> bool:
		return a.id < b.id
	)
	return picked
