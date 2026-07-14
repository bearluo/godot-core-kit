extends Node
## 一块农田 = 农场示例的集成粘合层。持有(注入的)作物+物品数据表 + 玩家背包,负责:
## - plant:查 crop 定义拿种子 id → 扣 1 个种子(KitInventory)→ spawn 一株 Crop 子节点;
## - harvest_all:把已成熟作物的产物加进背包,单格上限取自 item 数据表(数据驱动堆叠)。
## 演示三个新子系统协作:KitDataRegistry(crop+item 两类定义) + KitInventory(背包) +
## GameClock/bus(生长,在 Crop 里)。农田本身不 preload 任何子系统——registry/bag 全由
## 驱动方 bind 注入,保持解耦(消费者视角)。

const CropScript := preload("res://examples/farm-sim/crop.gd")

var _registry   ## KitDataRegistry(含 "crop" 与 "item" 两种类型)
var _bag        ## KitInventory
var _crops: Array = []


## 注入依赖(驱动方在 add_child 前调用)。
func bind(registry, bag) -> void:
	_registry = registry
	_bag = bag


## 播种一株作物:查定义 → 扣 1 个种子 → spawn Crop 子节点。种子不足则跳过。
func plant(crop_id: StringName) -> void:
	var def = _registry.get_def(&"crop", crop_id)
	if def == null:
		return
	if _bag.count(def.seed_item) < 1:
		CoreKit.log.warn("[Farm] 种子不足,无法播种 %s" % crop_id)
		return
	_bag.remove(def.seed_item, 1)
	var crop := CropScript.new()
	crop.name = "Crop_%s_%d" % [crop_id, _crops.size()]
	crop.crop_id = crop_id
	crop.def = def
	_crops.append(crop)
	add_child(crop)
	CoreKit.log.info("[Farm] 播种 %s (消耗 1 %s)" % [def.display_name, _name_of(def.seed_item)])


## 收获所有已成熟作物:产物入背包(单格上限取自 item 表),作物 free()。未熟的留在地里。
func harvest_all() -> void:
	var remaining: Array = []
	for crop in _crops:
		if crop.is_ready():
			var def = crop.def
			var cap = _max_stack_of(def.harvest_item)
			_bag.add(def.harvest_item, def.harvest_amount, {}, cap)
			CoreKit.log.info("[Farm] 收获 %s x%d → 背包(单格上限 %d)" % [
				_name_of(def.harvest_item), def.harvest_amount, cap])
			crop.free()
		else:
			remaining.append(crop)
	_crops = remaining


## 取物品展示名,查不到回退原 id。
func _name_of(id: StringName) -> String:
	var idef = _registry.get_def_or(&"item", id, null)
	return idef.display_name if idef != null else String(id)


## 取物品单格上限,查不到回退 -1(=用背包默认)。
func _max_stack_of(id: StringName) -> int:
	var idef = _registry.get_def_or(&"item", id, null)
	return idef.max_stack if idef != null else -1
