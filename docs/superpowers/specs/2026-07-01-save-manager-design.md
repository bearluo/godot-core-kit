# SaveManager (存档) 子系统设计

- 日期：2026-07-01
- 状态：已确认，待实现
- 版本目标：0.3.0
- 前置：`2026-07-01-logger-design.md`（沿用同样的 autoload 形状、`##` doc comment 风格、headless 纯函数测试规范）
- Autoload 名：`SaveManager`（`extends Node`，镜像 `Log`），文件 `addons/godot-core-kit/save_manager.gd`

**范围边界**：本文档只覆盖 SaveManager 子系统本身（`save_manager.gd` 的公开 API 与内部行为）及其测试计划。autoload 注册（`project.godot`/`plugin.gd` 接线）、版本号升级（`plugin.cfg`/`CoreKit.VERSION`）、README、demo 更新均为后续独立的集成步骤，不在本文档范围内——对应实现计划 `2026-07-01-save-manager.md` 同样只产出 `save_manager.gd` + `test/test_save_manager.gd` 两个文件。

## 目标与定位

把任意游戏状态（Dictionary）以具名"存档位"（slot）形式持久化到本地磁盘（`user://saves/`），提供一套在桌面与 Web 导出上行为一致的最小化、诚实的 API。SaveManager 只负责*字节怎么安全地读写到磁盘*，不负责*游戏往 Dictionary 里放什么*。与 `Log` 一样，它是独立、零依赖的子系统：只有自己的信号，不依赖 EventBus/SceneManager/ObjectPool；但可以依赖 `Log`（用于版本不匹配等场景下打日志）。

### v1 非目标（YAGNI，明确排除）

- 不做"已注册存档对象"registry / 从场景树自动收集状态。
- 不做加密（也不在 `save`/`load` 签名里预留 `encrypted` 占位参数）。
- 不做迁移引擎——只保留 `_version` 字段本身，供未来版本在不破坏格式的前提下加迁移逻辑。
- 不做自动存档调度——由游戏自己决定何时调用 `save()`。
- 不做存档位元数据 API（缩略图/时长）——`list_slots()` 只返回名称。
- 不做原子写（temp 文件 + rename）的崩溃安全加固。

## 公开 API

```gdscript
extends Node
## SaveManager —— godot-core-kit 全局存档单例。

signal saved(slot: String)
signal save_failed(slot: String, reason: String)
signal loaded(slot: String)
signal load_failed(slot: String, reason: String)
signal slot_deleted(slot: String)

const SAVE_DIR := "user://saves"
const SCHEMA_VERSION := 1

## 把 data 写入 slot，若该存档位已存在则覆盖。
## 成功返回 true；失败返回 false 并 emit save_failed(slot, reason)。
func save(slot: String, data: Dictionary) -> bool

## 把 slot 读回一个 Dictionary。任何错误（文件不存在、JSON 损坏/非法）
## 都返回 {} 并 emit load_failed；存档位本身合法地存了 {} 时同样返回 {}，
## 但 emit 的是 loaded —— 见下文"envelope 与空/损坏消歧"。
func load(slot: String) -> Dictionary

func has_slot(slot: String) -> bool
func delete_slot(slot: String) -> bool

## 仅名称（无元数据），升序排列。存档目录尚不存在时返回 []。
func list_slots() -> Array[String]

## --- 可测接缝（纯函数，不碰磁盘/autoload） ---

## 白名单方式清洗存档位名称为 [A-Za-z0-9_-]*；清洗后为空则拒绝，返回 ""。
func _sanitize_slot_name(slot: String) -> String

## 纯路径拼接；不做清洗——调用方需先自行清洗。
func _slot_path(slot: String) -> String

## Dictionary -> JSON 字符串，包裹为 {_version, data} 信封。
func _encode(data: Dictionary) -> String

## JSON 字符串 -> 信封 Dictionary（{_version:int, data:Dictionary}）；
## 任何失败（JSON 非法、根不是 Dictionary、信封键缺失/类型不对）都返回 {}。
func _decode(text: String) -> Dictionary
```

**命名坑（`load` 遮蔽全局 `load()`，需实现时验证）：** `load` 在本脚本自身作用域内会遮蔽 GDScript 内置全局函数 `load(path) -> Resource`，与 `Log` 遮蔽全局 `log()`（自然对数）是同一种情况，Logger 设计文档已 headless 验证过一次、这里按同样方式处理。其他脚本调用 `SaveManager.load("slot")` 不受影响（始终是限定调用）；SaveManager 内部从不需要调用全局 `load()`，所以这只是文档提示，不是阻塞项——实现阶段用 Godot 4.7 headless 再跑一次确认无遮蔽/报错。

## 行为与数据流

### `save(slot, data)`

1. `_sanitize_slot_name(slot)`；若结果为空 → `save_failed(slot, "invalid_slot_name")`，返回 `false`。（信号带*原始*字符串，方便调用方看清是什么被拒绝了。）
2. `DirAccess.make_dir_recursive_absolute(SAVE_DIR)` —— 幂等，保证首次 save 时目录已就绪，调用方无需单独"初始化"一步。
3. `FileAccess.open(_slot_path(safe_slot), FileAccess.WRITE)`；`null` → `save_failed(slot, "open_error:<code>")`（`<code>` 为 `FileAccess.get_open_error()` 返回的 `Error` 枚举整数值），返回 `false`。
4. `file.store_string(_encode(data))`，`file.close()`。
5. Emit `saved(safe_slot)`（*清洗后*的名字——磁盘上的真实身份），返回 `true`。

### `load(slot)`

1. 同样方式清洗；为空 → `load_failed(slot, "invalid_slot_name")`，返回 `{}`。
2. `FileAccess.file_exists(...)` 为 `false` → `load_failed(safe_slot, "not_found")`，返回 `{}`。
3. 打开、读全文、关闭；若打开失败（理论上的竞态：`file_exists` 之后文件被删/权限变化）→ `load_failed(safe_slot, "open_error:<code>")`，返回 `{}`（与 `save` 用同一种 reason 格式，属防御性补充，不引入新的 reason 词表）。
4. `_decode(text)`；空信封 → `load_failed(safe_slot, "corrupt")`，返回 `{}`。
5. 若 `envelope._version != SCHEMA_VERSION`：`Log.warn(...)`（v1 无迁移逻辑，这是未来迁移步骤的挂载点），照常继续。
6. Emit `loaded(safe_slot)`，返回 `envelope["data"]`。

### `has_slot` / `delete_slot` / `list_slots`

- `has_slot`：清洗失败视为 `false`；否则 `FileAccess.file_exists(_slot_path(...))`。
- `delete_slot`：清洗失败、文件不存在、或 `DirAccess.remove_absolute` 出错，均返回 `false`；成功删除才 emit `slot_deleted(safe_slot)` 并返回 `true`。**无专属失败信号**——`delete_slot` 的失败模式没有 `save`/`load` 那么丰富，返回值本身已足够，不需要额外一个 `reason`-carrying 信号。
- `list_slots`：目录不存在返回 `[]`；否则 `DirAccess.list_dir_begin()` 扫描 `SAVE_DIR`，跳过子目录，只保留扩展名为 `json` 的文件，取其去扩展名的 basename，升序排序后返回。

### 存档位清洗（`_sanitize_slot_name`）

白名单正则 `[^A-Za-z0-9_-]`，把命中的字符**删除**（而非替换为占位符）：

- `"hero1"` → `"hero1"`（全部合法，原样返回）。
- `"../../etc/passwd"` → 删除所有 `.`、`/` 后得到 `"etcpasswd"`：不含 `/`、`\`、`..`，直接挡掉路径穿越，不需要维护一份危险模式黑名单。
- `""` / `"   "` → 删除后仍是 `""`：空输入或纯空白输入被拒绝，**不会**静默回退到某个默认存档位——"清洗后为空则拒绝"这条规则由删除语义自然得到，不需要额外的空值特判分支。

### envelope 格式与空/损坏消歧

`_encode`/`_decode` 把调用方的 Dictionary 包一层信封 `{"_version": SCHEMA_VERSION, "data": <caller's dict>}`，而不是把 `_version` 拍平合并进调用方自己的字典（避免和调用方恰好也用了 `_version` 这个 key 冲突）。这个信封顺带解决了"合法空存档 `{}`"与"文件损坏"的消歧问题：

- `_decode` 对**任何**失败（JSON 语法错误、根不是 Dictionary、缺 `_version`/`data` 键、`data` 值类型不是 Dictionary）统一返回字面量 `{}`。
- 一个**合法**的信封永远至少有 `_version`、`data` 两个键，因此哪怕调用方存的就是 `save(slot, {})`，`_decode` 的返回值也不会等于 `{}`（`{"_version":1,"data":{}}` != `{}`）。
- 这让"损坏文件"与"合法空存档"在 `_decode` 这一层纯函数里就能被区分，而不必只依赖"到底触发了哪个信号"这种运行时行为来判断——可以直接写一条 disk-free 单元测试断言它。

版本号只是一个字段：`_version` 不匹配时仅 `Log.warn`，照常按当前解析逻辑继续加载，v1 没有任何迁移代码路径。

## 关键决定（已锁定）

| 维度 | 结论 | 理由 |
|---|---|---|
| 落盘格式 | JSON（`JSON.stringify`/`JSON.parse_string`），`indent="\t"` 美化输出 | 人类可读/可 diff，便于 QA 与开发期手改；与"纯 Dictionary"数据模型 1:1 对应；`ConfigFile` 的扁平 ini 分段不适合嵌套状态；`var_to_bytes` 能序列化任意 Object，绑定引擎二进制内部实现，版本脆弱且难调试。 |
| 数据模型 | 纯 Dictionary API（`save`/`load`） | Registry 式自动收集会耦合场景树组织方式，削弱独立性原则；v1 按 YAGNI 由游戏自己决定状态语义。 |
| 存档位/路径 | `user://saves/<slot>.json`；白名单正则清洗 `[^A-Za-z0-9_-]`（删除非法字符），清洗后为空则拒绝 | 直接从根源挡掉路径穿越（`../`、`/`、`\`、`:`、空字节等），而不是维护一份危险模式黑名单。 |
| 版本字段 | Envelope 包裹 `{_version, data}`，v1 `_version = 1`；不匹配仅 `Log.warn`，**不做迁移引擎** | 独立信封避免和调用方字典的 key 冲突；`_version` 字段本身足够留住未来演进空间，迁移逻辑本身留到真正需要时再设计——目前也没有已知的存档格式变更计划，先把字段占位即可。 |
| 加密 | v1 完全不做加密，`save`/`load` 签名**不含** `encrypted` 占位参数 | 密钥管理（密钥放哪、在天然可被检视的 Web 客户端上防的是什么）是威胁模型决策，不是工程默认值；没有具体近期需求就不预留占位参数——加密以后作为独立的新方法引入，而不是改动现有签名。 |
| 空/损坏消歧 | `_decode` 返回**整个信封**，只有失败时才是 `{}`；合法信封恒有 `_version`+`data` 两键，永不等于字面量 `{}` | 让"文件损坏"与"存档位合法地存了空 Dictionary"在纯函数层面就能区分，可写 disk-free 单测直接断言。 |
| 错误处理形态 | `bool`（save/has/delete）或 `Dictionary`（load）返回值 + `*_failed(slot, reason)` 信号，reason 为短机器可读字符串（`invalid_slot_name`/`not_found`/`open_error:<code>`/`corrupt`） | 调用方可只看返回值做分支（脚本友好），UI/遥测代码也可以只监听信号；reason 字符串稳定到可以被测试断言。 |
| 写入durability | 直接写（无 temp 文件 + rename 的原子写） | rename 式原子性在 Web 的 IndexedDB-backed 文件系统下语义不确定（见下文 Web 导出注意事项）；现在加是投机式加固——等真的收到存档损坏反馈再回头做。 |
| `list_slots()` 载荷 | 只返回名称，`Array[String]`，无元数据（无 mtime/size/缩略图） | 目前没有近期的存档选择 UI 元数据需求；以后如需 mtime，可以用 `FileAccess.get_modified_time()` 现查而不必改动存档格式；playtime/缩略图才需要真正的 API/信封变更，留到需要时再设计。 |

## Web 导出注意事项

- `user://` 在 HTML5 导出上由持久化的虚拟文件系统（IndexedDB-backed）支撑；`FileAccess`/`DirAccess` 调用与桌面**完全一致**——这正是选择"JSON + 纯 `FileAccess`"而不是任何需要原生文件选择器/原生路径的方案的原因。
- **Durability 警告（务必向使用方显式说明）：** Godot 的 HTML5 导出把内存文件系统同步到 IndexedDB 是**异步**的，不保证每次 `close()` 都同步落盘。`save()` 调用和下一次引擎驱动的同步之间若发生标签页崩溃/被强制关闭，这次写入可能丢失。实践建议：在有意义的检查点（关卡切换、玩家主动点"保存"）调用 `save()`，而不是每次状态变化都存；把 Web 端存档当作"尽力而为的持久化"，不是"保证持久化"。**这一点需要在实现阶段针对真实 Godot 4.7 Web 导出做一次实机验证，而不是仅凭文档假设。**
- **存储配额：** 浏览器 per-origin 存储有配额限制，部分浏览器（尤其 Safari/隐私模式）配额可能很小或在压力下被驱逐。v1 不做压缩也不做配额预检查——配额超限时游戏收到的唯一信号就是带 `open_error`/写入错误 reason 的 `save_failed`。
- **无跨设备/跨浏览器同步，玩家看不到文件本身：** 每个浏览器+origin 的 `user://` 都是完全独立的存储；玩家无法像桌面那样"看到"或搬运存档文件。这不是 SaveManager 特有的限制（所有 Godot Web 导出皆如此），但"存档位"这个 UX 概念常常隐含"文件系统层面可移植"的假设，在 Web 上并不成立，值得单独提醒。
- `FileAccess`/`DirAccess`/`JSON` 在所有平台上在 GDScript 里都是**同步** API——公开 API（`save`/`load`/`has_slot`/等）不需要 `await`/异步变体来支持 Web。

## 可测接缝与测试计划

纯、disk-free、不依赖 autoload —— 直接实例化脚本（`preload(...).new()`），与 `test/test_log.gd` 的模式一致：

- `_sanitize_slot_name(slot: String) -> String`
- `_slot_path(slot: String) -> String`
- `_encode(data: Dictionary) -> String`
- `_decode(text: String) -> Dictionary`

**测试文件：** `test/test_save_manager.gd`，`extends SceneTree`，
`const SaveManagerScript := preload("res://addons/godot-core-kit/save_manager.gd")`，
断言写在 `_initialize()` 里，全部通过打印 `test_save_manager: ALL PASS` 并 `quit(0)`；
任一失败打印失败详情并 `quit(1)`——与 `test/test_log.gd` 完全一致的 harness 形态。

### 第一部分：纯函数断言（全部 disk-free，共 11 条）

1. `_sanitize_slot_name("hero1")` == `"hero1"`（合法输入原样通过）。
2. `_sanitize_slot_name("../../etc/passwd")` 不含 `/`、`\`、`..`，且整体匹配 `^[A-Za-z0-9_-]+$`。
3. `_sanitize_slot_name("")` == `""` 且 `_sanitize_slot_name("   ")` == `""`（拒绝，不静默回退默认值）。
4. `_slot_path("hero1")` == `"user://saves/hero1.json"`（纯字符串拼接，不调用 `FileAccess`）。
5. 往返：对一个具代表性的嵌套 Dictionary（嵌套 dict、array、int、float、string、bool）做 `_decode(_encode(data))["data"] == data`。
6. `_decode(_encode({}))` **不是** `{}`——含 `_version`、`data` 两个键，`data == {}`，证明"合法空存档"不与"损坏"sentinel 冲突。
7. `_decode("not valid json {{{")` == `{}`（非法 JSON 被优雅处理，不崩溃）。
8. `_decode("42")` == `{}`（语法合法但根不是 Dictionary，拒绝）。
9. `_decode("{}")` == `{}`（合法 JSON object 但缺 `_version`/`data` 信封键，拒绝）。
10. `_decode('{"_version":1,"data":"not a dict"}')` == `{}`（内层 `data` 类型检查）。
11. `_encode({"a":1})` 的输出本身能被 `JSON.parse_string` 独立解析（确保 `_encode` 从不产出非法 JSON）。

### 第二部分（可选、清晰分隔）：磁盘往返

用一次性 slot 名（如 `__test_save_manager__`）走一遍真实 `FileAccess`/`DirAccess` I/O：`save` → `has_slot` → `load` → 内容一致 → `list_slots()` 含该名 → `delete_slot` → `has_slot` 变回 `false`；再单独构造一个磁盘上的损坏文件，断言 `load()` 返回 `{}` 且 `load_failed` 信号 reason 为 `"corrupt"`。测试结束前清理掉自己创建的文件。这部分与第一部分在测试文件里**明确分区**（独立的函数/注释块），不与纯函数断言混在一起，因为任务要求序列化逻辑本身必须能在零磁盘 IO 的前提下被验证。
