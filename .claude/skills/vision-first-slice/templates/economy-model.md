# 经济曲线先行(idle / incremental)

放置类的「好玩」= 一条数值曲线。**先在表里把曲线调爽,再写引擎代码。** 别把经济直接写进 GDScript 靠 smoke test 猜——那样你看不见曲线,而曲线就是游戏本身。

## 最小列(一张表 / CSV 即可)

| level | cost | rate(产/秒) | 累计产出 | time_to_next(秒) | 备注 |
|---|---|---|---|---|---|
| 1 | 10 | 1.0 | … | … | 第一个正反馈 |
| … | | | | | |

关键盯 `time_to_next` 这一列的**节奏**:早期几秒一个正反馈,中期几十秒~几分钟,后期靠 prestige/倍率重置节奏。盯着它调,直到「等待感」符合愿景里的爽点。

## 先验的问题

- 第一个正反馈多久出现?(通常 < 10 秒)
- 「再等一下就能买下一个」的钩子,在每一级都成立吗?
- prestige / 重置后,重跑前段是「快进爽」还是「重复烦」?
- 有没有某一级卡成长墙(time_to_next 突然跳几个数量级)?

## 一次性算曲线(不建引擎,先看数)

用 GDScript headless 或 Python 打印曲线,肉眼扫 `time_to_next`:

```gdscript
# calc_curve.gd —— godot --headless -s calc_curve.gd
extends SceneTree
func _initialize() -> void:
	var base_cost := 10.0
	var growth := 1.15      # 每级成本增长率
	var base_rate := 1.0
	var owned_rate := 0.0
	for level in range(1, 31):
		var cost := base_cost * pow(growth, level - 1)
		owned_rate += base_rate
		var ttn := cost / owned_rate      # 粗略:攒下一级要多久
		print("L%02d cost=%.1f rate=%.1f ttn=%.1fs" % [level, cost, owned_rate, ttn])
	quit(0)
```

调 `growth` / `base_rate` 到 `ttn` 节奏符合愿景,再把这组参数带进引擎。改一个数、重跑、扫一眼——比在引擎里改代码快一个数量级。
