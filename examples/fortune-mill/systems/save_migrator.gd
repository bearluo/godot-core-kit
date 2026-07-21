class_name SaveMigrator
extends RefCounted
## 存档版本迁移链(example 内孵化,拟反哺进 kit SaveManager 信封 _version)。
##
## 长期运营的放置游戏一次数值改版就报废老存档,故存档 data 内自带 "schema_version"
## 版本章;加载旧档时按序跑注册的迁移函数 v(n) → v(n+1),逐级升到 current_version。
## 缺某级迁移函数 / 迁移函数返回非字典 / 存档版本高于当前(未来版本)→ 迁移失败,
## 由调用方保底新档(不静默覆盖旧文件,下次 save 才写)。
##
## 纯 RefCounted,不挂树、不引用门面,可 headless 单测。反哺窗口:定型后把本机制上移进
## kit save_manager.gd 的 load() —— 届时版本章走信封 _version,游戏不再需自己在 data 里盖章。

## data 里的版本章键。缺失视为 v1(兼容所有未打版本章的历史存档)。
const VERSION_KEY := "schema_version"

## 目标(当前)数据版本。低于它的存档会被逐级迁移;等于则原样;高于则判未来版本失败。
var current_version: int = 1
## from_version(int) -> Callable(data: Dictionary) -> Dictionary 迁移函数注册表。
var _steps: Dictionary = {}


func _init(current: int = 1) -> void:
	current_version = current


## 注册一步迁移:把 from_version 的 data 升级为 from_version+1 的 data 并返回。
func register(from_version: int, fn: Callable) -> void:
	_steps[from_version] = fn


## 读出 data 的版本章(缺失 → 1)。
func version_of(data: Dictionary) -> int:
	return int(data.get(VERSION_KEY, 1))


## 迁移 data 到 current_version。返回 {ok, data, from, to, reason}:
## - from == to:原样(补盖版本章),ok=true。
## - from < to:逐步跑注册函数;任一步缺失 → reason="missing:N",返回非字典 → reason="error:N",ok=false。
## - from > to:未来版本 → reason="future",ok=false。
func migrate(data: Dictionary) -> Dictionary:
	var from := version_of(data)
	var to := current_version
	if from > to:
		return {"ok": false, "data": data, "from": from, "to": to, "reason": "future"}
	var cur = data   # 无类型:后续要接住迁移函数返回的 Variant(已 is Dictionary 守卫)
	var v := from
	while v < to:
		if not _steps.has(v):
			return {"ok": false, "data": data, "from": from, "to": to, "reason": "missing:%d" % v}
		var out = _steps[v].call(cur)
		if not (out is Dictionary):
			return {"ok": false, "data": data, "from": from, "to": to, "reason": "error:%d" % v}
		cur = out
		v += 1
	cur[VERSION_KEY] = to
	return {"ok": true, "data": cur, "from": from, "to": to, "reason": ""}
