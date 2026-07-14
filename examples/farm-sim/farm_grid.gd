extends RefCounted
## 农田网格模型(纯逻辑,零 core-kit 依赖,可脱离场景树 headless 单测)。
## 持有 W×H 个格子的状态与已种作物;耕/种/浇/收经注入的 KitInventory(背包)+ KitDataRegistry
## (作物/物品定义)完成。表现层(FarmGridView)只读本模型画占位美术,互不耦合。
##
## 设计:格子状态 EMPTY→TILLED→WATERED 与"格上是否有作物"正交;作物是 {id, stage},
## 生长由 advance_day() 推进(P0 固定 +1/天,浇水加成留到 P2)。所有非法操作静默返回 false,
## 反馈日志交给调用方(world/player),模型自身不打印。

enum State { EMPTY, TILLED, WATERED }

const CELL := 32   ## 单格像素边长(表现层与玩家共用坐标换算)

var _w := 0
var _h := 0
var _state: Dictionary = {}   ## Vector2i -> State(缺省 EMPTY)
var _crop: Dictionary = {}    ## Vector2i -> {id: StringName, stage: int}
var _registry                 ## KitDataRegistry(crop/item 定义)
var _bag                      ## KitInventory(背包)


## 注入依赖 + 网格尺寸(驱动方构建时调用)。
func setup(registry, bag, w: int, h: int) -> void:
	_registry = registry
	_bag = bag
	_w = w
	_h = h


func size() -> Vector2i:
	return Vector2i(_w, _h)


func cell_size() -> int:
	return CELL


func cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _w and cell.y < _h


## 格左上角世界坐标;格中心 = +CELL/2。
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL).floor())


func tile_state(cell: Vector2i) -> int:
	return _state.get(cell, State.EMPTY)


func has_crop(cell: Vector2i) -> bool:
	return _crop.has(cell)


func crop_id(cell: Vector2i) -> StringName:
	return _crop[cell]["id"] if _crop.has(cell) else &""


func crop_stage(cell: Vector2i) -> int:
	return int(_crop[cell]["stage"]) if _crop.has(cell) else 0


## 该格作物是否成熟(stage 达到定义的 grow_days)。
func crop_mature(cell: Vector2i) -> bool:
	if not _crop.has(cell):
		return false
	var def = _registry.get_def(&"crop", _crop[cell]["id"])
	return def != null and int(_crop[cell]["stage"]) >= int(def.grow_days)


## 该格作物生长进度 0.0~1.0(供渲染;无作物返回 0)。
func crop_ratio(cell: Vector2i) -> float:
	if not _crop.has(cell):
		return 0.0
	var def = _registry.get_def(&"crop", _crop[cell]["id"])
	if def == null or int(def.grow_days) <= 0:
		return 1.0
	return clampf(float(_crop[cell]["stage"]) / float(def.grow_days), 0.0, 1.0)


## 耕地:空格 → 已耕。
func till(cell: Vector2i) -> bool:
	if not cell_valid(cell) or tile_state(cell) != State.EMPTY:
		return false
	_state[cell] = State.TILLED
	return true


## 播种:已耕/已浇且无作物,背包有该作物种子 → 扣 1 种子并种下(stage 0)。
func plant(cell: Vector2i, crop_id_arg: StringName) -> bool:
	if not cell_valid(cell) or _crop.has(cell):
		return false
	if tile_state(cell) != State.TILLED and tile_state(cell) != State.WATERED:
		return false
	var def = _registry.get_def(&"crop", crop_id_arg)
	if def == null:
		return false
	var seed = def.seed_item
	if _bag.count(seed) < 1:
		return false
	_bag.remove(seed, 1)
	_crop[cell] = {"id": crop_id_arg, "stage": 0}
	return true


## 浇水:已耕 → 已浇(带不带作物都可)。已是已浇/未耕返回 false。
func water(cell: Vector2i) -> bool:
	if not cell_valid(cell) or tile_state(cell) != State.TILLED:
		return false
	_state[cell] = State.WATERED
	return true


## 收获:该格作物成熟 → 产物入背包(单格上限取自 item 表),清作物、格回已耕。
func harvest(cell: Vector2i) -> bool:
	if not crop_mature(cell):
		return false
	var def = _registry.get_def(&"crop", _crop[cell]["id"])
	var cap := -1
	var idef = _registry.get_def_or(&"item", def.harvest_item, null)
	if idef != null:
		cap = int(idef.max_stack)
	_bag.add(def.harvest_item, int(def.harvest_amount), {}, cap)
	_crop.erase(cell)
	_state[cell] = State.TILLED
	return true


## 推进一天:所有未成熟作物生长一格(P0 固定 +1)。
func advance_day() -> void:
	for cell in _crop:
		if not crop_mature(cell):
			_crop[cell]["stage"] = int(_crop[cell]["stage"]) + 1


## 持久化:Vector2i 键序列化成 "x,y" 字符串(JSON 安全),id 存 String。registry/bag 不入档
## (由 setup 注入),读档前须先 setup 再 from_dict。
func to_dict() -> Dictionary:
	var st := {}
	for cell in _state:
		st[_key(cell)] = int(_state[cell])
	var cr := {}
	for cell in _crop:
		cr[_key(cell)] = {"id": String(_crop[cell]["id"]), "stage": int(_crop[cell]["stage"])}
	return {"w": _w, "h": _h, "state": st, "crop": cr}


## 从存档还原。经 JSON 往返:键为 String、数值为 float、id 退化为 String —— 这里统一归一回
## Vector2i 键 + int + StringName(见 dogfood 的 JSON 退化坑)。
func from_dict(d: Dictionary) -> void:
	_w = int(d.get("w", _w))
	_h = int(d.get("h", _h))
	_state = {}
	var st: Dictionary = d.get("state", {})
	for k in st:
		_state[_unkey(k)] = int(st[k])
	_crop = {}
	var cr: Dictionary = d.get("crop", {})
	for k in cr:
		_crop[_unkey(k)] = {"id": StringName(cr[k]["id"]), "stage": int(cr[k]["stage"])}


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _unkey(s: String) -> Vector2i:
	var parts := s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
