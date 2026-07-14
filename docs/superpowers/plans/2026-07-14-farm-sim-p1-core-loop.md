# farm-sim P1 · 核心循环成型（vertical slice 收口）实现计划

> 设计 spec：`docs/superpowers/specs/2026-07-14-farm-sim-game-design.md`
> 前置：P0 视觉切片已完成（走动/耕种浇收/逐日生长/HUD）。
> **For agentic workers：** 逐 task 实现；逻辑 task 用 headless 断言 + world FARM_SMOKE 自测,
> UI task 用 headless 无报错 + 编辑器 F5 手动验；绿了再提交。

**Goal（P1 done）：** 一个完整"日循环"闭环——体力约束下耕作、睡觉进天、多作物选种、
背包界面查看、商店买卖、菜单存/读档,反复可玩。

**Architecture：** 延续 P0 逻辑/表现分离。体力/选种是 world 侧状态;背包/商店/存档 UI 用
`Control` 面板 + `KitUiStack`（挂 `CoreKit.layers` 的 window/modal 层）入出栈;存档经
`CoreKit.saves` 全量往返（新增 `FarmGrid.to_dict/from_dict`）。UI 占位（半透明底 + Label/
键盘驱动),P5 换真素材。

## Global Constraints

- 游戏代码留 `example/farm-sim` 分支,不合 main、不升 kit 版本;不破坏现有 dogfood 与 P0。
- Tab 缩进;游戏脚本不加 class_name;无类型注入对象**别用 `:=`**（已反复踩坑）。
- 验收:逻辑 task headless 断言/自测通过;`FARM_SMOKE=1` world 自测仍 PASS;
  `run_all` 仍 FAILS=0;UI task 编辑器 F5 手动验。
- 新增输入动作(背包/商店/菜单/选种切换/睡觉)加进 project.godot `[input]`。

---

### Task 1：体力系统 + 睡觉进天

**Files:** Modify `world.gd`、`hud.gd`;可选新增输入 `sleep`（复用 `farm_next_day` 语义为"睡觉"）。

- [ ] world 加 `_energy`/`_energy_max`（如 100）;每次成功工具动作扣体力（耕/种/浇/收各扣如 2）。
- [ ] 体力不足以支付某动作 → 该动作不执行 + 日志提示。体力降到 0 → 自动睡觉。
- [ ] `farm_next_day`（N）语义改为**睡觉**：`clock.advance_day()` + 体力回满。
- [ ] HUD 体力显示真实 `_energy/_energy_max`（world 注入/HUD 每帧读）。
- [ ] 扩展 `_run_smoke`：断言工具动作扣体力、睡觉回满。
- [ ] 验收：`FARM_SMOKE=1` 自测 PASS；F5 手动看体力随操作下降、睡觉回满、日期+1。

### Task 2：FarmGrid 存档序列化（to_dict/from_dict）

**Files:** Modify `examples/farm-sim/farm_grid.gd`;Create `test/test_farm_grid_save.gd`。

- [ ] `to_dict()`：序列化 `_state`（Vector2i→int）与 `_crop`（Vector2i→{id,stage}）。键用可 JSON 化形式（如 `"x,y"` 字符串）,`id` 存 `String(id)`。
- [ ] `from_dict(d)`：还原;键解析回 Vector2i,`id` 归一回 `StringName`（JSON 往返坑,见 dogfood）。
- [ ] `test_farm_grid_save.gd`：耕+种+浇若干格 → `to_dict` → 新 grid `from_dict` → 断言状态/作物/stage 完全一致（含经 `JSON.stringify/parse` 往返模拟存档）。
- [ ] 验收：test ALL PASS。

### Task 3：多作物 + 选种切换

**Files:** Create 第 3 种作物 `data/crops/*.tres` + 种子/产物 `data/items/*.tres`;Modify `world.gd`、`hud.gd`;新增输入 `cycle_seed`。

- [ ] 加第 3 种作物（如 potato，grow_days=6，价格不同),配套 seed/harvest item 定义（价格数据驱动）。
- [ ] world 维护可选作物列表（`registry.ids(&"crop", true)`）;`cycle_seed`（如 Tab）循环 `_selected_crop`。
- [ ] HUD 显示当前选中种子名（经 registry 展示名）。
- [ ] 验收：`FARM_SMOKE`/F5 验证能切换并种下不同作物、生长期不同。

### Task 4：背包界面（KitUiStack）

**Files:** Create `examples/farm-sim/inventory_panel.gd`;Modify `world.gd`;新增输入 `toggle_inventory`。

- [ ] `inventory_panel.gd`（Control）：半透明底 + 标题 + `bag.totals()` 逐项"展示名 × 数量"（字母序,复用 `KitInventory.totals` + registry 展示名）。
- [ ] world 建一个 `KitUiStack`,`CoreKit.layers.mount(stack, "window")`;`toggle_inventory`（如 I）→ 栈空则 push 背包面板、否则 pop。
- [ ] 验收：headless 无报错;F5 按 I 开/关背包,内容随种/收变化。

### Task 5：商店界面（买 / 卖）

**Files:** Create `examples/farm-sim/shop_panel.gd`;Modify `world.gd`;新增输入 `toggle_shop`。

- [ ] `shop_panel.gd`（Control）：列可购种子（`buy_price`)与可售产物（`sell_price`)+ 当前金币;键盘驱动占位交互——数字键 1..N 买 1 个对应种子;一个键"卖光背包里的产物"。交易走 `shop.buy/sell`（已广播 `shop:` 事件）。
- [ ] world `toggle_shop`（如 P）经 `KitUiStack` push/pop 商店面板（同栈或独立栈,挂 window/modal 层）。
- [ ] 验收：headless 无报错;F5 开商店买种子（金币减、背包加）、卖收成（金币加）。

### Task 6：存档 / 读档菜单

**Files:** Create `examples/farm-sim/pause_menu.gd`;Modify `world.gd`;新增输入 `toggle_menu`。

- [ ] world `save_game()`：`CoreKit.saves.save("farm", {grid: _grid.to_dict(), bag: _bag.to_dict(), gold: _shop.gold, clock: CoreKit.clock.to_dict(), energy: _energy})`;`load_game()`：读回并全量还原（含 `_grid.from_dict` + `_view.queue_redraw()`）。
- [ ] `pause_menu.gd`（Control）：`toggle_menu`（Esc）开菜单,键选 存档 / 读档 / 继续;经 `KitUiStack` 挂 modal 层。
- [ ] 验收：headless smoke 加"存 → 变 → 读 → 复原"断言;F5 存档→耕几格/推几天→读档→回存档点。

---

## P1 完成后

- 勾选 spec 里 P1 checklist;提交（游戏代码留分支）。
- 至此 P0+P1 = vertical slice：完整日循环立住。进 P2（四季/天气可见/工具升级/任务成就 UI/i18n/audio）前另出 plan。
- 若暴露 kit 缺口,按分支分流剥到 main 走 kit SDD。
