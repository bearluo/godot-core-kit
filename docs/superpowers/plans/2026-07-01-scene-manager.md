# SceneManager 子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 godot-core-kit 实现 `SceneManager` 全局场景切换单例（v1：仅替换当前场景，无
场景栈）的脚本本体与 headless 纯逻辑断言测试。对应设计见
`docs/superpowers/specs/2026-07-01-scene-manager-design.md`。

**Architecture:** 单文件（`scene_manager.gd`）承载：`change_scene(target, options)` 统一
入口协程（重入保护 → 校验 → 归一化 options → 可选淡入 → 同步加载 → 等一帧 → 换场景 →
可选淡出 → 广播信号）、常驻子节点淡入淡出遮罩（`CanvasLayer` + `ColorRect` + `Tween`，
`_ready()` 一次性创建、幂等）、三个纯逻辑接缝（`_validate_target`/`_resolve_target_path`/
`_merge_options`）+ `is_changing()`，均不碰场景树、不调 `Log`，可在裸 `.new()` 实例上直接
调用断言。

**Tech Stack:** Godot 4.7，纯 GDScript，Compatibility 渲染器。无第三方测试框架。

## Global Constraints

以下为全项目约束，每个任务隐含遵守：

- 引擎 Godot 4.7，`config_version=5`；纯 GDScript，**不含 C#**。
- **Web 导出兼容**：禁止线程（不用 `Thread`/`load_threaded_request`）、禁止文件 IO、禁止
  shader；淡入淡出仅用 `CanvasLayer`+`ColorRect`+`create_tween()`。
- Autoload 名为 `SceneManager`，脚本路径 `addons/godot-core-kit/scene_manager.gd`。**本计划
  不做 autoload 注册**（不改 `project.godot`/`plugin.gd`），那是后续独立集成步骤；脚本本身
  引用全局标识符 `Log` 可正常编译，因为 `Log` 已在本仓库 `project.godot` 中注册为 autoload。
- **仅替换（replace-only），v1 无 push/pop 场景栈。**
- 同步 `load()`（不做线程化加载）；内建过渡 `Transition.{NONE, FADE}`，默认 `NONE`；拒绝
  重入（`_is_changing` 守卫 + `scene_change_failed(ERR_BUSY)`），不排队。
- 信号：`scene_changing(target_path: String)` /
  `scene_changed(scene_path: String, scene: Node)` /
  `scene_change_failed(target_path: String, error: int)`。
- Fade 默认值硬编码为 `const`（`DEFAULT_FADE_DURATION = 0.3`、`DEFAULT_FADE_COLOR = Color.BLACK`、
  CanvasLayer `layer = 4096`），可按次调用经 `options` 覆盖；v1 无全局配置入口。
- 可测纯接缝：`_validate_target`/`_resolve_target_path`/`_merge_options`/`is_changing()`，
  在裸 `preload(...).new()` 实例（未 `add_child`，`_ready()` 不会跑）上直接调用，不依赖
  autoload、不依赖运行中的场景树。真正动树的 `change_scene()` 协程与淡入淡出**不做** headless
  断言——那需要一棵运行中的场景树和真实可切换的两个场景，属于后续集成步骤的 demo 冒烟验证
  范畴，本计划只覆盖纯接缝。
- 独立性：只用自有信号，不依赖 EventBus/ObjectPool/SaveManager。
- 本机 Godot（验证用），下文命令记作 `$godot`：
  `D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`
  PowerShell 里先设 `$godot = "D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"`，再 `& $godot ...`。

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `addons/godot-core-kit/scene_manager.gd` | `SceneManager` 单例：`change_scene`/信号/fade 遮罩/纯接缝 | Create |
| `test/test_scene_manager.gd` | headless 断言 `_validate_target`/`_resolve_target_path`/`_merge_options`/`is_changing` | Create |

**范围外（不在本计划内，后续独立集成步骤处理）**：`project.godot`/`plugin.gd` 的 autoload
注册、`plugin.cfg`/`core_kit.gd`/`README.md` 的版本号升级、`demo/` 新增第二占位场景与
`change_scene` 实际冒烟验证。

---

## Task 1: SceneManager 核心 —— change_scene / fade 遮罩 / 重入保护 / 纯接缝

**Files:**
- Create: `addons/godot-core-kit/scene_manager.gd`
- Test: `test/test_scene_manager.gd`

**Interfaces:**
- Consumes: `Log`（全局 autoload，已在 `project.godot` 注册，供 `change_scene` 内部调用
  `Log.warn`/`Log.error`；纯接缝测试路径完全不触发这些调用）。
- Produces:
  - `SceneManager` 脚本（`extends Node`），供后续集成步骤注册为 autoload。
  - `enum Transition { NONE, FADE }`
  - `signal scene_changing(target_path: String)` /
    `signal scene_changed(scene_path: String, scene: Node)` /
    `signal scene_change_failed(target_path: String, error: int)`
  - `func change_scene(target, options: Dictionary = {}) -> void`（协程）
  - `func is_changing() -> bool` / `func get_current_scene() -> Node` /
    `func get_current_scene_path() -> String`
  - `func _validate_target(target) -> int`（可测）
  - `func _resolve_target_path(target) -> String`（可测）
  - `func _merge_options(options: Dictionary) -> Dictionary`（可测）

- [ ] **Step 1: 写失败测试** `test/test_scene_manager.gd`

```gdscript
extends SceneTree
## SceneManager 纯接缝 headless 断言测试（不依赖 autoload，直接实例化脚本）。
## 覆盖 _validate_target / _resolve_target_path / _merge_options / is_changing。
## change_scene() 本体（协程、动场景树、fade）不在本文件断言范围内 —— 那需要一棵运行中
## 的场景树和真实可切换场景，属后续集成步骤的 demo 冒烟验证范畴。
## 运行：godot --headless -s res://test/test_scene_manager.gd

const SceneManagerScript := preload("res://addons/godot-core-kit/scene_manager.gd")


func _initialize() -> void:
	var failures := 0
	var sm = SceneManagerScript.new()  # 裸 .new()，不 add_child，_ready() 不会跑

	# 1. _validate_target：真实存在的 .tscn 路径 → OK
	if sm._validate_target("res://demo/demo.tscn") != OK:
		print("FAIL _validate_target 应接受 res://demo/demo.tscn")
		failures += 1

	# 2. _validate_target：扩展名不对 → 非 OK
	if sm._validate_target("res://demo/demo.gd") == OK:
		print("FAIL _validate_target 应拒绝 res://demo/demo.gd(扩展名不对)")
		failures += 1

	# 3. _validate_target：空字符串 → 非 OK
	if sm._validate_target("") == OK:
		print("FAIL _validate_target 应拒绝空字符串")
		failures += 1

	# 4. _validate_target：非 res:// 开头 → 非 OK
	if sm._validate_target("user://x.tscn") == OK:
		print("FAIL _validate_target 应拒绝 user://x.tscn(非 res:// 开头)")
		failures += 1

	# 5. _validate_target：类型不对（int）→ 非 OK
	if sm._validate_target(123) == OK:
		print("FAIL _validate_target 应拒绝类型不对的 123")
		failures += 1

	# 6. _validate_target：真实 PackedScene → OK
	if sm._validate_target(preload("res://demo/demo.tscn")) != OK:
		print("FAIL _validate_target 应接受真实 PackedScene")
		failures += 1

	# 7. _resolve_target_path：String 原样返回
	if sm._resolve_target_path("res://a.tscn") != "res://a.tscn":
		print("FAIL _resolve_target_path(String) 应原样返回")
		failures += 1

	# 8. _resolve_target_path：PackedScene 返回 resource_path
	var path: String = sm._resolve_target_path(preload("res://demo/demo.tscn"))
	if path != "res://demo/demo.tscn":
		print("FAIL _resolve_target_path(PackedScene) 得到 '%s'" % path)
		failures += 1

	# 9. _merge_options({})：全部回退默认值
	var opts: Dictionary = sm._merge_options({})
	if opts["transition"] != SceneManagerScript.Transition.NONE:
		print("FAIL _merge_options({}) transition 应为 NONE")
		failures += 1
	if opts["duration"] != 0.3:
		print("FAIL _merge_options({}) duration 应为 0.3，得到 %s" % str(opts["duration"]))
		failures += 1
	if opts["color"] != Color.BLACK:
		print("FAIL _merge_options({}) color 应为 Color.BLACK")
		failures += 1

	# 10. _merge_options：合法 transition/duration 按传入值，color 回退默认
	var opts2: Dictionary = sm._merge_options({
		"transition": SceneManagerScript.Transition.FADE,
		"duration": 1.5,
	})
	if opts2["transition"] != SceneManagerScript.Transition.FADE:
		print("FAIL _merge_options transition 应保留传入的 FADE")
		failures += 1
	if opts2["duration"] != 1.5:
		print("FAIL _merge_options duration 应保留传入的 1.5")
		failures += 1
	if opts2["color"] != Color.BLACK:
		print("FAIL _merge_options 未传 color 时应回退默认黑色")
		failures += 1

	# 11. _merge_options：duration 负数夹到 0.0
	var opts3: Dictionary = sm._merge_options({"duration": -1})
	if opts3["duration"] != 0.0:
		print("FAIL _merge_options duration=-1 应夹到 0.0，得到 %s" % str(opts3["duration"]))
		failures += 1

	# 12. _merge_options：transition 超出枚举范围回退 NONE
	var opts4: Dictionary = sm._merge_options({"transition": 999})
	if opts4["transition"] != SceneManagerScript.Transition.NONE:
		print("FAIL _merge_options transition=999 应回退 NONE")
		failures += 1

	# 13. is_changing()：新实例默认 false
	if sm.is_changing():
		print("FAIL 新实例 is_changing() 应为 false")
		failures += 1

	sm.free()

	if failures == 0:
		print("test_scene_manager: ALL PASS")
		quit(0)
	else:
		print("test_scene_manager: %d FAILURE(S)" % failures)
		quit(1)
```

- [ ] **Step 2: 运行，确认失败**

```powershell
$godot = "D:\Program Files\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"
& $godot --headless --path . -s res://test/test_scene_manager.gd
```
Expected：失败。`scene_manager.gd` 尚不存在，`preload` 报错
`Could not preload resource file res://addons/godot-core-kit/scene_manager.gd`，脚本无法
加载，退出码非 0。

- [ ] **Step 3: 写实现** `addons/godot-core-kit/scene_manager.gd`

```gdscript
extends Node
## SceneManager —— godot-core-kit 全局场景切换单例（首版：仅替换，无场景栈）。
##
## 以 autoload "SceneManager" 注册（注册步骤属后续集成任务，不在本文件内）。统一入口
## change_scene(target, options) 把"替换当前活动场景"这件事从零散的
## get_tree().change_scene_to_*() 调用收敛为一个可选带淡入淡出过渡、带切换生命周期信号
## 的协程。同步 load()（不用线程，Web 导出安全）；默认过渡 NONE，可选 FADE
## （CanvasLayer + ColorRect + Tween，常驻本节点下、不受场景替换影响）。拒绝重入
## （_is_changing 守卫），不做排队。
##
## 用法：
##   SceneManager.change_scene("res://levels/level_2.tscn")
##   SceneManager.change_scene(preload("res://levels/boss.tscn"), {"transition": SceneManager.Transition.FADE})
##   await SceneManager.change_scene(...)   # 原地等待切换完成

signal scene_changing(target_path: String)
signal scene_changed(scene_path: String, scene: Node)
signal scene_change_failed(target_path: String, error: int)  # error 为 Error 枚举取值

enum Transition { NONE, FADE }

const DEFAULT_TRANSITION := Transition.NONE
const DEFAULT_FADE_DURATION := 0.3
const DEFAULT_FADE_COLOR := Color.BLACK
const _FADE_LAYER := 4096

var _is_changing := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	_ensure_fade_overlay()


# --- 公开运行时 API ---

## 把当前活动场景替换为 target。target 为 res:// 路径（String）或 PackedScene。
## options 支持 transition/duration/color，未识别或类型不对的键静默回退默认值。
## 协程：可 fire-and-forget（靠信号感知结果），也可 await 原地等待切换完成。
func change_scene(target, options: Dictionary = {}) -> void:
	var target_path := _resolve_target_path(target)

	if _is_changing:
		Log.warn("SceneManager.change_scene: 拒绝重入，目标 '%s' 被忽略（当前正在切换中）" % target_path)
		scene_change_failed.emit(target_path, ERR_BUSY)
		return

	var validation := _validate_target(target)
	if validation != OK:
		Log.error("SceneManager.change_scene: 非法 target '%s'" % target_path)
		scene_change_failed.emit(target_path, ERR_INVALID_PARAMETER)
		return

	var opts := _merge_options(options)
	var use_fade: bool = opts["transition"] == Transition.FADE

	_is_changing = true
	scene_changing.emit(target_path)

	if use_fade:
		_ensure_fade_overlay()
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		await _fade_to(1.0, opts["duration"], opts["color"])

	var packed_scene := _load_packed_scene(target)
	if packed_scene == null:
		Log.error("SceneManager.change_scene: 加载失败 '%s'" % target_path)
		if use_fade:
			await _fade_to(0.0, opts["duration"], opts["color"])
			_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_changing = false
		scene_change_failed.emit(target_path, ERR_CANT_OPEN)
		return

	# 等一帧再动树：避免在触发调用的信号回调栈内（例如按钮 pressed 冒泡途中）直接冻结/
	# 移除仍在处理事件的旧场景节点。NONE 过渡也统一走这一步，语义与内置
	# change_scene_to_* 系列的"延迟切换"保持一致。
	await get_tree().process_frame

	var new_scene := packed_scene.instantiate()
	var old_scene := get_tree().current_scene
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	if is_instance_valid(old_scene):
		old_scene.queue_free()

	if use_fade:
		await _fade_to(0.0, opts["duration"], opts["color"])
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_is_changing = false
	scene_changed.emit(target_path, new_scene)


func is_changing() -> bool:
	return _is_changing


func get_current_scene() -> Node:
	return get_tree().current_scene


func get_current_scene_path() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return scene.scene_file_path


# --- 可测纯逻辑接缝（不碰场景树、不调 Log）---

## target 是 PackedScene 时检查 can_instantiate()；是 String 时检查非空、以 res:// 开头、
## 以 .tscn/.scn 结尾（不检查文件是否真实存在，存在性检查留给运行时 ResourceLoader.exists）；
## 其余类型一律无效。返回 Error 枚举值 OK 或 ERR_INVALID_PARAMETER。
func _validate_target(target) -> int:
	if target is PackedScene:
		if target.can_instantiate():
			return OK
		return ERR_INVALID_PARAMETER
	if target is String:
		if target.is_empty():
			return ERR_INVALID_PARAMETER
		if not target.begins_with("res://"):
			return ERR_INVALID_PARAMETER
		if not (target.ends_with(".tscn") or target.ends_with(".scn")):
			return ERR_INVALID_PARAMETER
		return OK
	return ERR_INVALID_PARAMETER


## String 原样返回；PackedScene 返回其 resource_path（可能为空字符串）；其余类型返回空字符串。
func _resolve_target_path(target) -> String:
	if target is String:
		return target
	if target is PackedScene:
		return target.resource_path
	return ""


## 归一化 options，始终返回包含 transition/duration/color 三键的字典。
## 未识别键忽略；已识别键类型不对或超范围一律静默回退默认值。
func _merge_options(options: Dictionary) -> Dictionary:
	var transition = options.get("transition", DEFAULT_TRANSITION)
	if not (transition is int) or transition < Transition.NONE or transition > Transition.FADE:
		transition = DEFAULT_TRANSITION

	var duration = options.get("duration", DEFAULT_FADE_DURATION)
	if not (duration is int or duration is float):
		duration = DEFAULT_FADE_DURATION
	duration = max(0.0, float(duration))

	var color = options.get("color", DEFAULT_FADE_COLOR)
	if not (color is Color):
		color = DEFAULT_FADE_COLOR

	return {"transition": transition, "duration": duration, "color": color}


# --- 内部：加载 + 淡入淡出遮罩（碰场景树/资源系统，不做 headless 断言）---

## target 是 PackedScene 直接返回；是 String 先 ResourceLoader.exists 预检再同步 load()。
## 失败（不存在，或 load() 返回非 PackedScene）返回 null。
func _load_packed_scene(target) -> PackedScene:
	if target is PackedScene:
		return target
	var path: String = target
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path)
	if loaded is PackedScene:
		return loaded
	return null


## 一次性创建常驻淡入淡出遮罩（CanvasLayer + 铺满全屏 ColorRect），幂等：已创建且节点
## 仍有效则直接返回。挂在 SceneManager 节点下，天然不受场景替换影响，跨场景常驻。
func _ensure_fade_overlay() -> void:
	if _fade_layer != null and is_instance_valid(_fade_layer):
		return

	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = _FADE_LAYER
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = DEFAULT_FADE_COLOR
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


## 把遮罩的可见度 Tween 到 target_alpha。color 的 RGB 写入 ColorRect.color（alpha 归一化为
## 1.0），可见度完全由 modulate:a 驱动，避免 color.a 与 modulate.a 两个 alpha 通道相乘导致
## 淡入淡出不到位。
func _fade_to(target_alpha: float, duration: float, color: Color) -> void:
	_fade_rect.color = Color(color.r, color.g, color.b, 1.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, duration)
	await tween.finished
```

- [ ] **Step 4: 运行，确认通过**

```powershell
& $godot --headless --path . --import
& $godot --headless --path . -s res://test/test_scene_manager.gd
```
Expected：输出含 `test_scene_manager: ALL PASS`，退出码 0。（`--import` 顺带生成
`scene_manager.gd.uid`、`test_scene_manager.gd.uid` 边车文件。）

注意：本步骤只验证 13 项纯接缝断言。`change_scene()` 本体（重入保护的运行时行为、真实加载、
换场景、fade 遮罩的可见 Tween 效果）不被这份 headless 测试覆盖——它需要一棵运行中的场景树、
一个已注册的 `SceneManager` autoload 和至少两个真实可切换场景，留给后续集成步骤用 demo 工程
做冒烟验证（对齐设计文档"架构与文件"节声明的范围边界）。

- [ ] **Step 5: 提交**

```powershell
git add addons/godot-core-kit/scene_manager.gd addons/godot-core-kit/scene_manager.gd.uid test/test_scene_manager.gd test/test_scene_manager.gd.uid
git commit -m @'
feat: add SceneManager core (change_scene / fade overlay / re-entry guard)

SceneManager 单例：change_scene(target, options) 统一入口协程（重入保护 →
校验 → 归一化 options → 可选淡入 → 同步加载 → 等一帧 → 换场景 → 可选淡出 →
广播信号）；scene_changing/scene_changed/scene_change_failed 三个信号；
Transition.NONE|FADE，v1 仅替换、无场景栈。常驻 CanvasLayer+ColorRect+Tween
淡入淡出遮罩，_ready() 一次性创建、幂等。纯接缝 _validate_target/
_resolve_target_path/_merge_options + is_changing() 供 headless 断言，
不碰场景树、不调 Log。headless 测试直接实例化脚本、不依赖 autoload。
尚未接线到工程（autoload 注册、版本升级、demo 冒烟为后续独立集成步骤）。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## 完成后

Task 1 完成后，`SceneManager` 的脚本本体与纯接缝测试即落地，但**尚未生效**（未注册为
autoload）。后续独立集成步骤（类比 Logger 的 Task 2）需要：在 `plugin.gd`/`project.godot`
注册 `SceneManager` autoload（追加在 `CoreKit` 之后）、`plugin.cfg`/`core_kit.gd`/`README.md`
版本号升到 `0.3.0`、`demo/` 新增第二占位场景并跑一次真实 `change_scene()`（先 `NONE` 过渡
验证基本替换，再 `FADE` 过渡验证遮罩不报错）冒烟验证 `scene_changing`/`scene_changed`
各触发一次、`get_tree().current_scene` 确实变化、`--quit-after N` 无报错退出码 0——该步骤
不在本计划范围内，需另开一份实现计划。
