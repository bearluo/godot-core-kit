# godot-core-kit

通用 2D 游戏开发底层框架(Godot 4.7,纯 GDScript,Web 导出兼容)。
单一 autoload 门面 `CoreKit` 暴露全部子系统;`KitStateMachine`/`KitState`
以 class_name 类库随插件分发。

## 安装

1. 把 `addons/godot-core-kit/` 复制进目标工程;
2. 项目设置 → 插件 → 启用 godot-core-kit(自动注册唯一 autoload `CoreKit`)。

## 子系统一览

| 门面属性 | 子系统 | 一句话 |
|---|---|---|
| `CoreKit.log` | Log | 分级日志(debug/info/warn/error,运行时可调级) |
| `CoreKit.bus` | EventBus | 字符串事件 pub/sub,失效监听自动清理,重入安全 |
| `CoreKit.scenes` | SceneManager | 统一切场景入口,可选淡入淡出,重入拒绝 |
| `CoreKit.pool` | ObjectPool | 具名对象池,预热/上限/`_pool_reset` 钩子 |
| `CoreKit.saves` | SaveManager | JSON 信封存档槽(`user://saves/`) |
| `CoreKit.settings` | Settings | 玩家偏好分区键值,写透 `user://settings.json` |
| `CoreKit.ticker` | FrameScheduler | every_n 降频错峰 tick + 每帧预算任务队列 |
| `CoreKit.input` | InputManager | 键位重绑定持久化、设备检测、输入前缓冲 |
| `CoreKit.audio` | AudioManager | 总线音量持久化、BGM 交叉淡切、SFX 轮转池 |
| `CoreKit.res` | ResourceManager | 异步批量预热(桌面线程/Web 分帧双通道)+ 缓存 |

## 快速开始

```gdscript
CoreKit.log.info("hello")
CoreKit.bus.subscribe("player_died", _on_player_died)
CoreKit.bus.publish("player_died", {"by": "spike"})

CoreKit.settings.set_value("audio", "music", 0.8)
CoreKit.audio.play_music(preload("res://music/theme.ogg"), 1.5)  # 1.5s 交叉淡切
CoreKit.audio.play_sfx(preload("res://sfx/jump.wav"))

CoreKit.input.rebind_action("jump", my_key_event)   # 自动持久化,下次启动自动恢复
if CoreKit.input.is_action_buffered("jump", 0.15):  # 平台跳跃前缓冲
    CoreKit.input.consume_buffer("jump")
    _do_jump()

CoreKit.ticker.every_n(_slow_ai_think, 10)          # 每 10 帧,自动错峰
CoreKit.res.preload_batch(level_paths)              # 进度条接 batch_progress 信号

var save_ok := CoreKit.saves.save("slot1", {"hp": 100})
```

### 状态机(类库,不经门面)

```gdscript
# 场景树:Player → KitStateMachine → Idle/Run/Jump(各挂一个 KitState 子类脚本)
# 状态脚本里:
extends KitState

func update(delta: float) -> void:
    if CoreKit.input.is_action_buffered("jump", 0.15):
        transition_to("Jump")
```

## 0.3.x → 0.4.0 迁移(破坏性变更)

v0.4.0 起只注册一个 autoload `CoreKit`,老的全局单例名全部下线:

| 0.3.x | 0.4.0 |
|---|---|
| `Log.info(...)` | `CoreKit.log.info(...)` |
| `EventBus.publish(...)` | `CoreKit.bus.publish(...)` |
| `SceneManager.change_scene(...)` | `CoreKit.scenes.change_scene(...)` |
| `ObjectPool.acquire(...)` | `CoreKit.pool.acquire(...)` |
| `SaveManager.save(...)` | `CoreKit.saves.save(...)` |

升级步骤:更新 addon 目录后,在项目设置 → 全局(autoload)里**手动删除**
Log/EventBus/SceneManager/ObjectPool/SaveManager 五项旧注册,只保留 CoreKit;
然后按上表全局替换调用点。

## 测试

```
godot --headless --path . -s res://test/test_<subsystem>.gd
```

12 份 headless 断言测试覆盖全部子系统与门面接线;`demo/demo.tscn` 冒烟全家桶。

## 版本

- **0.4.0** — CoreKit 门面(唯一 autoload);新增 Settings / FrameScheduler /
  KitStateMachine / InputManager / AudioManager / ResourceManager;老五件迁入门面
  (破坏性变更,见迁移表)。
- 0.3.0 — EventBus / SceneManager / ObjectPool / SaveManager。
- 0.2.0 — Log。
- 0.1.0 — addon 脚手架。
