# Log —— 全局日志

> `CoreKit.log` · `core/log.gd`

## 职责

分级日志单例。四级(DEBUG/INFO/WARN/ERROR)+ 全局阈值过滤 + 统一格式 `[HH:MM:SS.mmm][LEVEL] message` + `print_rich` 彩色输出。WARN/ERROR 额外走 `push_warning`/`push_error`,进编辑器"错误"面板并带调用栈。纯 GDScript、无文件 IO,支持 Web 导出。

## 公开 API

```gdscript
enum Level { DEBUG, INFO, WARN, ERROR }

func debug(message) -> void
func info(message) -> void
func warn(message) -> void          # 额外 push_warning
func error(message) -> void         # 额外 push_error
func set_level(level: Level) -> void # 全局阈值,默认 DEBUG
func get_level() -> Level
func format_line(level: Level, message) -> String  # 只格式化不打印(测试/复用)
```

`message` 接受任意类型(内部 `str()` 转换)。低于当前阈值的调用直接跳过,无格式化开销。

## 依赖

零依赖。构造序最靠前,故其它所有子系统都能在自己的生命周期里安全调用 `CoreKit.log`。

## 用法示例

```gdscript
CoreKit.log.info("关卡加载完成")
CoreKit.log.warn("掉帧:%d ms" % delta_ms)
CoreKit.log.error("存档写入失败")

# 发布构建只留 WARN 及以上
CoreKit.log.set_level(CoreKit.log.Level.WARN)
```

## 注意事项

- 属性名 `log` 遮蔽全局函数 `log()`(数学对数)。需要数学 `log()` 的作用域自行注意。
- WARN/ERROR 会污染编辑器错误面板——是刻意设计(让问题显眼),不要用它们打常规流水日志。
- 时间戳取自系统时钟(`Time.get_time_string_from_system`),非游戏内时间。
