@tool
extends EditorPlugin

const POSITION_BOTTOM := 1

var _native_plugin: GodotSubpackEditorPlugin


func _enter_tree() -> void:
	_native_plugin = GodotSubpackEditorPlugin.new()
	_native_plugin.activate(self, POSITION_BOTTOM)


func _exit_tree() -> void:
	if _native_plugin:
		_native_plugin.deactivate(self)
		_native_plugin = null
