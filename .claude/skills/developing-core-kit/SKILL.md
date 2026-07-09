---
name: developing-core-kit
description: Use when adding a new subsystem to the godot-core-kit plugin or modifying an existing one — wiring a subsystem into the CoreKit facade, writing its headless test, keeping the version/docs/runner in sync, or extending subsystem behavior in a repo containing addons/godot-core-kit/.
---

# Developing core-kit

How to add or change a subsystem in the **godot-core-kit** Godot 4 GDScript plugin (`addons/godot-core-kit/`). Read `addons/godot-core-kit/docs/architecture.md` first — it is the source of truth for the facade, layout, and rules; this skill is the procedure.

> The repo may also contain `addons/godot_ai/` — an unrelated MCP editor plugin. This skill is only about `addons/godot-core-kit/`.

## Before writing code: lock the design

Decide up front: public API (signals + methods), whether it needs another subsystem, its facade property name (full word like `settings`/`audio`, not an abbreviation), and node name (PascalCase). For anything non-trivial, run the superpowers pipeline (brainstorming → writing-plans → subagent-driven-development); the design doc goes in `docs/superpowers/specs/`.

## Where the file goes

- `core/` — foundational, zero-dependency infra (`log`, `event_bus`, `settings`). `systems/` may depend on `core/`, never the reverse.
- `systems/` — gameplay-facing subsystems (everything else). New subsystems almost always go here.
- `extends Node`, **no `class_name`** (systems are reached only via `CoreKit.<prop>`; only `state_machine/` uses `class_name`). Indent with **tabs**. Lead with a `##` header docstring like `systems/resource_manager.gd`.

## Dependency discipline (hard rule)

Subsystems must NOT `preload` or hard-reference each other by name. The only two legal cross-subsystem channels:

1. **`bind_*(dep)` injection**, called ONLY from `core_kit.gd:_ready()`. Store the ref as untyped `_dep = null` and guard the unbound path (`if _dep == null: return`).
2. The global **`CoreKit.log`** chain.

Init-time diagnostics (`_init`/`_ready`, before wiring is guaranteed) use engine-native `push_warning`/`push_error`; runtime uses `CoreKit.log.*`.

## Wire into the facade — `core_kit.gd` (4 additive edits, in order)

Construction order = child order = `_ready` order. Append after the current last subsystem:

1. `const XScript := preload("res://addons/godot-core-kit/systems/x.gd")`
2. `var x: XScript`
3. in `_init()`: `x = XScript.new(); x.name = "X"; add_child(x)`
4. if it needs a dependency: add `x.bind_settings(settings)` in `_ready()`, before the final `log.info(...)` "ready" banner — the ONLY place cross-subsystem wiring may happen.

## Test — `test/test_x.gd`

- `extends SceneTree`; in `_initialize()` load the subsystem with **runtime `load(...)`, NOT a top-level `const preload`**. Hard-earned pitfall: a `-s` script's top-level preloads compile *before* autoloads register, so any script that references the global `CoreKit` identifier cannot be top-level-preloaded by a test.
- Instantiate the script directly (not through the `CoreKit` autoload — only `test_core_kit.gd` tests the facade itself).
- Assert with a `failures` counter, `print("FAIL n: ...")` per failure, end with `print("test_x: ALL PASS"); quit(0)` or `... %d FAILURE(S); quit(1)`.
- If the subsystem is injectable, test BOTH the bound and the unbound (`null`) degraded path.
- `.gd.uid` sidecars are real Godot-generated files: run `godot --headless --path . --import` to generate them; commit the `.gd` and its `.gd.uid` together; never hand-write or copy a UID.

## Update the facade regression test — `test/test_core_kit.gd`

It hard-codes the subsystem list in multiple places: add your entry to the `expected` (prop + script path) array AND the `order` (node-name) array; add a `bind_*` assertion if you injected a dependency; and update the VERSION assertion (see below).

## Keep version, docs, and runner in sync

- **Version** (three places must match): `plugin.cfg` `version=` (+ extend `description=`), `core_kit.gd` `const VERSION`, and the `test_core_kit.gd` VERSION assertion. Adding a subsystem is a new feature → **minor** bump (e.g. `0.4.1` → `0.5.0`). A no-API structural change is a patch — that is what `0.4.0` → `0.4.1` was, so don't reuse the patch slot.
- **Runner:** add `'test_x'` to `test/run_all.ps1`'s `$tests` array, **before `'test_core_kit'`** (which must stay last — it asserts the full facade). The runner also greps the demo's stdout for a fixed marker list and fails on any stderr `ERROR:`/`SCRIPT ERROR:`, so new code that pushes an error fails the gate.
- **Demo:** add a smoke block to `demo/demo.gd` with one distinctive `CoreKit.log.info(...)` line.
- **Docs** (living docs — never edit `docs/superpowers/*`, those are dated snapshots): new `addons/godot-core-kit/docs/systems/x.md` — **doc filenames are kebab-case** even though scripts are snake_case (`resource_manager.gd` → `resource-manager.md`). Use the five-section template (职责 / 公开 API / 依赖 / 用法示例 / 注意事项); add rows to `docs/README.md` and `docs/architecture.md` (facade table, construction chain). The subsystem count and test count are hardcoded as prose in several spots (`architecture.md`, repo `README.md`, `run_all.ps1` header) — grep the old number and update every hit.

## Verify — the gate

```
powershell -File test\run_all.ps1
```

Must end `=== SUMMARY FAILS=0 ===` (import → every test ALL PASS → demo smoke, stderr clean). This is the only acceptance signal — do not claim the change is done until it is green.

## Common mistakes

| Mistake | Fix |
|---|---|
| Top-level `const XScript := preload(...)` in a `-s` test | Use runtime `load(...)` inside `_initialize()` |
| `class_name` on a system script | Systems are facade-only; drop it |
| One subsystem `preload`s another | Use `bind_*` injection from `core_kit.gd:_ready()` or `CoreKit.log` |
| Bumped `plugin.cfg` but not `VERSION`/test assertion | Bump all three together |
| Added subsystem but `test_core_kit.gd` fails | Update its `expected` + `order` lists |
| Hand-wrote a `.gd.uid` | Run `--import` to generate it for real |
| Spaces for indentation | This repo uses tabs |
