# 游戏时钟 (CoreKit.clock) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 godot-core-kit 增加第 14 个门面子系统 `CoreKit.clock`——年/季/日/时/分 世界时钟,混合推进(实时自动 + 显式跳时/睡觉),原生 signal + `CoreKit.bus` 广播 `clock:*`,并确立全 kit 的 bus 事件命名约定 `namespace:event`(冒号)。

**Architecture:** `systems/game_clock.gd`(`extends Node`,无 class_name,经门面属性访问)。以**绝对分钟**为中枢做级联(分→时→日→季→年)。仅依赖 EventBus,经 `bind_bus` 注入(唯一跨系统通道,只在 `core_kit.gd:_ready()` 接线),未绑定则只发原生 signal(降级)。持久化 `to_dict/from_dict` 由游戏接入 `CoreKit.saves`。

**Tech Stack:** Godot 4.7,纯 GDScript,Web 导出兼容。headless `SceneTree` 测试。

## Global Constraints

- 版本 **0.15.0**(承 layer-manager v0.14.0)。三处版本必须一致:`plugin.cfg`、`core_kit.gd VERSION`、`test_core_kit.gd` 版本断言。
- **上门面第 14 子系统**:打破"13 子系统"不变量 → 14;`core_kit.gd` 门面接线 + `test_core_kit.gd`(属性表 13→14、节点序、保留键、版本、bind_bus 断言、provide 守卫)同步。
- **依赖纪律**:仅依赖 EventBus,经 `bind_bus(bus)` 注入;引用存无类型 `var _bus = null` 并守卫未绑定路径(`if _bus != null`)。不 `preload` 任何其他子系统。
- `systems/` 下门面子系统脚本**无 class_name**(经 `CoreKit.<属性>` 访问)。
- 事件名 `namespace:event`(冒号);本子系统 namespace = `clock`;事件名以 `EV_*` 常量导出。payload = 单 `Dictionary`。
- 用 **Tab** 缩进。纯 GDScript,无 shader,Web 安全。
- 测试:`extends SceneTree` + `_initialize()`,顶层用运行时 `load(...)` 不用 `const preload`;末行 `ALL PASS` + `quit(0/1)`。`run_all.ps1` 测试文件数 19→20。

## File Structure

- **Create** `addons/godot-core-kit/systems/game_clock.gd` — 时钟子系统(第 14)。
- **Create** `test/test_game_clock.gd` — 12 条 headless 断言。
- **Modify** `addons/godot-core-kit/core_kit.gd` — preload/属性/构造/`bind_bus`/`_services`/`RESERVED_KEYS`/`VERSION`/头注释。
- **Modify** `test/test_core_kit.gd` — 版本/属性表(13→14)/节点序/接线断言/保留键/provide 守卫。
- **Modify** `test/run_all.ps1`、`demo/demo.gd`、`addons/godot-core-kit/plugin.cfg`、`README.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`、`addons/godot-core-kit/docs/core/event-bus.md`。
- **Create** `addons/godot-core-kit/docs/systems/game-clock.md`。

---

### Task 1: GameClock 子系统 + headless 测试(不含门面)

**Files:**
- Create: `addons/godot-core-kit/systems/game_clock.gd`
- Create: `test/test_game_clock.gd`
- Modify: `test/run_all.ps1`(tests 数组末尾加 `test_game_clock`;`:1` 注释 19→20)

**Interfaces:**
- Produces:`GameClock`(`extends Node`)。常量 `EV_TIME_CHANGED/EV_HOUR_CHANGED/EV_DAY_CHANGED/EV_SEASON_CHANGED/EV_YEAR_CHANGED`;signal `time_changed/hour_changed/day_changed/season_changed/year_changed`;方法 `bind_bus(bus)`、`configure(cfg:Dictionary)`、`pause()`/`resume()`/`set_time_scale(f)`、`advance_minutes(n)`/`advance_hours(n)`/`advance_day()`/`sleep_to_next_day()`、`set_datetime(y,s,d,h,m)`、getter `year()/season_index()/season_name()/day()/hour()/minute()/seasons()/days_per_season()`、`snapshot()`、`to_dict()`/`from_dict(d)`;属性 `time_scale:float`、`paused:bool`;`_process(delta)` 自动走时。

- [ ] **Step 1: 写 `addons/godot-core-kit/systems/game_clock.gd`**

```gdscript
extends Node
## CoreKit.clock —— 游戏时钟/日历(第 14 子系统)。维护 年/季/日/时/分 日历,混合推进:
## _process 按 time_scale(游戏分钟/真实秒,默认 0=暂停)自动走时,同时提供 advance_minutes/
## advance_day/sleep_to_next_day 显式推进。级联(分→时→日→季→年)以绝对分钟为中枢实现;
## 每跨一级发对应原生 signal,并(若 bind_bus 注入)向 CoreKit.bus 广播 "clock:xxx"。
##
## 依赖:仅 EventBus,经 bind_bus 注入;未注入则只发原生 signal(bus 静默跳过)。
## 持久化:to_dict/from_dict,游戏自行接入 CoreKit.saves。
##
## 事件命名约定(全 kit,见 docs/core/event-bus.md):"namespace:event"。本子系统 namespace
## = "clock",事件名以 EV_* 常量导出,游戏订阅引用常量:
##   CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_new_day)

## --- 事件名常量(payload 均为 snapshot() 快照 Dictionary)---
const EV_TIME_CHANGED := "clock:time_changed"      ## 每分钟推进
const EV_HOUR_CHANGED := "clock:hour_changed"      ## 跨小时
const EV_DAY_CHANGED := "clock:day_changed"        ## 跨天(作物生长主钩子)
const EV_SEASON_CHANGED := "clock:season_changed"  ## 跨季
const EV_YEAR_CHANGED := "clock:year_changed"      ## 跨年

## --- 原生 signal(直连;与 bus 广播同时发)---
signal time_changed(hour: int, minute: int)
signal hour_changed(hour: int)
signal day_changed(day: int, season_index: int, year: int)
signal season_changed(season_index: int)
signal year_changed(year: int)

## --- 日历配置(configure 覆盖;默认星露谷式)---
var _minutes_per_hour := 60
var _hours_per_day := 24
var _days_per_season := 28
var _seasons: Array = ["spring", "summer", "fall", "winter"]
var _wake_hour := 6

## --- 日历状态(1 起:year/day;0 起:season_index/hour/minute)---
var _year := 1
var _season_index := 0
var _day := 1
var _hour := 6
var _minute := 0

## 游戏分钟/真实秒;<=0 或 paused 时 _process 不推进。默认 0(起始暂停)。
var time_scale := 0.0
var paused := false
var _accum := 0.0   ## 实时累加的游戏分钟小数余量

## bind_bus 注入;untyped:未注入(脱离门面单测)为 null。
var _bus = null


func bind_bus(bus) -> void:
	_bus = bus


## 覆盖日历配置(任一键可缺省;应在推进前调用)。键:minutes_per_hour/hours_per_day/
## days_per_season/seasons(Array)/wake_hour。其它键忽略(故 from_dict 可整包传入)。
func configure(cfg: Dictionary) -> void:
	if cfg.has("minutes_per_hour"): _minutes_per_hour = maxi(1, int(cfg["minutes_per_hour"]))
	if cfg.has("hours_per_day"): _hours_per_day = maxi(1, int(cfg["hours_per_day"]))
	if cfg.has("days_per_season"): _days_per_season = maxi(1, int(cfg["days_per_season"]))
	if cfg.has("seasons") and not (cfg["seasons"] as Array).is_empty(): _seasons = (cfg["seasons"] as Array).duplicate()
	if cfg.has("wake_hour"): _wake_hour = clampi(int(cfg["wake_hour"]), 0, _hours_per_day - 1)


func _process(delta: float) -> void:
	if paused or time_scale <= 0.0:
		return
	_accum += delta * time_scale
	if _accum < 1.0:
		return
	var whole := int(_accum)
	_accum -= float(whole)
	advance_minutes(whole)


func pause() -> void:
	paused = true


func resume() -> void:
	paused = false


func set_time_scale(scale: float) -> void:
	time_scale = maxf(0.0, scale)


## 推进 n 游戏分钟(n<=0 no-op)。以绝对分钟加法级联,按跨级发信号/广播。
func advance_minutes(n: int) -> void:
	if n <= 0:
		return
	var b_year := _year
	var b_season := _season_index
	var b_absday := _abs_day()
	var b_hour := _hour
	_set_from_abs(_abs_minutes() + n)
	_fire(b_year, b_season, b_absday, b_hour)


func advance_hours(n: int) -> void:
	advance_minutes(n * _minutes_per_hour)


## 前进一整天(保持当前时:分)。
func advance_day() -> void:
	advance_minutes(_minutes_per_day())


## 睡觉:跳到次日 wake_hour:00。
func sleep_to_next_day() -> void:
	var b_year := _year
	var b_season := _season_index
	var b_absday := _abs_day()
	var b_hour := _hour
	var next_day_start := (b_absday + 1) * _minutes_per_day()
	_set_from_abs(next_day_start + _wake_hour * _minutes_per_hour)
	_fire(b_year, b_season, b_absday, b_hour)


## 直接置位(不发级联信号;用于 from_dict/调试)。各字段夹取到合法范围。
func set_datetime(year: int, season_index: int, day: int, hour: int, minute: int) -> void:
	_year = maxi(1, year)
	_season_index = clampi(season_index, 0, _seasons.size() - 1)
	_day = clampi(day, 1, _days_per_season)
	_hour = clampi(hour, 0, _hours_per_day - 1)
	_minute = clampi(minute, 0, _minutes_per_hour - 1)
	_accum = 0.0


## --- 只读 getter ---
func year() -> int: return _year
func season_index() -> int: return _season_index
func season_name() -> String:
	return String(_seasons[_season_index]) if _season_index < _seasons.size() else ""
func day() -> int: return _day
func hour() -> int: return _hour
func minute() -> int: return _minute
func seasons() -> Array: return _seasons.duplicate()
func days_per_season() -> int: return _days_per_season


## 当前日历快照(bus payload / UI 一次性读取)。
func snapshot() -> Dictionary:
	return {
		"year": _year, "season_index": _season_index, "season_name": season_name(),
		"day": _day, "hour": _hour, "minute": _minute,
	}


## --- 持久化 ---
func to_dict() -> Dictionary:
	var d := snapshot()
	d.erase("season_name")   # 派生字段不存
	d["time_scale"] = time_scale
	d["paused"] = paused
	d["minutes_per_hour"] = _minutes_per_hour
	d["hours_per_day"] = _hours_per_day
	d["days_per_season"] = _days_per_season
	d["seasons"] = _seasons.duplicate()
	d["wake_hour"] = _wake_hour
	return d


func from_dict(d: Dictionary) -> void:
	configure(d)   # 先恢复配置(configure 只挑自己的键,int() 包)
	set_datetime(int(d.get("year", 1)), int(d.get("season_index", 0)),
		int(d.get("day", 1)), int(d.get("hour", _wake_hour)), int(d.get("minute", 0)))
	time_scale = float(d.get("time_scale", 0.0))
	paused = bool(d.get("paused", false))


## --- 内部:绝对分钟中枢 ---
func _minutes_per_day() -> int: return _hours_per_day * _minutes_per_hour
func _minutes_per_season() -> int: return _days_per_season * _minutes_per_day()
func _minutes_per_year() -> int: return _seasons.size() * _minutes_per_season()

func _abs_minutes() -> int:
	return ((_year - 1) * _seasons.size() + _season_index) * _minutes_per_season() \
		+ (_day - 1) * _minutes_per_day() + _hour * _minutes_per_hour + _minute

func _abs_day() -> int:
	return _abs_minutes() / _minutes_per_day()

func _set_from_abs(m: int) -> void:
	if m < 0: m = 0
	var mps := _minutes_per_season()
	var mpd := _minutes_per_day()
	_year = m / _minutes_per_year() + 1
	m = m % _minutes_per_year()
	_season_index = m / mps
	m = m % mps
	_day = m / mpd + 1
	m = m % mpd
	_hour = m / _minutes_per_hour
	_minute = m % _minutes_per_hour

## 从粗到细比较并发信号 + bus 广播。
func _fire(b_year: int, b_season: int, b_absday: int, b_hour: int) -> void:
	if _year != b_year:
		year_changed.emit(_year); _publish(EV_YEAR_CHANGED)
	if _season_index != b_season:
		season_changed.emit(_season_index); _publish(EV_SEASON_CHANGED)
	if _abs_day() != b_absday:
		day_changed.emit(_day, _season_index, _year); _publish(EV_DAY_CHANGED)
	if _hour != b_hour:
		hour_changed.emit(_hour); _publish(EV_HOUR_CHANGED)
	time_changed.emit(_hour, _minute); _publish(EV_TIME_CHANGED)

func _publish(ev: String) -> void:
	if _bus != null:
		_bus.publish(ev, snapshot())
```

- [ ] **Step 2: 写 `test/test_game_clock.gd`**

```gdscript
extends SceneTree
## GameClock headless 断言。不入树、直接 .new() 实例化(手动调 _process 保确定性,
## 避免真实帧干扰);bus 断言用运行时 load 的 EventBus 实例。
## 运行:godot --headless --path . -s res://test/test_game_clock.gd

var ClockScript
var BusScript


func _initialize() -> void:
	ClockScript = load("res://addons/godot-core-kit/systems/game_clock.gd")
	BusScript = load("res://addons/godot-core-kit/core/event_bus.gd")
	var failures := 0

	# 1. 初始状态
	var c = ClockScript.new()
	if c.year() != 1 or c.season_index() != 0 or c.season_name() != "spring" or c.day() != 1 or c.hour() != 6 or c.minute() != 0:
		print("FAIL 1: 初始应 y1 spring d1 06:00,实际 y%d s%d d%d %02d:%02d" % [c.year(), c.season_index(), c.day(), c.hour(), c.minute()]); failures += 1
	if c.paused or c.time_scale != 0.0:
		print("FAIL 1: 初始应 time_scale=0 未暂停"); failures += 1

	# 2. 分->时级联
	c.advance_minutes(30)
	if c.hour() != 6 or c.minute() != 30:
		print("FAIL 2: advance 30 应 06:30"); failures += 1
	c.advance_minutes(40)
	if c.hour() != 7 or c.minute() != 10:
		print("FAIL 2: 再 advance 40 应 07:10"); failures += 1

	# 3. 跨天
	var c3 = ClockScript.new()
	c3.advance_day()
	if c3.day() != 2 or c3.hour() != 6 or c3.minute() != 0:
		print("FAIL 3: advance_day 应到 d2 06:00"); failures += 1

	# 4. 跨季(2 天季长)
	var c4 = ClockScript.new()
	c4.configure({"days_per_season": 2})
	c4.advance_day()
	c4.advance_day()
	if c4.season_index() != 1 or c4.day() != 1:
		print("FAIL 4: 2 天季长 advance 2 天应到 season1 d1,实际 s%d d%d" % [c4.season_index(), c4.day()]); failures += 1

	# 5. 跨年(1 天季长 2 季)
	var c5 = ClockScript.new()
	c5.configure({"days_per_season": 1, "seasons": ["a", "b"]})
	c5.advance_day()
	c5.advance_day()
	if c5.year() != 2:
		print("FAIL 5: 1 天季长 2 季 advance 2 天应到 year2,实际 %d" % c5.year()); failures += 1

	# 6. sleep_to_next_day
	var c6 = ClockScript.new()
	c6.set_datetime(1, 0, 1, 14, 0)
	c6.sleep_to_next_day()
	if c6.day() != 2 or c6.hour() != 6 or c6.minute() != 0:
		print("FAIL 6: sleep 应到 d2 06:00,实际 d%d %02d:%02d" % [c6.day(), c6.hour(), c6.minute()]); failures += 1

	# 7. 原生 signal 计数
	var c7 = ClockScript.new()
	var sig := {"days": 0, "last": []}
	c7.day_changed.connect(func(d, s, y): sig["days"] += 1; sig["last"] = [d, s, y])
	c7.advance_day(); c7.advance_day(); c7.advance_day()
	if sig["days"] != 3:
		print("FAIL 7: day_changed 应发 3 次,实际 %d" % sig["days"]); failures += 1
	if sig["last"] != [4, 0, 1]:
		print("FAIL 7: 末次参数应 (4,0,1),实际 %s" % str(sig["last"])); failures += 1

	# 8. bus 绑定广播
	var c8 = ClockScript.new()
	var bus = BusScript.new()
	c8.bind_bus(bus)
	var got := {"payload": null}
	bus.subscribe(c8.EV_DAY_CHANGED, func(p): got["payload"] = p)
	c8.advance_day()
	if not (got["payload"] is Dictionary) or int(got["payload"].get("day", -1)) != 2 or not got["payload"].has("season_name"):
		print("FAIL 8: bus clock:day_changed 应收到含 day/season_name 的快照,实际 %s" % str(got["payload"])); failures += 1
	bus.free()

	# 9. bus 未绑定降级
	var c9 = ClockScript.new()
	c9.advance_day()
	if c9.day() != 2:
		print("FAIL 9: 未绑定 bus 仍应正常推进"); failures += 1

	# 10. _process 走时
	var c10 = ClockScript.new()
	c10.time_scale = 60.0
	c10._process(1.0)
	if c10.hour() != 7 or c10.minute() != 0:
		print("FAIL 10: time_scale 60 _process(1.0) 应到 07:00,实际 %02d:%02d" % [c10.hour(), c10.minute()]); failures += 1
	c10.paused = true
	c10._process(1.0)
	if c10.hour() != 7:
		print("FAIL 10: paused 后 _process 不应推进"); failures += 1
	c10.paused = false
	c10.time_scale = 0.0
	c10._process(1.0)
	if c10.hour() != 7:
		print("FAIL 10: time_scale 0 不应推进"); failures += 1

	# 11. to_dict/from_dict 往返
	var c11 = ClockScript.new()
	c11.configure({"days_per_season": 10, "seasons": ["x", "y", "z"], "wake_hour": 8})
	c11.advance_minutes(3 * 60 + 15)
	c11.time_scale = 30.0
	var d11 = c11.to_dict()
	var c11b = ClockScript.new()
	c11b.from_dict(d11)
	if c11b.snapshot() != c11.snapshot():
		print("FAIL 11: from_dict 后 snapshot 应一致"); failures += 1
	if c11b.days_per_season() != 10 or c11b.seasons() != ["x", "y", "z"] or c11b.time_scale != 30.0:
		print("FAIL 11: from_dict 应恢复配置与 time_scale"); failures += 1

	# 12. set_datetime 夹取
	var c12 = ClockScript.new()
	c12.set_datetime(1, 99, 999, 99, 99)
	if c12.season_index() > 3 or c12.day() > 28 or c12.hour() > 23 or c12.minute() > 59:
		print("FAIL 12: set_datetime 应夹取到合法上界,实际 s%d d%d %02d:%02d" % [c12.season_index(), c12.day(), c12.hour(), c12.minute()]); failures += 1

	c.free(); c3.free(); c4.free(); c5.free(); c6.free(); c7.free(); c8.free(); c9.free(); c10.free(); c11.free(); c11b.free(); c12.free()

	if failures == 0:
		print("test_game_clock: ALL PASS")
		quit(0)
	else:
		print("test_game_clock: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 3: run_all 注册**

`test/run_all.ps1` 的 `$tests` 数组末尾(`'test_layer_manager'` 后)加 `,'test_game_clock'`;`:1` 注释 `19 个断言测试` → `20 个断言测试`。

- [ ] **Step 4: import + 单跑测试**

```
godot --headless --path . --import
godot --headless --path . -s res://test/test_game_clock.gd
```
Expected: `test_game_clock: ALL PASS`,退出码 0,无 `leaked`。FAIL 则按打印修 `game_clock.gd`,重跑至绿。

- [ ] **Step 5: Commit**

```bash
git add addons/godot-core-kit/systems/game_clock.gd test/test_game_clock.gd test/run_all.ps1
git commit -m "feat: GameClock 游戏时钟子系统 + 12 条 headless 断言"
```

---

### Task 2: 接入 CoreKit 门面(第 14 子系统)

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`
- Modify: `test/test_core_kit.gd`

**Interfaces:**
- Consumes:Task 1 的 `GameClock`、既有 `bus`(EventBus)。
- Produces:`CoreKit.clock`(门面属性 + `service("clock")` + 保留键 + `_bus` 已绑定为 `CoreKit.bus`)。

- [ ] **Step 1: core_kit.gd —— preload / 属性 / 构造 / bind_bus / 注册 / 保留键 / 版本 / 注释**

- `const VERSION := "0.14.0"` → `"0.15.0"`。
- 头注释(第 3-4 行)子系统列表 `.i18n / .layers。` → `.i18n / .layers / .clock。`。
- `RESERVED_KEYS` 注释 `= 13 个内置子系统` → `= 14 个内置子系统`;数组末 `"i18n", "layers"]` → `"i18n", "layers", "clock"]`。
- preload 段末(`LayerManagerScript` 那行后)加:
  ```gdscript
  const GameClockScript := preload("res://addons/godot-core-kit/systems/game_clock.gd")
  ```
- 属性段末(`var layers: LayerManagerScript` 后)加:
  ```gdscript
  var clock: GameClockScript
  ```
- `_init` 末尾(`add_child(layers)` 后)加:
  ```gdscript

  	clock = GameClockScript.new()
  	clock.name = "GameClock"
  	add_child(clock)
  ```
- `_ready` 接线段(`i18n.bind_settings(settings)` 后)加:
  ```gdscript
  	clock.bind_bus(bus)
  ```
- `_ready` 注册段(`_services["layers"] = layers` 后)加:
  ```gdscript
  	_services["clock"] = clock
  ```

- [ ] **Step 2: test_core_kit.gd —— 版本 / 属性表 / 节点序 / 接线 / 保留键 / provide 守卫**

- 版本断言(2 行,约 25-26 行):`"0.14.0"` → `"0.15.0"`。
- 第 29 行注释 `# 2. 十二个门面属性` → `# 2. 十四个门面属性`(既有 stale,顺带修准)。
- test 2 `expected` 数组 layers 行后加:
  ```gdscript
  		["clock", "res://addons/godot-core-kit/systems/game_clock.gd"],
  ```
- test 3 `order` 数组末 `"LayerManager"]` → `"LayerManager", "GameClock"]`。
- test 4 接线断言段(`res._ticker` 那块后)加:
  ```gdscript
  	if kit.clock._bus != kit.bus:
  		print("FAIL 4: clock 未绑定 bus")
  		failures += 1
  ```
- test 6 `builtin_keys` 数组末 `"i18n", "layers"]` → `"i18n", "layers", "clock"]`;并在 `provide("layers", 1)` 守卫块后加:
  ```gdscript
  	kit.provide("clock", 1)  # 保留键:应被拒
  	if kit.service("clock") != kit.clock:
  		print("FAIL 6: 保留键 clock 不应被 provide 覆盖")
  		failures += 1
  ```

- [ ] **Step 3: 单跑 test_core_kit**

Run: `godot --headless --path . -s res://test/test_core_kit.gd`
Expected: `test_core_kit: ALL PASS`。FAIL 则核对门面接线/断言,修至绿。

- [ ] **Step 4: Commit**

```bash
git add addons/godot-core-kit/core_kit.gd test/test_core_kit.gd
git commit -m "feat: CoreKit.clock 接入门面第 14 子系统 (bind_bus)"
```

---

### Task 3: 版本 / 文档 / demo / event-bus 约定 / 全量收尾

**Files:**
- Modify: `addons/godot-core-kit/plugin.cfg`、`demo/demo.gd`、`test/run_all.ps1`(demo marker)
- Modify: `README.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`、`addons/godot-core-kit/docs/core/event-bus.md`
- Create: `addons/godot-core-kit/docs/systems/game-clock.md`

- [ ] **Step 1: plugin.cfg**

`version="0.14.0"` → `"0.15.0"`;description 末尾追加 `;0.15.0 新增门面第 14 子系统 CoreKit.clock(systems/game_clock.gd):年/季/日/时/分 世界时钟,混合推进(time_scale 自动走时 + advance_minutes/day + sleep_to_next_day),原生 signal + CoreKit.bus 广播 clock:*(bind_bus 注入),to_dict/from_dict;确立全 kit 事件命名约定 namespace:event(冒号)`。

- [ ] **Step 2: demo 加 Clock 冒烟 marker**

`demo/demo.gd` 的 Layers 段之后、末尾 `CoreKit.log.info("CoreKit v%s ..."` 之前插入:

```gdscript
	# 游戏时钟 冒烟:订阅 clock:day_changed + advance_day(经门面第 14 子系统)
	var day_evt := {"hit": false}
	CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, func(_p): day_evt["hit"] = true)
	CoreKit.clock.advance_day()
	CoreKit.log.info("Clock: y%d %s d%d %02d:%02d day_evt=%s" % [
		CoreKit.clock.year(), CoreKit.clock.season_name(), CoreKit.clock.day(),
		CoreKit.clock.hour(), CoreKit.clock.minute(), day_evt["hit"]])
```

- [ ] **Step 3: run_all demo marker**

`test/run_all.ps1` 的 demo marker 数组里,`'Layers: hud_z=10'` 后加 `,'Clock: y1 spring d2 06:00 day_evt=true'`。

- [ ] **Step 4: `docs/core/event-bus.md` 加事件命名约定**

在该文件"注意事项"段之前(或末尾追加)新增一节:

```markdown
## 事件命名约定(kit 级)

事件名统一 `namespace:event`(单个**冒号**分隔):

- **namespace** = 子系统门面短名(`clock`/`save`/`scene`/`input`/`audio`/`i18n`…);kit 保留这些命名空间。游戏自己的事件用自己的命名空间(如 `farm:crop_harvested`),**不得**借 kit 命名空间发。
- **event** = 过去时 snake_case(`day_changed`/`loaded`/`changed`)。
- **payload** = 单个 `Dictionary`(或 null)。
- 每个发事件的子系统把事件名导出成 `const`(如 `CoreKit.clock.EV_DAY_CHANGED`),订阅引用常量而非裸串,防拼错、可自动补全。
- 约定是文档纪律 + `EV_*` 常量,EventBus **不**做运行时校验。

### 已保留命名空间登记表

| namespace | 子系统 | 事件常量 |
|---|---|---|
| `clock` | GameClock(`CoreKit.clock`) | `EV_TIME_CHANGED` `EV_HOUR_CHANGED` `EV_DAY_CHANGED` `EV_SEASON_CHANGED` `EV_YEAR_CHANGED` |
```

- [ ] **Step 5: 写 `addons/godot-core-kit/docs/systems/game-clock.md`(五段式)**

涵盖:**职责**(年/季/日/时/分 世界时钟,第 14 子系统,混合推进);**公开 API**(`configure`/`time_scale`/`pause`/`resume`/`set_time_scale`/`advance_minutes`/`advance_hours`/`advance_day`/`sleep_to_next_day`/`set_datetime`/getter/`snapshot`/`to_dict`/`from_dict` + `EV_*` 常量 + 5 个原生 signal);**依赖**(仅 EventBus,经 bind_bus 注入,未绑定降级);**用法示例**(configure 一年四季、`CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, ...)` 推进作物、存档接入 `to_dict`/`from_dict`、`time_scale` 挂机);**注意事项**(默认 time_scale=0 起始暂停要游戏 `resume`/`set_time_scale` 才走时;JSON int→float 用 int() 包;事件命名约定;`_process` 自动走时需子系统在树中——门面已保证)。

- [ ] **Step 6: 更新索引文档**

- 根 `README.md`:门面属性表在 `CoreKit.layers` 行后加 `| \`CoreKit.clock\` | 游戏时钟/日历(混合推进 + bus 广播) | [game-clock](addons/godot-core-kit/docs/systems/game-clock.md) |`;版本段加 `0.15.0` 条目。
- `docs/README.md`:门面子系统表(systems 段)加 `CoreKit.clock` 行(指向 `systems/game-clock.md`);顶部"统管 12 个子系统"若已是 13 则 → 14(grep 数字逐处)。
- `docs/architecture.md`:凡"13 子系统/13 个内置"措辞 → 14(Grep 定位逐处);`systems/` 目录布局注加 GameClock;版本 → 0.15.0;测试文件数(19→20);依赖纪律注(GameClock 依赖 EventBus 经 bind_bus,未绑定降级)。

- [ ] **Step 7: 全量验证**

Run: `powershell -File test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===`。20 个测试全 `OK`,demo marker `Clock: y1 spring d2 06:00 day_evt=true` present,demo stderr 无 ERROR。

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "docs+demo: wire CoreKit.clock into version/docs/demo/run_all + event-bus 命名约定, bump 0.15.0"
```

---

## Self-Review

**Spec coverage:** 日历模型/getter(test 1)、分时日级联(test 2-3)、季/年翻转(test 4-5)、sleep(test 6)、原生 signal(test 7)、bus 绑定广播 + 未绑定降级(test 8-9)、_process 走时/暂停(test 10)、to_dict/from_dict(test 11)、set_datetime 夹取(test 12);门面接入(Task 2:属性/service/保留键/节点序/bind_bus/版本 + provide 守卫);事件命名约定 + 登记表(Task 3 Step 4);docs/demo/plugin/runner(Task 3)——全覆盖。非目标(天气/相位/多时钟/调度/EventBus 校验/自动存档)均未纳入。

**Placeholder scan:** 无 TBD/TODO;每步含实际代码或精确编辑位置(带锚点)。

**Type consistency:** `advance_minutes/advance_day/sleep_to_next_day/configure/bind_bus/snapshot/to_dict/from_dict/set_datetime` 与 getter 签名在 Task 1 定义、Task 2 门面 `_services["clock"]` + `clock.bind_bus(bus)`、Task 3 demo/docs 一致;常量 `EV_DAY_CHANGED` 等一致;节点名 `GameClock`、属性 `clock`、脚本路径 `systems/game_clock.gd`、保留键 `"clock"`、子系统计数 14、版本 0.15.0 全程一致。
