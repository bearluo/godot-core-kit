# 场景转场(KitTransition)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 按任务逐个实现。步骤用 `- [ ]` 勾选跟踪。

**Goal:** 把 SceneManager 写死的 fade 泛化成数据驱动、可复用的 `KitTransition`(extends Resource,off-facade),`change_scene` 兼容接收它或 legacy Dictionary,首版落地 FADE + SLIDE 两类转场。

**Architecture:** 新增 off-facade 类库 `transitions/kit_transition.gd`(`class_name KitTransition extends Resource`,纯数据 + 纯几何/校验方法,零依赖、headless 可测)。`SceneManager`(已在门面)新增 `_resolve_transition` 归一参数、`_play_transition` 通用遮罩播放器,取代 `_fade_to`;`_merge_options`/`enum Transition`/`DEFAULT_FADE_*` legacy 路径 100% 保留。`core_kit.gd` 仅 bump VERSION,不改子系统计数/接线。

**Tech Stack:** Godot 4.7-stable-mono,GDScript;headless 测试 `extends SceneTree`;纯色 `ColorRect` 遮罩 + `Tween`(无 shader、无 .tscn、Web 安全)。

## Global Constraints

- **版本 v0.12.0**,`plugin.cfg` 与 `CoreKit.VERSION` 同源。
- **off-facade**:`KitTransition` 不挂门面、不计入 12 子系统;`core_kit.gd` 仅改 `VERSION` 常量,不动构造/接线;`test_core_kit.gd` 除版本断言外不改。
- **向后兼容硬约束**:`change_scene` 的 legacy Dictionary/enum 路径 100% 保留 —— `_merge_options`、`enum Transition { NONE, FADE }`、`DEFAULT_FADE_DURATION/COLOR/TRANSITION` 常量**原样不动**;`test/test_scene_manager.gd` 现有 tests 1–13 一字不改,只在 `sm.free()` 前追加。
- **KitTransition 零依赖**:不引 `CoreKit`、不碰场景树;纯逻辑(`normalized`/`slide_*`/`is_none`)可脱离门面 headless 断言。
- **缓动默认** `ease_type=EASE_IN_OUT`、`trans_type=TRANS_LINEAR`(= Godot Tween 默认 = 现有 fade 手感,legacy 视觉零变化)。
- **纯 GDScript**:遮罩用纯色 `ColorRect`,无 `.gdshader`/`.tscn`。
- **headless 测试范式**:`extends SceneTree`、`_initialize()`、数 `failures`、打印 `test_X: ALL PASS`+`quit(0)` 或 `N FAILURE(S)`+`quit(1)`;引用其它脚本用 `load()`(class_name 全局标识符在 `-s` 下由 --import 缓存供给,但 autoload `CoreKit` 须运行期 load 规避编译期时序坑)。
- **提交尾注**:每次 commit message 结尾附
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- **Godot 可执行**(控制台版,读 stdout):
  `D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`。
  单测:`& '<exe>' --headless --path . -s res://test/test_X.gd`(看 `test_X: ALL PASS` + 退出码 0)。
  生成 class 缓存:`& '<exe>' --headless --path . --import`。

---

### Task 1: KitTransition 资源(纯数据 + 纯几何/校验)

**Files:**
- Create: `addons/godot-core-kit/transitions/kit_transition.gd`
- Test: `test/test_transition.gd`

**Interfaces:**
- Produces(供 Task 2/3 消费):
  - `class_name KitTransition extends Resource`
  - `enum Type { NONE, FADE, SLIDE }`、`enum Dir { LEFT, RIGHT, UP, DOWN }`
  - `@export var type: Type`(默认 FADE)、`direction: Dir`(LEFT)、`duration: float`(0.3)、`color: Color`(BLACK)、`ease_type: Tween.EaseType`(EASE_IN_OUT)、`trans_type: Tween.TransitionType`(TRANS_LINEAR)
  - `is_none() -> bool`
  - `normalized() -> KitTransition`(返副本,夹取)
  - `slide_cover_from(viewport_size: Vector2) -> Vector2`、`slide_reveal_to(viewport_size: Vector2) -> Vector2`

- [ ] **Step 1: 写失败测试** `test/test_transition.gd`

```gdscript
extends SceneTree
## KitTransition 纯逻辑 headless 断言(默认值 / is_none / normalized 夹取+副本 / SLIDE 四向几何)。
## KitTransition 零依赖,直接 load() 脚本实例化,不碰场景树、不经门面。
## 运行:godot --headless --path . -s res://test/test_transition.gd

var TransitionScript


func _initialize() -> void:
	TransitionScript = load("res://addons/godot-core-kit/transitions/kit_transition.gd")
	var failures := 0

	# 1. 默认值
	var t = TransitionScript.new()
	if t.type != TransitionScript.Type.FADE:
		print("FAIL 1: 默认 type 应为 FADE,得到 %s" % t.type)
		failures += 1
	if t.duration != 0.3:
		print("FAIL 1: 默认 duration 应为 0.3,得到 %s" % t.duration)
		failures += 1
	if t.color != Color.BLACK:
		print("FAIL 1: 默认 color 应为 BLACK")
		failures += 1
	if t.direction != TransitionScript.Dir.LEFT:
		print("FAIL 1: 默认 direction 应为 LEFT")
		failures += 1
	if t.ease_type != Tween.EASE_IN_OUT:
		print("FAIL 1: 默认 ease_type 应为 EASE_IN_OUT")
		failures += 1
	if t.trans_type != Tween.TRANS_LINEAR:
		print("FAIL 1: 默认 trans_type 应为 TRANS_LINEAR")
		failures += 1

	# 2. is_none
	if t.is_none():
		print("FAIL 2: FADE 实例 is_none() 应为 false")
		failures += 1
	var none_t = TransitionScript.new()
	none_t.type = TransitionScript.Type.NONE
	if not none_t.is_none():
		print("FAIL 2: NONE 实例 is_none() 应为 true")
		failures += 1

	# 3. normalized 夹取 + 副本不改原
	var bad = TransitionScript.new()
	bad.duration = -5.0
	bad.type = 999
	var fixed = bad.normalized()
	if fixed.duration != 0.0:
		print("FAIL 3: normalized duration 应夹到 0.0,得到 %s" % fixed.duration)
		failures += 1
	if fixed.type != TransitionScript.Type.FADE:
		print("FAIL 3: normalized 越界 type 应回 FADE,得到 %s" % fixed.type)
		failures += 1
	if bad.duration != -5.0:
		print("FAIL 3: normalized 不应改原实例 duration(应仍 -5.0,得到 %s)" % bad.duration)
		failures += 1

	# 4. SLIDE 四向几何(size=800x600)
	var size := Vector2(800, 600)
	var s = TransitionScript.new()
	s.type = TransitionScript.Type.SLIDE
	var cases := {
		TransitionScript.Dir.LEFT:  [Vector2(800, 0), Vector2(-800, 0)],
		TransitionScript.Dir.RIGHT: [Vector2(-800, 0), Vector2(800, 0)],
		TransitionScript.Dir.UP:    [Vector2(0, 600), Vector2(0, -600)],
		TransitionScript.Dir.DOWN:  [Vector2(0, -600), Vector2(0, 600)],
	}
	for dir in cases:
		s.direction = dir
		var expect = cases[dir]
		if s.slide_cover_from(size) != expect[0]:
			print("FAIL 4: dir=%s cover_from 应 %s,得到 %s" % [dir, expect[0], s.slide_cover_from(size)])
			failures += 1
		if s.slide_reveal_to(size) != expect[1]:
			print("FAIL 4: dir=%s reveal_to 应 %s,得到 %s" % [dir, expect[1], s.slide_reveal_to(size)])
			failures += 1

	if failures == 0:
		print("test_transition: ALL PASS")
		quit(0)
	else:
		print("test_transition: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& '<exe>' --headless --path . -s res://test/test_transition.gd`
Expected: 失败(kit_transition.gd 尚不存在,`load()` 返 null → `.new()` 报错)。

- [ ] **Step 3: 写 `addons/godot-core-kit/transitions/kit_transition.gd`**

```gdscript
class_name KitTransition
extends Resource
## 可复用场景转场定义(数据驱动,对标 EasyTransition)。描述"用什么遮罩动画覆盖→切换→揭开"
## 一次场景替换:由 SceneManager.change_scene 消费。可 .new() 现造,也可存成 .tres 资产
## @export 到 Inspector 复用。纯逻辑(校验 normalized / slide 几何)无副作用、可 headless 断言;
## 真正驱动常驻遮罩色板的活在 SceneManager 内(碰视口/场景树)。零依赖(不引 CoreKit)。

enum Type { NONE, FADE, SLIDE }
enum Dir { LEFT, RIGHT, UP, DOWN }   ## SLIDE 时遮罩色板"驶入"的方向(= 色板运动方向)

@export var type: Type = Type.FADE
@export var direction: Dir = Dir.LEFT
@export var duration: float = 0.3
@export var color: Color = Color.BLACK
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var trans_type: Tween.TransitionType = Tween.TRANS_LINEAR


## type == NONE(无过渡直切)。
func is_none() -> bool:
	return type == Type.NONE


## 返回校验后的副本:duration 夹到 >= 0、越界 type/direction 回默认(FADE/LEFT)。
## 不改原资产(保 .tres 共享安全)。
func normalized() -> KitTransition:
	var t := duplicate() as KitTransition
	if t.type < Type.NONE or t.type > Type.SLIDE:
		t.type = Type.FADE
	if t.direction < Dir.LEFT or t.direction > Dir.DOWN:
		t.direction = Dir.LEFT
	if t.duration < 0.0:
		t.duration = 0.0
	return t


## SLIDE 覆盖段:色板起点(终点恒 Vector2.ZERO)。direction = 色板运动方向,从对侧边缘外驶入。
func slide_cover_from(viewport_size: Vector2) -> Vector2:
	match direction:
		Dir.LEFT:
			return Vector2(viewport_size.x, 0.0)
		Dir.RIGHT:
			return Vector2(-viewport_size.x, 0.0)
		Dir.UP:
			return Vector2(0.0, viewport_size.y)
		Dir.DOWN:
			return Vector2(0.0, -viewport_size.y)
		_:
			return Vector2.ZERO


## SLIDE 揭开段:色板终点(起点恒 Vector2.ZERO)。同 direction 续行驶出屏外。
func slide_reveal_to(viewport_size: Vector2) -> Vector2:
	match direction:
		Dir.LEFT:
			return Vector2(-viewport_size.x, 0.0)
		Dir.RIGHT:
			return Vector2(viewport_size.x, 0.0)
		Dir.UP:
			return Vector2(0.0, -viewport_size.y)
		Dir.DOWN:
			return Vector2(0.0, viewport_size.y)
		_:
			return Vector2.ZERO
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& '<exe>' --headless --path . -s res://test/test_transition.gd`
Expected: `test_transition: ALL PASS` + 退出码 0。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/transitions/kit_transition.gd addons/godot-core-kit/transitions/kit_transition.gd.uid test/test_transition.gd test/test_transition.gd.uid
git commit -m "feat: add KitTransition reusable scene-transition resource

off-facade class_name KitTransition extends Resource(transitions/):数据驱动
转场定义(Type NONE/FADE/SLIDE + Dir + duration/color/ease/trans),纯几何
slide_cover_from/slide_reveal_to + normalized 校验副本,headless 断言全绿。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> 注:`.gd.uid` 由编辑器 --import 生成;若首次未生成,先跑一次 `--import` 再 add。

---

### Task 2: SceneManager 消费 KitTransition

**Files:**
- Modify: `addons/godot-core-kit/systems/scene_manager.gd`
- Test: `test/test_scene_manager.gd`(追加 14–16,tests 1–13 不动)

**Interfaces:**
- Consumes:`KitTransition`(Task 1,class_name;scene_manager.gd 内按 class_name 引用,`-s` 下由 --import 缓存供给)。
- Produces:`change_scene(target, transition = {})`(第 2 参接受 `KitTransition` 或 legacy Dictionary);`_resolve_transition(arg) -> KitTransition`(纯逻辑接缝)。

- [ ] **Step 1: 写失败测试**——在 `test/test_scene_manager.gd` 的 `sm.free()`(现第 105 行)之前插入:

```gdscript
	# 14. _resolve_transition({}) → KitTransition NONE(back-compat 默认无过渡)
	var KitTransitionScript = load("res://addons/godot-core-kit/transitions/kit_transition.gd")
	var rt0 = sm._resolve_transition({})
	if rt0.type != KitTransitionScript.Type.NONE:
		print("FAIL 14: _resolve_transition({}) 应为 NONE,得到 %s" % rt0.type)
		failures += 1

	# 15. _resolve_transition(legacy Dictionary FADE) → KitTransition FADE + duration 保留
	var rt1 = sm._resolve_transition({
		"transition": SceneManagerScript.Transition.FADE,
		"duration": 1.5,
	})
	if rt1.type != KitTransitionScript.Type.FADE:
		print("FAIL 15: legacy FADE 应映射 KitTransition.Type.FADE,得到 %s" % rt1.type)
		failures += 1
	if rt1.duration != 1.5:
		print("FAIL 15: legacy duration 1.5 应保留,得到 %s" % rt1.duration)
		failures += 1

	# 16. _resolve_transition(KitTransition SLIDE, duration=-2) → passthrough + normalized 夹取
	var kt = KitTransitionScript.new()
	kt.type = KitTransitionScript.Type.SLIDE
	kt.duration = -2.0
	var rt2 = sm._resolve_transition(kt)
	if rt2.type != KitTransitionScript.Type.SLIDE:
		print("FAIL 16: KitTransition SLIDE 应透传,得到 %s" % rt2.type)
		failures += 1
	if rt2.duration != 0.0:
		print("FAIL 16: 负 duration 应经 normalized 夹到 0.0,得到 %s" % rt2.duration)
		failures += 1
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& '<exe>' --headless --path . -s res://test/test_scene_manager.gd`
Expected: 失败(`_resolve_transition` 方法尚不存在)。

- [ ] **Step 3: 改 `addons/godot-core-kit/systems/scene_manager.gd`**(四处 Edit,逐字精确)

**Edit A —— 加 `_Phase` 枚举。** 找:
```gdscript
enum Transition { NONE, FADE }

const DEFAULT_TRANSITION := Transition.NONE
```
换成:
```gdscript
enum Transition { NONE, FADE }  # legacy Dictionary API 用;KitTransition.Type 为新规范
enum _Phase { COVER, REVEAL }

const DEFAULT_TRANSITION := Transition.NONE
```

**Edit B —— 重写 `change_scene` 本体。** 找从 `func change_scene(target, options: Dictionary = {}) -> void:` 起到该函数结尾 `scene_changed.emit(target_path, new_scene)` 的整段(现第 42–94 行),整体替换为:
```gdscript
## 把当前活动场景替换为 target。target 为 res:// 路径(String)或 PackedScene。
## transition 接受 KitTransition,或 legacy options 字典({transition/duration/color},未识别键
## 静默回退默认),默认 {} = 无过渡。协程:可 fire-and-forget(靠信号感知结果),也可 await
## 原地等待切换完成。
func change_scene(target, transition = {}) -> void:
	var target_path := _resolve_target_path(target)

	if _is_changing:
		CoreKit.log.warn("SceneManager.change_scene: 拒绝重入,目标 '%s' 被忽略(当前正在切换中)" % target_path)
		scene_change_failed.emit(target_path, ERR_BUSY)
		return

	var validation := _validate_target(target)
	if validation != OK:
		CoreKit.log.error("SceneManager.change_scene: 非法 target '%s'" % target_path)
		scene_change_failed.emit(target_path, ERR_INVALID_PARAMETER)
		return

	var t := _resolve_transition(transition)
	var animated: bool = t.type != KitTransition.Type.NONE

	_is_changing = true
	scene_changing.emit(target_path)

	if animated:
		_ensure_fade_overlay()
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		await _play_transition(t, _Phase.COVER)

	var packed_scene := _load_packed_scene(target)
	if packed_scene == null:
		CoreKit.log.error("SceneManager.change_scene: 加载失败 '%s'" % target_path)
		if animated:
			await _play_transition(t, _Phase.REVEAL)
			_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_changing = false
		scene_change_failed.emit(target_path, ERR_CANT_OPEN)
		return

	# 等一帧再动树:避免在触发调用的信号回调栈内(例如按钮 pressed 冒泡途中)直接冻结/
	# 移除仍在处理事件的旧场景节点。NONE 过渡也统一走这一步,语义与内置
	# change_scene_to_* 系列的"延迟切换"保持一致。
	await get_tree().process_frame

	var new_scene := packed_scene.instantiate()
	var old_scene := get_tree().current_scene
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	if is_instance_valid(old_scene):
		old_scene.queue_free()

	if animated:
		await _play_transition(t, _Phase.REVEAL)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_is_changing = false
	scene_changed.emit(target_path, new_scene)
```

**Edit C —— 加 `_resolve_transition` + `_legacy_transition_to_type`。** 找 `_merge_options` 结尾:
```gdscript
	return {"transition": transition, "duration": duration, "color": color}
```
在其后(空一行)追加:
```gdscript


## 把 change_scene 第 2 参归一为 KitTransition(纯逻辑,不碰场景树)。KitTransition→normalized();
## Dictionary→复用 _merge_options 走 legacy 路径映射;其余类型(含非法)→NONE。
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

**Edit D —— `_fade_to` 泛化为 `_play_transition` + `_overlay_size`。** 找现有 `_fade_to`(含其上方 doc 注释,现第 195–203 行):
```gdscript
## 把遮罩的可见度 Tween 到 target_alpha。color 的 RGB 写入 ColorRect.color（alpha 归一化为
## 1.0），可见度完全由 modulate:a 驱动，避免 color.a 与 modulate.a 两个 alpha 通道相乘导致
## 淡入淡出不到位。
func _fade_to(target_alpha: float, duration: float, color: Color) -> void:
	_fade_rect.color = Color(color.r, color.g, color.b, 1.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, duration)
	await tween.finished
```
整体替换为:
```gdscript
## 按 t.type 驱动常驻遮罩色板演一段(COVER 覆盖 / REVEAL 揭开)。碰视口/场景树,运行时驱动,
## 不做 headless 断言。每次 COVER 都完整重置遮罩起始态,故上次转场遗留态不影响本次。
## FADE 走 modulate:a(色板全屏、alpha 0↔1);SLIDE 走 position(全屏不透明色板按 direction 掠过)。
func _play_transition(t: KitTransition, phase: int) -> void:
	match t.type:
		KitTransition.Type.FADE:
			_fade_rect.color = Color(t.color.r, t.color.g, t.color.b, 1.0)
			if phase == _Phase.COVER:
				_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
				_fade_rect.position = Vector2.ZERO
				_fade_rect.modulate.a = 0.0
			var target_a: float = 1.0 if phase == _Phase.COVER else 0.0
			var tween := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tween.tween_property(_fade_rect, "modulate:a", target_a, t.duration)
			await tween.finished
		KitTransition.Type.SLIDE:
			var size := _overlay_size()
			_fade_rect.color = Color(t.color.r, t.color.g, t.color.b, 1.0)
			_fade_rect.modulate.a = 1.0
			_fade_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_fade_rect.size = size
			var from_pos: Vector2 = t.slide_cover_from(size) if phase == _Phase.COVER else Vector2.ZERO
			var to_pos: Vector2 = Vector2.ZERO if phase == _Phase.COVER else t.slide_reveal_to(size)
			_fade_rect.position = from_pos
			var tween := create_tween().set_ease(t.ease_type).set_trans(t.trans_type)
			tween.tween_property(_fade_rect, "position", to_pos, t.duration)
			await tween.finished
		_:
			pass


## 遮罩尺寸 = 当前视口可见矩形;无视口时回退 1080p(仅运行时用)。
func _overlay_size() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		return vp.get_visible_rect().size
	return Vector2(1920, 1080)
```

**Edit E —— 更新类头注释(准确性)。** 找:
```gdscript
## 的协程。同步 load()（不用线程，Web 导出安全）；默认过渡 NONE，可选 FADE
## （CanvasLayer + ColorRect + Tween，常驻本节点下、不受场景替换影响）。拒绝重入
```
换成:
```gdscript
## 的协程。同步 load()（不用线程，Web 导出安全）；第 2 参接受 KitTransition（FADE/SLIDE）
## 或 legacy options 字典，默认无过渡（CanvasLayer + ColorRect + Tween 遮罩常驻本节点下、不受
## 场景替换影响）。拒绝重入
```

- [ ] **Step 4: 跑 test_scene_manager 确认通过**

Run: `& '<exe>' --headless --path . --import`(先刷新 class 缓存,确保 `KitTransition` 全局标识符可解析)
再 Run: `& '<exe>' --headless --path . -s res://test/test_scene_manager.gd`
Expected: `test_scene_manager: ALL PASS` + 退出码 0(16 条断言全绿,含新 14–16)。

- [ ] **Step 5: 提交**

```bash
git add addons/godot-core-kit/systems/scene_manager.gd test/test_scene_manager.gd
git commit -m "feat: SceneManager consumes KitTransition (FADE + SLIDE), keep legacy path

change_scene 第 2 参泛化为接受 KitTransition 或 legacy Dictionary;_resolve_transition
归一 + _play_transition 通用遮罩播放器(FADE=modulate,SLIDE=position)取代 _fade_to;
_merge_options/enum Transition/DEFAULT_FADE_* legacy 路径 100% 保留。test_scene_manager
补 14-16(_resolve_transition),1-13 不动。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 版本 + 文档 + demo + run_all(off-facade 收尾)

**Files:**
- Modify: `addons/godot-core-kit/core_kit.gd`、`test/test_core_kit.gd`、`addons/godot-core-kit/plugin.cfg`
- Create: `addons/godot-core-kit/docs/transitions/kit-transition.md`
- Modify: `addons/godot-core-kit/docs/systems/scene-manager.md`、`addons/godot-core-kit/docs/README.md`、`addons/godot-core-kit/docs/architecture.md`、`README.md`
- Modify: `demo/demo.gd`、`test/run_all.ps1`

**Interfaces:** 消费 Task 1/2 的 `KitTransition` + `change_scene`。无新代码接口。

- [ ] **Step 1: 版本三处同源 + 门面版本断言**

`addons/godot-core-kit/core_kit.gd` 第 13 行:`const VERSION := "0.11.0"` → `const VERSION := "0.12.0"`。

`test/test_core_kit.gd`:
```gdscript
	if kit.VERSION != "0.11.0":
		print("FAIL 1: VERSION 应为 0.11.0,实际 %s" % kit.VERSION)
```
→
```gdscript
	if kit.VERSION != "0.12.0":
		print("FAIL 1: VERSION 应为 0.12.0,实际 %s" % kit.VERSION)
```

`addons/godot-core-kit/plugin.cfg`:`version="0.11.0"` → `version="0.12.0"`;`description` 末尾(闭引号前)追加:
`;0.12.0 新增 off-facade 可复用转场资源 KitTransition(transitions/,extends Resource):FADE + SLIDE 两类,change_scene 兼容接收 KitTransition 或 legacy 字典`

- [ ] **Step 2: 新建 `addons/godot-core-kit/docs/transitions/kit-transition.md`**(五段式)

```markdown
# KitTransition —— 可复用场景转场资源

> `class_name KitTransition`(off-facade,`extends Resource`)· `transitions/kit_transition.gd` · 由 `CoreKit.scenes.change_scene` 消费

## 职责

数据驱动的场景转场定义,对标 EasyTransition。描述「用什么遮罩动画覆盖 → 换场景 → 揭开」一次场景替换。`.new()` 现造或存成 `.tres` 资产 `@export` 到 Inspector 复用。首版两类:**FADE**(遮罩淡入淡出)、**SLIDE**(全屏色板按方向驶入覆盖 / 驶出揭开)。`SceneManager` 读它的字段驱动常驻遮罩,不再写死 fade 分支。

## 公开 API

```gdscript
enum Type { NONE, FADE, SLIDE }
enum Dir { LEFT, RIGHT, UP, DOWN }        # SLIDE 时色板运动方向

@export var type: Type = Type.FADE
@export var direction: Dir = Dir.LEFT
@export var duration: float = 0.3
@export var color: Color = Color.BLACK
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT       # 默认 = 现有 fade 手感
@export var trans_type: Tween.TransitionType = Tween.TRANS_LINEAR

func is_none() -> bool                                          # type == NONE
func normalized() -> KitTransition                             # 返副本:夹 duration>=0、越界枚举回默认
func slide_cover_from(viewport_size: Vector2) -> Vector2       # SLIDE 覆盖段色板起点(终点恒 ZERO)
func slide_reveal_to(viewport_size: Vector2) -> Vector2        # SLIDE 揭开段色板终点(起点恒 ZERO)
```

## 依赖

零依赖(纯 `Resource` + 纯几何/校验方法,不引 `CoreKit`、不碰场景树),故可脱离门面 headless 断言。转场的实际遮罩驱动在 `SceneManager` 内(见 [scene-manager](../systems/scene-manager.md))。

## 用法示例

```gdscript
# 现造一个向左滑动转场,原地等待切换完成
var t := KitTransition.new()
t.type = KitTransition.Type.SLIDE
t.direction = KitTransition.Dir.LEFT
t.duration = 0.4
await CoreKit.scenes.change_scene("res://levels/level_2.tscn", t)

# 淡入淡出(可配缓动曲线)
var fade := KitTransition.new()
fade.type = KitTransition.Type.FADE
fade.trans_type = Tween.TRANS_SINE
CoreKit.scenes.change_scene(preload("res://levels/boss.tscn"), fade)

# 预置成 .tres 资产,多处复用(Inspector 里配好后 @export 引用)
@export var boss_transition: KitTransition
```

## 注意事项

- **对称两段**:转场恒为「COVER 覆盖 → 换树 → REVEAL 揭开」两段,各 `duration` 秒;v1 无单程语义。
- **SLIDE 方向**:`direction` = 色板运动方向,整段朝同一方向单向掠过屏幕(LEFT 从右缘驶入、续向左驶出),四向对称。
- **缓动默认 = 现有 fade 手感**:`ease_type`/`trans_type` 默认 `EASE_IN_OUT`+`TRANS_LINEAR`(Godot Tween 默认),故 legacy fade 视觉零变化;要弹性/正弦手感显式设 `trans_type`。
- **`normalized()` 返副本**:校验(夹负 duration、越界枚举回默认)作用在副本上,不改原资产,`.tres` 多处共享安全。
- **纯色遮罩**:首版遮罩为纯色 `ColorRect`,无 shader;圆形擦除/溶解等留待后续按需扩(`Type` 已留扩展位)。
- **向后兼容**:`change_scene` 仍接受 legacy `{"transition": CoreKit.scenes.Transition.FADE, ...}` 字典;新代码传 `KitTransition`。
```

- [ ] **Step 3: 更新 `docs/systems/scene-manager.md`**

(a) 职责段(第 7 行)句末「默认过渡 NONE,可选 FADE」改为「第 2 参接受 `KitTransition`(FADE/SLIDE)或 legacy options 字典,默认无过渡」。

(b) 公开 API 段的 `change_scene` 签名行:
```gdscript
# target 为 res:// 路径(String)或 PackedScene;options 支持 transition/duration/color,
# 未识别或类型不对的键静默回退默认值。可 fire-and-forget(靠信号),也可 await 原地等待。
func change_scene(target, options: Dictionary = {}) -> void
```
→
```gdscript
# target 为 res:// 路径(String)或 PackedScene;第 2 参接受 KitTransition 或 legacy options
# 字典({transition/duration/color},未识别键静默回退)。可 fire-and-forget,也可 await。
func change_scene(target, transition = {}) -> void
```

(c) 用法示例段末追加一段:
```markdown
# 用可复用转场资源(推荐,支持 SLIDE + 缓动曲线,可存 .tres)
var slide := KitTransition.new()
slide.type = KitTransition.Type.SLIDE
slide.direction = KitTransition.Dir.LEFT
await CoreKit.scenes.change_scene("res://levels/level_2.tscn", slide)
```
并在「注意事项」末追加一条:
`- **转场定义**:过渡由 [KitTransition](../transitions/kit-transition.md) 资源承载(FADE/SLIDE + 缓动 + 可存 .tres);legacy `enum Transition { NONE, FADE }` + 字典 API 保留兼容。`

- [ ] **Step 4: 更新 `docs/README.md`**

「### 类库(off-facade,不挂门面)」表(现第 44 行 rebind 行后)追加一行:
```markdown
| [kit-transition](transitions/kit-transition.md) | `class_name KitTransition` | 可复用场景转场资源(FADE/SLIDE,由 `CoreKit.scenes` 消费) |
```

- [ ] **Step 5: 更新 `docs/architecture.md`**

(a) 目录布局(现第 39 行 `ui/` 行后)加一行:
```
  transitions/           class_name 可复用转场资源(KitTransition,off-facade)
```

(b) 依赖纪律段(现第 72 行 `ui/` 那条 bullet 后)加一条:
```markdown
- `transitions/`(`KitTransition`)是 off-facade 可复用转场资源(`extends Resource`,零依赖),由 `SceneManager` 消费驱动遮罩;不接门面、不计入 12 子系统。
```

(c) 测试段(现第 92 行):`import → 16 测试 → demo 冒烟` 中 `16` → `17`。

(d) 版本段(现第 96 行)句首 `当前 `0.11.0``... 改为 `当前 `0.12.0``,并在其后紧接插入一句:
`0.11.0→0.12.0 新增 off-facade 可复用转场资源 `KitTransition`(`transitions/`,`extends Resource`):数据驱动的 FADE/SLIDE 转场,`SceneManager.change_scene` 兼容接收 `KitTransition` 或 legacy 字典,`_merge_options`/`enum Transition` 保留,纯增量、向后兼容。`

- [ ] **Step 6: 更新根 `README.md`**

(a) 文档表(现第 32 行 rebind 行后)加一行:
```markdown
| `KitTransition`(类库) | 可复用场景转场资源 | [kit-transition](addons/godot-core-kit/docs/transitions/kit-transition.md) |
```

(b) 版本段(现第 48 行 `## 版本` 下)在 `- **0.11.0**` 之前插入:
```markdown
- **0.12.0** — 新增 off-facade 可复用转场资源 `KitTransition`(`transitions/`,`extends Resource`):数据驱动的 FADE + SLIDE 场景转场(方向 + 缓动曲线,可存 `.tres`);`SceneManager.change_scene` 第 2 参兼容接收 `KitTransition` 或 legacy 字典,`_merge_options`/`enum Transition` 保留。纯增量,API 无破坏。
```

- [ ] **Step 7: demo 冒烟 marker**——`demo/demo.gd` 在 rebind 冒烟末尾 `CoreKit.settings.erase_value("input", "demo_rebind_a")`(现第 136 行)之后、`CoreKit.log.info("CoreKit v%s ..."`(现第 138 行)之前插入:

```gdscript

	# 转场缓动 冒烟:构造 SLIDE KitTransition + 纯几何 marker(不真切场景,headless 确定性)
	var tr := KitTransition.new()
	tr.type = KitTransition.Type.SLIDE
	tr.direction = KitTransition.Dir.LEFT
	tr.duration = 0.4
	CoreKit.log.info("Transition: type=SLIDE none=%s slide_cover_from=%s" % [
		tr.is_none(), tr.slide_cover_from(Vector2(800, 600))])
```

- [ ] **Step 8: run_all.ps1 接入**——`test/run_all.ps1`:

(a) 第 1 行注释 `16 个断言测试` → `17 个断言测试`。

(b) `$tests` 数组(现第 57 行结尾)`...,'test_locale_manager','test_rebind')` → `...,'test_locale_manager','test_rebind','test_transition')`。

(c) demo markers 数组(现第 72 行)在 `'conflict_blocked=true'` 后追加 `,'Transition: type=SLIDE none=false'`。

- [ ] **Step 9: 全量验证**

Run: `powershell -File test\run_all.ps1`
Expected: 末行 `=== SUMMARY FAILS=0 ===`(import → 17 测试全 OK → demo 全 marker present、stderr 无 ERROR)。

- [ ] **Step 10: 提交**

```bash
git add -A
git commit -m "docs+demo: wire KitTransition into facade version/docs/demo/run_all, bump 0.12.0

VERSION 0.12.0 三处同源(core_kit/plugin.cfg/test_core_kit);新 docs/transitions/
kit-transition.md 五段式 + scene-manager/README/architecture 更新;demo 加 SLIDE
KitTransition 纯几何 marker;run_all 加 test_transition(17 测试)+ demo marker。
off-facade,12 子系统计数不变。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec 覆盖**:KitTransition 资源(Task 1)· SceneManager 消费 + 兼容(Task 2)· 版本/文档/demo/run_all(Task 3)· 测试 test_transition + test_scene_manager 14–16(Task 1/2)· legacy 保留(Task 2 Edit 明确不动 `_merge_options`/`Transition`)—— spec 各段均有对应任务。

**占位符扫描**:无 TBD/TODO;每个代码步骤含完整代码;每处文档改动给了确切 old→new 锚点。

**类型一致性**:`KitTransition.Type { NONE, FADE, SLIDE }`、`Dir { LEFT, RIGHT, UP, DOWN }`、`normalized()`/`slide_cover_from`/`slide_reveal_to`/`is_none` 在 Task 1 定义,Task 2(`_resolve_transition`/`_play_transition`)与 Task 3(demo)引用一致;`change_scene(target, transition = {})` 新签名在 Task 2 定义、Task 3 文档同步。legacy `enum Transition { NONE, FADE }` 与 `KitTransition.Type` 前两序数对齐(NONE=0/FADE=1),`_legacy_transition_to_type` 显式 match 映射不依赖序数巧合。

**已知引擎坑复核**:① `KitTransition` 为 class_name,scene_manager.gd 按全局标识符引用,Task 2 Step 4 先 `--import` 刷缓存;test 文件用 `load()` 取脚本(`.Type` 经脚本资源访问,同 `SceneManagerScript.Transition` 既有范式)。② `@export var type: Type`——`type` 非 GDScript 关键字、非虚方法名,无遮蔽风险。③ `duplicate() as KitTransition` 显式 cast 避免不安全赋值告警。
