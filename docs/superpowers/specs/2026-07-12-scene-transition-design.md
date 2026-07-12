# 场景转场设计(KitTransition,可复用转场资源)

> 阶段4 补缺库 4/4(收官)。对标 [EasyTransition](https://github.com/IUXGames/EasyTransition)。把 `SceneManager` 里写死的 `enum Transition { NONE, FADE }` + `_fade_to` 泛化成**数据驱动、可复用、可扩展**的转场体系:新增 off-facade 的 `KitTransition`(`extends Resource`),`change_scene` 消费它,首版落地 FADE + SLIDE 两类转场。

**版本:** v0.12.0(承 rebind UI v0.11.0)

## 目标

给用 core-kit 的游戏一个**可复用的场景转场定义**:`KitTransition` 资源描述「用什么遮罩动画覆盖 → 换场景 → 揭开」一次场景替换,`.new()` 现造或存成 `.tres` 资产 `@export` 复用。`SceneManager.change_scene` 接受它,把过渡从写死的枚举分支变成读资源字段的通用播放器。首版两类:**FADE**(遮罩淡入淡出,现有能力泛化)、**SLIDE**(全屏色板按方向驶入覆盖 / 驶出揭开)。缓动经 `Tween.EaseType`/`TransitionType` 字段可配。

## 非目标(YAGNI v1)

- **通用补间 / 缓动库**:不封装 Godot 内建 `Tween`(它已够强),不做 `tween_to` 之类便捷 API。缓动仅作为转场的曲线字段存在。
- **屏幕震动 / juice**:screen shake 抖的是相机/视口,与转场遮罩正交,不在本项;要的话本轮后单列。
- **shader / 遮罩纹理转场**(圆形擦除、溶解等):首版遮罩用纯色 `ColorRect` + `position`/`modulate` 动画,纯 GDScript、无 `.gdshader`、Web 安全。shader 转场留待有真实需求再扩(`KitTransition` 已留 `type` 枚举扩展位)。
- **场景栈 / 转场队列**:同 SceneManager v1,仍是「仅替换、拒重入」。
- **单程转场(只 COVER 或只 UNCOVER)**:v1 转场恒为「覆盖→换→揭开」对称两段;单程语义留待需求。

## 架构 / 定位

新增 **off-facade 类库目录** `addons/godot-core-kit/transitions/`(与 `state_machine/`、`di/`、`ui/` 同为不挂门面的 `class_name` 类库)。`KitTransition extends Resource`——它是**数据**,由已在门面上的 `SceneManager`(`CoreKit.scenes`)消费。**不接门面、不改 12 子系统计数**,`core_kit.gd` 仅 bump `VERSION`。命名沿用 `Kit` 前缀。

依赖纪律:`KitTransition` 零依赖(纯 Resource + 纯几何/校验方法,不引 `CoreKit`);故可脱离门面 headless 断言。`SceneManager` 消费它,遮罩驱动仍在 `SceneManager` 内(碰视口/场景树,不做 headless 断言,同现状)。

**向后兼容是硬约束**:现有 `change_scene(target, {"transition": Transition.FADE, ...})` 的 Dictionary/enum 路径 100% 保留;`test_scene_manager.gd` 现有 13 条断言(含 `_merge_options`/`Transition.NONE|FADE`)不动。

## 组件

### a. `KitTransition`(`transitions/kit_transition.gd`,`class_name KitTransition extends Resource`)

数据驱动的转场定义。纯逻辑(校验 + 几何)无副作用、可 headless 断言;不驱动任何节点。

```gdscript
class_name KitTransition
extends Resource

enum Type { NONE, FADE, SLIDE }
enum Dir { LEFT, RIGHT, UP, DOWN }   # SLIDE 时遮罩色板"驶入"的方向

@export var type: Type = Type.FADE
@export var direction: Dir = Dir.LEFT
@export var duration: float = 0.3
@export var color: Color = Color.BLACK
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var trans_type: Tween.TransitionType = Tween.TRANS_LINEAR
```

| 成员 | 说明 |
|---|---|
| `is_none() -> bool` | `type == Type.NONE`。 |
| `normalized() -> KitTransition` | 返回**校验后的副本**(`duplicate()`):`duration` 夹到 `>= 0.0`、越界 `type`/`direction` 回默认(`FADE`/`LEFT`)。**不改原资产**(保 `.tres` 共享安全)。 |
| `slide_cover_from(viewport_size: Vector2) -> Vector2` | SLIDE 覆盖段色板起点(终点恒 `Vector2.ZERO`)。按 `direction`:`LEFT`→`(+W,0)`、`RIGHT`→`(-W,0)`、`UP`→`(0,+H)`、`DOWN`→`(0,-H)`。 |
| `slide_reveal_to(viewport_size: Vector2) -> Vector2` | SLIDE 揭开段色板终点(起点恒 `Vector2.ZERO`)。按 `direction` 同向续行:`LEFT`→`(-W,0)`、`RIGHT`→`(+W,0)`、`UP`→`(0,-H)`、`DOWN`→`(0,+H)`。 |

- `normalized()` 实现:`var t: KitTransition = duplicate()`;`if t.type < Type.NONE or t.type > Type.SLIDE: t.type = Type.FADE`;`if t.direction < Dir.LEFT or t.direction > Dir.DOWN: t.direction = Dir.LEFT`;`if t.duration < 0.0: t.duration = 0.0`;`return t`。
- SLIDE 几何语义:`direction` = 色板**运动方向**,整段转场色板朝同一方向单向掠过 —— COVER 从对侧边缘外驶入盖住全屏(终点 ZERO),REVEAL 续同向驶出(起点 ZERO)。四向对称。
- `ease_type`/`trans_type` 默认 `EASE_IN_OUT` + `TRANS_LINEAR` = **现有 fade 手感**(Godot Tween 默认),故 legacy fade 视觉零变化;用户可显式设 `TRANS_SINE` 等。

### b. `SceneManager` 改造(`systems/scene_manager.gd`)

- **`change_scene(target, transition = {})`**:第 2 参由 `options: Dictionary` 改为**无类型 `transition`**(默认 `{}`),接受 `KitTransition` 或 legacy `Dictionary`。语义不变(协程、可 await、拒重入)。
- **新增 `_resolve_transition(arg) -> KitTransition`**(纯逻辑接缝,不碰场景树):

```gdscript
## 把 change_scene 第 2 参归一为 KitTransition。KitTransition→normalized();
## Dictionary→复用现有 _merge_options 映射(legacy 路径);其余(含默认 {} 之外的类型)→NONE。
func _resolve_transition(arg) -> KitTransition:
	if arg is KitTransition:
		return arg.normalized()
	var t := KitTransition.new()
	if arg is Dictionary:
		var opts := _merge_options(arg)
		t.type = _legacy_transition_to_type(opts["transition"])
		t.duration = opts["duration"]
		t.color = opts["color"]
	else:
		t.type = KitTransition.Type.NONE
	return t.normalized()

## legacy Transition 枚举 → KitTransition.Type(FADE→FADE,其余→NONE;SLIDE 仅 KitTransition 可达)。
func _legacy_transition_to_type(legacy: int) -> int:
	match legacy:
		Transition.FADE:
			return KitTransition.Type.FADE
		_:
			return KitTransition.Type.NONE
```

- **`_merge_options` / `enum Transition { NONE, FADE }` / `DEFAULT_FADE_*` 常量保留原样**(legacy Dictionary API + 现有测试仍用)。空 `{}` 经 `_merge_options` → NONE,back-compat。
- **`_fade_to` 泛化为 `_play_transition(t: KitTransition, phase: int)`**(碰视口/场景树,运行时驱动,不做 headless 断言),`enum _Phase { COVER, REVEAL }`:

```gdscript
enum _Phase { COVER, REVEAL }

## 按 t.type 驱动常驻遮罩色板演一段(COVER 覆盖 / REVEAL 揭开)。NONE 空操作。
func _play_transition(t: KitTransition, phase: int) -> void:
	match t.type:
		KitTransition.Type.FADE:
			_fade_rect.color = Color(t.color.r, t.color.g, t.color.b, 1.0)
			if phase == _Phase.COVER:
				_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
				_fade_rect.position = Vector2.ZERO
				_fade_rect.modulate.a = 0.0
			var target_a: float = 1.0 if phase == _Phase.COVER else 0.0
			var tw := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tw.tween_property(_fade_rect, "modulate:a", target_a, t.duration)
			await tw.finished
		KitTransition.Type.SLIDE:
			var size := _overlay_size()
			_fade_rect.color = Color(t.color.r, t.color.g, t.color.b, 1.0)
			_fade_rect.modulate.a = 1.0
			_fade_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_fade_rect.size = size
			var from_pos: Vector2 = t.slide_cover_from(size) if phase == _Phase.COVER else Vector2.ZERO
			var to_pos: Vector2 = Vector2.ZERO if phase == _Phase.COVER else t.slide_reveal_to(size)
			_fade_rect.position = from_pos
			var tw := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tw.tween_property(_fade_rect, "position", to_pos, t.duration)
			await tw.finished
		_:
			pass

## 遮罩尺寸 = 当前视口可见矩形;无视口时回退 1080p(仅运行时用)。
func _overlay_size() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		return vp.get_visible_rect().size
	return Vector2(1920, 1080)
```

- **`change_scene` 本体**改用 `_resolve_transition` + `_play_transition`:

```gdscript
var t := _resolve_transition(transition)
var animated: bool = t.type != KitTransition.Type.NONE
_is_changing = true
scene_changing.emit(target_path)
if animated:
	_ensure_fade_overlay()
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _play_transition(t, _Phase.COVER)
# ... 加载失败:if animated: await _play_transition(t, _Phase.REVEAL); _fade_rect.mouse_filter = IGNORE ...
# ... await get_tree().process_frame; 换树 ...
if animated:
	await _play_transition(t, _Phase.REVEAL)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
_is_changing = false
scene_changed.emit(target_path, new_scene)
```

每次 COVER 都完整重置遮罩起始态(FADE:全屏锚点 + `a=0`;SLIDE:top-left 锚点 + `size` + `a=1` + 起点),故上一次转场遗留的遮罩态(如 SLIDE 结束停在屏外)不影响下一次。

## 数据流

`change_scene(target, transition)` → `_resolve_transition` 归一为 `KitTransition` → 校验 target → `scene_changing` → (animated) COVER 遮罩覆盖 + `mouse_filter=STOP` → `load()` → `await process_frame` → 换树 → (animated) REVEAL 揭开 + `mouse_filter=IGNORE` → `scene_changed`。加载失败:已覆盖则先 REVEAL 收回遮罩、复位 `mouse_filter`,再 `scene_change_failed`。

## 错误处理

- 第 2 参非法类型(非 `KitTransition`/`Dictionary`)→ `_resolve_transition` 归 NONE(无过渡直切),不崩。
- `KitTransition` 字段越界(负 duration、坏枚举)→ `normalized()` 兜底夹取。
- 加载失败 / 重入拒绝 / target 非法:沿用现有 `scene_change_failed` + `CoreKit.log` 路径,遮罩若已覆盖则收回。

## 测试(headless)

### 新 `test/test_transition.gd`(纯逻辑,`load()` KitTransition,不碰场景树)

1. **默认值**:`type==FADE`、`duration==0.3`、`color==BLACK`、`direction==LEFT`、`ease_type==EASE_IN_OUT`、`trans_type==TRANS_LINEAR`。
2. **`is_none`**:FADE 实例 `is_none()==false`;`type=NONE` 实例 `==true`。
3. **`normalized()` 夹取 + 副本语义**:`duration=-5` 的实例 `normalized().duration==0.0`,且**原实例 `duration` 仍 `-5`**(未被改);越界 `type=999` → `normalized().type==FADE`。
4. **SLIDE 四向几何**(`size=Vector2(800,600)`):`LEFT` cover_from`(800,0)`/reveal_to`(-800,0)`;`RIGHT` `(-800,0)`/`(800,0)`;`UP` `(0,600)`/`(0,-600)`;`DOWN` `(0,-600)`/`(0,600)`。

### `test/test_scene_manager.gd`(**加** 3 条,tests 1–13 不动)

14. `_resolve_transition({})` → `KitTransition.Type.NONE`。
15. `_resolve_transition({"transition": Transition.FADE, "duration": 1.5})` → `type==FADE`、`duration==1.5`。
16. `_resolve_transition(<KitTransition SLIDE, duration=-2>)` → `type==SLIDE`、`duration==0.0`(passthrough + normalized)。

裸 `SceneManagerScript.new()`(不 add_child)即可测 `_resolve_transition`(纯逻辑);`KitTransition` 经 `load()` 取脚本。

## 收尾件

- 新 `transitions/kit_transition.gd`(+`.gd.uid`);新 `test/test_transition.gd`(+`.uid`)。
- `systems/scene_manager.gd`:`change_scene` 第 2 参泛化、增 `_resolve_transition`/`_legacy_transition_to_type`/`_play_transition`/`_overlay_size`/`enum _Phase`,`_fade_to` 移除;保留 `enum Transition`/`_merge_options`/`DEFAULT_FADE_*`。
- `test/test_scene_manager.gd`:补 14–16。
- 新 `docs/transitions/kit-transition.md`(五段式);`docs/systems/scene-manager.md` 更新 `change_scene` 签名说明 + 加转场段指路 KitTransition + 记 SLIDE;`docs/README.md` 加「### transitions/ —— 可复用转场资源」段 + 行;`docs/architecture.md` 目录布局加 `transitions/`、依赖纪律注(`KitTransition`(数据/零依赖)← `SceneManager` 消费)、版本、测试数(16→17);根 `README.md` 表加行 + 版本 0.12.0 条目;`plugin.cfg` version 0.12.0 + description。
- `demo/demo.gd`:构造 SLIDE `KitTransition` + 纯几何 marker(`Transition: type=SLIDE none=false slide_cover_from=(800, 0)`,**不真切场景**,headless 确定性);`test/run_all.ps1` 加 `test_transition`(测试文件 16→17)+ demo marker `Transition: type=SLIDE none=false` + 计数。
- **不改** `core_kit.gd` 的子系统构造/接线(off-facade,12 子系统计数不变),仅 `VERSION` → `"0.12.0"`;`test/test_core_kit.gd` 版本断言 → `"0.12.0"`。

## 我替你拍的默认(实现时若无异议即照此)

`transitions/` 新目录 + `Kit` 前缀 · `KitTransition extends Resource`(可存 .tres)· 首版 FADE + SLIDE 两类 · SLIDE `direction`=色板运动方向、对称两段 · `ease/trans` 默认 = 现有 fade 手感(legacy 零变化)· `normalized()` 返副本不改原 · legacy Dictionary/enum 路径 100% 保留 · 遮罩纯色 ColorRect 无 shader · 版本 0.12.0 · off-facade 不接门面。
