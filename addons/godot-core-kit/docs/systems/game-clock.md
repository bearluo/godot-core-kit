# GameClock —— 游戏时钟/日历

> `CoreKit.clock` · `systems/game_clock.gd` · 第 14 子系统

## 职责

维护游戏世界的**年/季/日/时/分**日历,并**混合推进**:既能按真实时间自动走时(可设倍率、可暂停),也能显式跳时/跳天/睡到次日。每跨一级(时/日/季/年)发对应**原生 signal**,并(经 `bind_bus` 注入后)向 `CoreKit.bus` 广播 `clock:*` 事件——作物生长、作息、季节事件都挂在这台时钟上。日历结构可配置(默认 4 季 × 28 天 × 24 时 × 60 分)。

## 公开 API

```gdscript
# --- 事件名常量(payload = snapshot() 快照 Dictionary)---
const EV_TIME_CHANGED := "clock:time_changed"      # 每分钟推进
const EV_HOUR_CHANGED := "clock:hour_changed"      # 跨小时
const EV_DAY_CHANGED := "clock:day_changed"        # 跨天(作物生长主钩子)
const EV_SEASON_CHANGED := "clock:season_changed"  # 跨季
const EV_YEAR_CHANGED := "clock:year_changed"      # 跨年

# --- 原生 signal(直连;与 bus 广播同时发)---
signal time_changed(hour: int, minute: int)
signal hour_changed(hour: int)
signal day_changed(day: int, season_index: int, year: int)
signal season_changed(season_index: int)
signal year_changed(year: int)

# --- 配置 / 推进 ---
func configure(cfg: Dictionary) -> void   # 键:minutes_per_hour/hours_per_day/days_per_season/seasons(Array)/wake_hour
var time_scale: float                     # 游戏分钟 / 真实秒;默认 0(起始暂停)
var paused: bool
func pause() -> void
func resume() -> void
func set_time_scale(scale: float) -> void
func advance_minutes(n: int) -> void
func advance_hours(n: int) -> void
func advance_day() -> void                # 前进一整天(保持当前时:分)
func sleep_to_next_day() -> void          # 跳到次日 wake_hour:00
func set_datetime(year, season_index, day, hour, minute) -> void  # 直接置位(夹取;不发级联信号)

# --- 只读 getter / 快照 / 持久化 ---
func year() -> int
func season_index() -> int
func season_name() -> String
func day() -> int
func hour() -> int
func minute() -> int
func seasons() -> Array
func days_per_season() -> int
func snapshot() -> Dictionary             # {year, season_index, season_name, day, hour, minute}
func to_dict() -> Dictionary
func from_dict(d: Dictionary) -> void
```

## 依赖

仅依赖 `EventBus`,经 `bind_bus(bus)` 注入(在 `core_kit.gd:_ready()` 接线,门面已保证)。**未绑定 bus 时只发原生 signal,bus 广播静默跳过**(降级路径,可脱离门面 headless 单测)。不 `preload` 任何其他子系统。持久化只给 `to_dict/from_dict`,由游戏接入 `CoreKit.saves`(不耦合 SaveManager)。

## 用法示例

```gdscript
# 1) 配置日历(可选;不配用默认 4 季 28 天)
CoreKit.clock.configure({
    "days_per_season": 28,
    "seasons": ["spring", "summer", "fall", "winter"],
    "wake_hour": 6,
})

# 2) 作物生长:订阅跨天事件(引用常量,不写裸串)
CoreKit.bus.subscribe(CoreKit.clock.EV_DAY_CHANGED, _on_new_day)
func _on_new_day(snap: Dictionary) -> void:
    for plot in _plots:
        plot.grow_one_day()   # 读 KitDataRegistry 里的作物生长天数推进

# 3) 挂机走时:1 真实秒 = 60 游戏分钟
CoreKit.clock.set_time_scale(60.0)
CoreKit.clock.resume()

# 4) 睡觉跳到次日清晨
CoreKit.clock.sleep_to_next_day()

# 5) 存/读档
var save := {"clock": CoreKit.clock.to_dict(), ...}
CoreKit.clock.from_dict(save["clock"])
```

## 注意事项

- **默认起始暂停**:`time_scale` 默认 0,时钟不会自己走,须 `set_time_scale(x)` + `resume()`(或用显式 `advance_*`)。这样"新游戏第一天早晨静止"是默认态。
- **自动走时靠 `_process`**:门面把 GameClock 挂在 CoreKit autoload 子树,`_process` 常驻;脱离门面 `.new()` 且不入树时不会自动走时(须手动 `advance_*` 或手动调 `_process`)。
- **JSON int→float**:`from_dict` 已用 `int()` 包裹各字段容 JSON 往返;派生字段 `season_name` 不入 `to_dict`。
- **级联以绝对分钟为中枢**:一次推进跨多级(如推进十万分钟跨年)也正确;信号从粗到细(year→season→day→hour→time)发。
- **事件命名约定**:`clock:*` 遵全 kit 的 `namespace:event` 约定,见 [event-bus](../core/event-bus.md#事件命名约定kit-级)。游戏订阅务必引用 `CoreKit.clock.EV_*` 常量。
- **`set_datetime` 夹取不发信号**:直接置位会把各字段夹到合法范围,且**不**触发级联 signal/广播(用于载档/调试);要发信号请用 `advance_*`。
