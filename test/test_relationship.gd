extends SceneTree
## test/test_relationship.gd —— 好感度纯逻辑离线测(不依赖 CoreKit;运行时 load,不用顶层 preload)。
## 覆盖:gift_delta 各偏好档、level_of 分档、reaction_of 映射、relationships JSON 往返键归一。
## 按需单跑(不进 run_all $tests):
##   godot --headless --path . -s res://test/test_relationship.gd
## 运行时送礼累加/扣物/当日防刷/解锁 由 FARM_SMOKE(带 CoreKit)覆盖,不在此重复。

func _initialize() -> void:
	var Relationship = load("res://examples/farm-sim/relationship.gd")
	var NpcDef = load("res://examples/farm-sim/npc_def.gd")
	var failures := 0

	var d = NpcDef.new()
	d.gift_loved = [&"turnip"]
	d.gift_liked = [&"potato"]
	d.gift_disliked = [&"parsnip"]

	# gift_delta 各档
	if Relationship.gift_delta(d, &"turnip") != Relationship.GIFT_LOVED:
		failures += 1; print("FAIL 1: loved delta")
	if Relationship.gift_delta(d, &"potato") != Relationship.GIFT_LIKED:
		failures += 1; print("FAIL 2: liked delta")
	if Relationship.gift_delta(d, &"parsnip") != Relationship.GIFT_DISLIKED:
		failures += 1; print("FAIL 3: disliked delta")
	if Relationship.gift_delta(d, &"wood") != Relationship.GIFT_NEUTRAL:
		failures += 1; print("FAIL 4: neutral delta")
	if Relationship.gift_delta(null, &"x") != Relationship.GIFT_NEUTRAL:
		failures += 1; print("FAIL 5: null def -> neutral")

	# level_of 分档(每 100 一级,负点数 0 级)
	if Relationship.level_of(0) != 0 or Relationship.level_of(99) != 0:
		failures += 1; print("FAIL 6: level 0 band")
	if Relationship.level_of(100) != 1 or Relationship.level_of(250) != 2:
		failures += 1; print("FAIL 7: level up")
	if Relationship.level_of(-50) != 0:
		failures += 1; print("FAIL 8: negative -> 0")

	# reaction_of 映射
	if Relationship.reaction_of(Relationship.GIFT_LOVED) != "loved":
		failures += 1; print("FAIL 9: react loved")
	if Relationship.reaction_of(Relationship.GIFT_LIKED) != "liked":
		failures += 1; print("FAIL 10: react liked")
	if Relationship.reaction_of(Relationship.GIFT_DISLIKED) != "disliked":
		failures += 1; print("FAIL 11: react disliked")
	if Relationship.reaction_of(Relationship.GIFT_NEUTRAL) != "neutral":
		failures += 1; print("FAIL 12: react neutral")

	# relationships JSON 往返:StringName 键 → String(JSON) → StringName 归一(见 quest_log 同款坑)
	var rel := {&"merchant": 150, &"granny": 40}
	var saveable := {}
	for k in rel:
		saveable[String(k)] = int(rel[k])
	var parsed = JSON.parse_string(JSON.stringify(saveable))
	var restored := {}
	for k in parsed:
		restored[StringName(k)] = int(parsed[k])
	if restored.get(&"merchant", 0) != 150 or restored.get(&"granny", 0) != 40:
		failures += 1; print("FAIL 13: relationships round-trip value")
	if not restored.has(&"merchant"):
		failures += 1; print("FAIL 14: StringName key normalized")

	if failures == 0:
		print("test_relationship: ALL PASS")
		quit(0)
	else:
		print("test_relationship: %d FAILURE(S)" % failures)
		quit(1)
