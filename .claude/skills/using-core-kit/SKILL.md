---
name: using-core-kit
description: Use when calling or looking up the godot-core-kit API from a Godot game — playing audio/BGM, saving/loading, scene changes, input rebinding or jump-buffering, player settings, event bus pub/sub, object pools, frame-divided ticks, async resource preloading, or the KitStateMachine; or to find which subsystem provides a feature.
---

# Using core-kit

`godot-core-kit` exposes every subsystem through ONE autoload facade named `CoreKit` (plugin lives at `addons/godot-core-kit/`).

> If the project also has `addons/godot_ai/`, that is an unrelated MCP editor plugin — ignore it. Everything here is `CoreKit`.

## The answer is in the shipped docs — go there first

Authoritative, kept-1:1-with-source API docs ship inside the plugin. Prefer them over reading source:

- `addons/godot-core-kit/docs/README.md` — index of every subsystem.
- `addons/godot-core-kit/docs/architecture.md` — facade, init order, engine gotchas.
- `addons/godot-core-kit/docs/core/<x>.md` and `docs/systems/<x>.md` — per subsystem: 职责 / 公开 API / 依赖 / 用法示例 / 注意事项.
- `addons/godot-core-kit/docs/state-machine.md` — the KitStateMachine class library.

## Facade map (property → subsystem)

| Access | Does what |
|---|---|
| `CoreKit.log` | leveled logging (debug/info/warn/error) |
| `CoreKit.bus` | string-name pub/sub event bus |
| `CoreKit.settings` | player prefs, persisted to `user://settings.json` |
| `CoreKit.scenes` | scene switching (optional fade) |
| `CoreKit.pool` | object pools |
| `CoreKit.saves` | save slots (`user://saves/`) |
| `CoreKit.ticker` | frame-divided ticks + per-frame budget queue |
| `CoreKit.input` | action rebinding + device detect + input buffer |
| `CoreKit.audio` | bus volume + BGM crossfade + SFX pool |
| `CoreKit.res` | async batch preload + cache |

`KitStateMachine` / `KitState` are a per-entity `class_name` library, NOT on the facade — you `new()` one per entity. See `docs/state-machine.md`.

## To answer "how do I X?"

1. Find the subsystem in the map above.
2. Open `addons/godot-core-kit/docs/README.md` — its index links straight to each subsystem's page (filenames are **kebab-case**: `audio-manager.md`, not `audio.md`). The page's **公开 API** section has exact signatures, **用法示例** has a runnable snippet.
3. Call it via `CoreKit.<prop>...`.

## Gotchas that bite first-timers

- **Volume:** use `CoreKit.audio.set_volume("music", 0.8)` — it writes `AudioServer` immediately AND persists. `CoreKit.settings.set_value("audio","music",...)` alone is inert until the next launch, so the README's opening one-liner is a Settings demo, not the way to change volume live.
- **JSON int→float:** settings/saves round-trip through JSON, so ints come back as floats — wrap reads in `int(...)`.
- **State machine first run:** any script referencing `KitStateMachine`/`KitState` needs `godot --headless --path . --import` once to build the `class_name` cache.
