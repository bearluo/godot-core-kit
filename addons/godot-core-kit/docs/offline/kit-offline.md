# KitOffline —— 离线结算器

> `class_name KitOffline`(off-facade 类库) · `offline/kit_offline.gd` · `extends RefCounted`

## 职责

放置 / 挂机类游戏「关掉进程期间应补收益」的**纯函数**计算。给定上次在线墙钟、当前墙钟、每秒产率、封顶秒数,算离线应补收益,并检测系统时间回拨(玩家改系统时间刷收益)。**off-facade 静态类**——游戏在读档时调 `KitOffline.settle(...)` 拿一个收益数据包,自行入账 + 弹回归窗。恒定产率模型:离线期间无玩家操作、产率不变,故 `elapsed × rate` 即精确解;让「在线每秒产出」与本函数同用一个产率,离线补偿即与在线连续产出一致(「离线 1h ≈ 在线 1h」)。

## 公开 API

```gdscript
static func settle(last_seen: float, now: float, rate_per_sec: float,
                   cap_seconds := 28800.0) -> Dictionary
# 返回 { earned, elapsed, capped, rolled_back }:
#   earned      本次应补收益(elapsed × rate;rate<=0 时为 0)
#   elapsed     实际计入的秒数(min(墙钟差, cap))
#   capped      墙钟差是否超过封顶(true = 有收益被截断)
#   rolled_back 是否检测到时间回拨(now < last_seen;此时 earned=0)
```

## 依赖

零依赖(仅用引擎 `minf`,不挂门面、不 `preload` 任何子系统)。不参与存档——调用方自行持久化 `last_seen` 时间戳。

## 用法示例

```gdscript
# 读档时结算离线收益(last_seen 从存档里取,退出/自动存时写入)
func load_game() -> void:
    var d := CoreKit.saves.load("slot1")
    _apply_state(d)
    var now := Time.get_unix_time_from_system()
    var rep := KitOffline.settle(float(d.get("last_seen", 0.0)), now, _production_rate())
    if rep.earned > 0.0:
        currency.add(rep.earned)
        _show_welcome_back(rep)   # 「离线 %d 分钟,自动攒了 %s」

# 存档时盖上墙钟时间戳
func to_dict() -> Dictionary:
    return {"gold": currency.get_amount(), "last_seen": Time.get_unix_time_from_system()}
```

## 注意事项

- **墙钟,不是游戏时钟**:用 `Time.get_unix_time_from_system()`(进程退出照走);别用 `CoreKit.clock`——那是可暂停 / 可加速的游戏内日历,进程退出不推进、无防作弊语义。
- **时间回拨按 0**:`now < last_seen`(玩家把系统时间往回拨)→ `earned=0`、`rolled_back=true`。调用方可据此提示或静默跳过;不做「前拨」封顶之外的额外惩罚。
- **封顶**:默认 8 小时(`DEFAULT_CAP_SECONDS`),`cap_seconds<=0` 时回落默认;超封顶部分不计,`capped=true` 供 UI 提示「离线收益已封顶」。
- **恒定产率**:本函数假设离线窗口内产率不变(进程关闭本就无法变)。若要**在线**追赶多段产率(升级边界分段积分),那是另一套逻辑,本类不覆盖(YAGNI,尚无消费方)。
- **产率的确定性**:传入的 `rate_per_sec` 应是**期望产出**(确定性),别把带随机性的单次产出直接外推——让在线自动产出也用同一期望率,离线 / 在线才连续一致。
