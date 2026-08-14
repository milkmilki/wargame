class_name DisplaySettings
extends RefCounted
## 固定窗口分辨率的配置真源。窗口保持 16:9 且禁止用户任意拉伸，
## 分辨率只能通过设置菜单切换，避免出现未经布局验证的中间尺寸。

const CONFIG_PATH := "user://display_settings.cfg"
const CONFIG_SECTION := "display"
const WIDTH_KEY := "width"
const HEIGHT_KEY := "height"
const DEFAULT_RESOLUTION := Vector2i(1280, 720)
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1024, 576),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]


static func load_resolution() -> Vector2i:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return DEFAULT_RESOLUTION
	var resolution := Vector2i(
		int(config.get_value(
			CONFIG_SECTION,
			WIDTH_KEY,
			DEFAULT_RESOLUTION.x
		)),
		int(config.get_value(
			CONFIG_SECTION,
			HEIGHT_KEY,
			DEFAULT_RESOLUTION.y
		))
	)
	return validated_resolution(resolution)


static func save_resolution(resolution: Vector2i) -> Error:
	var validated := validated_resolution(resolution)
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, WIDTH_KEY, validated.x)
	config.set_value(CONFIG_SECTION, HEIGHT_KEY, validated.y)
	return config.save(CONFIG_PATH)


static func apply_resolution(resolution: Vector2i) -> void:
	var validated := validated_resolution(resolution)
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_RESIZE_DISABLED,
		true
	)
	DisplayServer.window_set_size(validated)
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(
		usable.position
			+ Vector2i(
				maxi(usable.size.x - validated.x, 0),
				maxi(usable.size.y - validated.y, 0)
			) / 2
	)


static func validated_resolution(resolution: Vector2i) -> Vector2i:
	return (
		resolution
		if RESOLUTIONS.has(resolution)
		else DEFAULT_RESOLUTION
	)
