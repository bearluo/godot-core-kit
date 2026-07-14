extends SceneTree
## KitInventory headless 断言。RefCounted,直接 load().new(),无需入树/free。
## 运行:godot --headless --path . -s res://test/test_kit_inventory.gd

var Inv


func _initialize() -> void:
	Inv = load("res://addons/godot-core-kit/inventory/kit_inventory.gd")
	var failures := 0

	# 1. add + count + slot
	var a = Inv.new(10)
	a.add(&"wood", 5)
	if a.count(&"wood") != 5 or a.used_slots() != 1:
		print("FAIL 1: add wood5 应 count5 used1"); failures += 1
	var s0 = a.slot(0)
	if s0.get("id") != &"wood" or s0.get("count") != 5 or s0.get("data") != {}:
		print("FAIL 1: slot(0) 应 {wood,5,{}}"); failures += 1

	# 2. 堆进已有
	a.add(&"wood", 3)
	if a.count(&"wood") != 8 or a.used_slots() != 1:
		print("FAIL 2: 再 add wood3 应 count8 used1"); failures += 1

	# 3. 溢出多格
	var b = Inv.new(10, 99)
	if b.add(&"wood", 120) != 0 or b.count(&"wood") != 120 or b.used_slots() != 2:
		print("FAIL 3: add 120 应 rem0 count120 used2"); failures += 1

	# 4. 满 + 余量
	var c = Inv.new(1, 50)
	if c.add(&"wood", 120) != 70 or c.slot(0).get("count") != 50 or not c.is_full():
		print("FAIL 4: 单格50 add120 应 rem70 slot50 full"); failures += 1

	# 5. remove 部分/清格
	var d = Inv.new(10)
	d.add(&"wood", 30)
	if d.remove(&"wood", 10) != 10 or d.count(&"wood") != 20:
		print("FAIL 5: remove10 应返10 余20"); failures += 1
	if d.remove(&"wood", 100) != 20 or d.count(&"wood") != 0 or d.slot(0) != {}:
		print("FAIL 5: remove100 应返20 余0 空格"); failures += 1

	# 6. has
	var e = Inv.new(10)
	e.add(&"wood", 5)
	if not e.has(&"wood") or not e.has(&"wood", 5) or e.has(&"wood", 6) or e.has(&"stone"):
		print("FAIL 6: has 判定错"); failures += 1

	# 7. data 分格不误合
	var f = Inv.new(10)
	f.add(&"wood", 5, {"q": 1})
	f.add(&"wood", 5, {"q": 2})
	if f.used_slots() != 2 or f.count(&"wood") != 10:
		print("FAIL 7: 不同 data 应分 2 格,count 合计 10"); failures += 1

	# 8. move 到空
	var g = Inv.new(10)
	g.add(&"wood", 5)
	g.move(0, 3)
	if g.slot(0) != {} or g.slot(3).get("id") != &"wood":
		print("FAIL 8: move 到空格失败"); failures += 1

	# 9. move 合并同 id
	var h = Inv.new(10)
	h.set_slot(0, &"wood", 5)
	h.set_slot(1, &"wood", 3)
	h.move(0, 1)
	if h.slot(1).get("count") != 8 or h.slot(0) != {}:
		print("FAIL 9: move 合并同 id 失败"); failures += 1

	# 10. move 交换异物
	var i = Inv.new(10)
	i.set_slot(0, &"wood", 5)
	i.set_slot(1, &"stone", 5)
	i.move(0, 1)
	if i.slot(0).get("id") != &"stone" or i.slot(1).get("id") != &"wood":
		print("FAIL 10: move 异物应交换"); failures += 1

	# 11. can_add
	var j = Inv.new(2, 10)
	j.add(&"wood", 5)
	if j.can_add(&"wood", 100) != 15:
		print("FAIL 11: can_add 应 15,实际 %d" % j.can_add(&"wood", 100)); failures += 1

	# 12. is_full / first_empty
	var k = Inv.new(2, 10)
	k.set_slot(0, &"a", 1)
	k.set_slot(1, &"b", 1)
	if not k.is_full() or k.first_empty() != -1:
		print("FAIL 12: 填满应 is_full first_empty=-1"); failures += 1

	# 13. to_dict/from_dict 往返
	var m = Inv.new(4, 99)
	m.set_slot(0, &"wood", 50, {"q": 1})
	m.set_slot(2, &"stone", 12)
	var m2 = Inv.new(1)
	m2.from_dict(m.to_dict())
	if m2.capacity() != 4 or m2.slot(0).get("id") != &"wood" or m2.slot(0).get("count") != 50 or m2.slot(0).get("data") != {"q": 1} or m2.slot(2).get("id") != &"stone" or m2.count(&"stone") != 12:
		print("FAIL 13: from_dict 往返不一致"); failures += 1

	# 14. changed 信号
	var n = Inv.new(10)
	var fired := {"n": 0}
	n.changed.connect(func(): fired["n"] += 1)
	n.add(&"wood", 1)
	if fired["n"] < 1:
		print("FAIL 14: add 应发 changed"); failures += 1

	# 15. totals 聚合(跨格合并同 id,忽略 data 分堆)
	var t = Inv.new(10, 5)
	t.add(&"wood", 12)            # 5+5+2 三格
	t.add(&"stone", 3)
	t.add(&"wood", 2, {"q": 1})  # 不同 data 另起一格,但 totals 按 id 合并
	var tot = t.totals()
	if tot.get(&"wood") != 14 or tot.get(&"stone") != 3 or tot.size() != 2:
		print("FAIL 15: totals 应 {wood:14, stone:3},实际 %s" % str(tot)); failures += 1
	if not Inv.new(3).totals().is_empty():
		print("FAIL 15: 空背包 totals 应 {}"); failures += 1

	if failures == 0:
		print("test_kit_inventory: ALL PASS")
		quit(0)
	else:
		print("test_kit_inventory: %d FAILURE(S)" % failures)
		quit(1)
