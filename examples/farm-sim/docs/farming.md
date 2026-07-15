# 种田循环

农场的核心咬合:**耕 → 种 → 浇 → 等长 → 收 → 卖**,受体力、季节、天气约束。

## 网格模型 `systems/farm_grid.gd`

纯逻辑、headless 可测(`test/test_farm_grid*.gd`)。`GRID_W=10 × GRID_H=8` 格,每格一个状态:

| 状态 | 含义 |
|---|---|
| `EMPTY` | 空地,可耕 |
| `TILLED` | 已耕,可种 / 可浇 |
| `WATERED` | 已浇(生长更快) |
| 有作物 | 记 `crop_id` + 已长天数,`crop_mature` 判成熟 |

关键 API:`till(cell)` / `plant(cell, crop, season)` / `water(cell)` / `harvest(cell)` / `tile_state(cell)` / `has_crop(cell)` / `crop_mature(cell)` / `advance_day(bonus)` / `crop_plantable(crop, season)` / `cell_valid(cell)` / `to_dict`·`from_dict`。

## 工具派发 `Farm.use_tool_on(cell)`

一个动作键 `J` 按格状态自动派发,成功则扣体力 + 播 SFX + 发 `grid_changed` + `fx_requested`:

```
有成熟作物      → 收获(harvest)
有未熟作物      → 浇水(water)
空地(EMPTY)    → 耕地(till)
已耕(TILLED)   → 播种当前选中种子;不当季则提示;已种过则浇水
```

**model/view 分离**:`use_tool_on` 吃传入格(facing 由区域 `_on_use` 用 `player.facing_cell()` 算),不依赖具体 player 节点——故 headless smoke 能直接调它跑完整循环。

## 作物 `defs/crop_def.gd` + `data/crops/*.tres`

字段:`id` / `display_name` / `grow_days` / `harvest_amount` / `seed_item` / `harvest_item` / `seasons`(空=全季)。经 `KitDataRegistry` 载入(`registry.load_dir(&"crop", ...)`)。

5 种作物的数值曲线见 [economy.md](economy.md)。选种子:`Q` 键 `Farm.cycle_seed()` 轮换,HUD 显示当前选中。

## 体力

- `ENERGY_MAX = 100`,每个工具动作耗 `ACTION_COST = 8`(≈ 12 动作/天)。
- `N` 睡觉 `Farm.sleep()`:推进一天(经天气链生长)+ 体力回满。
- 体力耗尽自动睡(`use_tool_on` 里 `_energy == 0 → sleep()`)。

## 季节

`CoreKit.clock` 提供季节(默认每季数天)。作物 `seasons` 字段 + `FarmGrid.crop_plantable` 做**季节门**:南瓜 `seasons=[fall]` 只能秋季种,别的季节播种被拒并提示。`test/test_farm_season.gd` 覆盖。

> 注意:正常游玩时 `clock.hour()` 恒 6:00(`time_scale=0` 暂停,`advance_day` 保持钟点),推进靠睡觉整天跳。

## 天气(事件链)

`systems/weather_system.gd` 订阅 `clock:day_changed`、固定种子 RNG 掷晴/雨、广播 `weather:changed{day, kind, growth_bonus}`。农田模型按 `growth_bonus` 加速生长(雨天 +1)。农田区挂一层 `scenes/weather_view.gd`(layer=1 CanvasLayer)画雨幕。

事件链:`clock:day_changed → weather:changed → 生长`,每级只认上一级、彼此不 `preload`——dogfood `CoreKit.bus` 作管道。天气瞬态不入档(读档只回滚时钟,RNG 继续)。

## 水壶升级(3×3 浇水)

`Farm.buy_water_upgrade()`:花 `WATER_UPGRADE_COST = 200` 金币把浇水从单格升为 3×3 区域(`_water_radius` 0→1)。随存档保存。中期里程碑(≈ 4 株防风草 1.6 天回本)。
