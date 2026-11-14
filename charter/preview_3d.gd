class_name Preview3D
extends Control

signal cursor_changed(u: float, valid: bool)
signal notice(message: String, level: String)
## 环编辑工作区：滚轮缩放、拖空白旋转，由工作区写进镜头关键帧。
signal ring_zoom(delta: float)
signal ring_rotate(degrees: float)

const RING_WIDTH := 4.0
const GLOW_WIDTH := 18.0
const PREVIEW_MARGIN := 1.24
const MOUSE_TILT_DEGREES := 11.0
## Path / Trace 的视觉尺寸：相对旧版 ×2。只放大笔画与头尾，不改轨迹几何与判定。
const PATH_SIZE_SCALE := 2.0
## 金键（Bell）：环上一段白描边金键（圆头 + 金色核心 + 细金光环）。
const BELL_BAND_HALF := 10.0
## 光标离弧带（含两端）多少像素内算在场。
const BELL_RADIAL_TOLERANCE := 55.0
## 扫键串里的 Bell 放宽到这个半径，并在画面上画出同半径的淡金光圈。
const BELL_CHAIN_TOLERANCE := 75.0
## 星头单独缩小（轨迹宽度不受影响）。
const PATH_HEAD_SCALE := 0.62
## 接力高亮：等待处理的星在重叠时压到这个亮度。
const PATH_RELAY_DIM := 0.45
## 命中退场：尾判后尾巴停在判定环上再淡出的真实时长（秒）。
## 用真实时间而不是拍数，慢歌不会拖成半秒、快歌也不会一闪就没。
const END_FADE_SEC := 0.1
## 松手补按窗口内的变暗程度（1 = 不变暗）。
const HOLD_SLIP_DIM := 0.35
## 命中后音符整体放大淡出的时长与最终倍数（osu!std 式击打光）。
## 从音符落在环上的实际大小起步，不再额外放大基座。
const NOTE_POP_SEC := 0.28
const NOTE_POP_SCALE := 1.5

var chart_override: Chart = null
## 洋葱皮：相邻关键帧的轮廓，由环工作区填。
var onion_shapes: Array = []
var follow_app: bool = true
var time_beat: float = 0.0
var playing: bool = false
var interactive: bool = true
var playtest_mode: bool = false
var show_hud: bool = true
var show_debug: bool = false
## Dedicated input overlay: geometry and progress come from live playtest states.
var show_path_judgement := false
var path_judgement_states: Dictionary = {}
var flow_scale: float = 1.0
var star_speed: float = 1.0
## Trace 门框的主色（默认银白）。
var custom_cursor_visible: bool = true
## 光标大小倍率（1.0 = 默认）。
var cursor_scale: float = 1.0
var mouse_tilt: bool = true
var use_3d_ring: bool = true:
	set(value):
		if use_3d_ring == value:
			return
		use_3d_ring = value
		if _viewport_container != null:
			_viewport_container.visible = value
		if _subviewport != null:
			_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
			_render_mode = -1 if value else SubViewport.UPDATE_DISABLED
		_force_3d_frame = value
		_mesh_dirty = true
		if _overlay != null:
			_overlay.queue_redraw()

var _app: Node = null

var hud_accuracy: float = -1.0
var hud_rating: String = "—"
var hud_errors: Array[float] = []
## 试玩 HUD：四角放数据、中心放连击、环外放进度/准度两条弧。
var hud_combo: int = 0
var hud_max_combo: int = 0
var hud_tiers: Dictionary = {}
var hud_title: String = ""
var hud_difficulty: String = ""
var hud_auto: bool = false
## HUD 选项（来自 App.hud_options()）：缩放 / 连击位置 / 进度仪表 / 判定字位置 / 档位计数 / 透明度 / 左上内容。
var hud_options: Dictionary = {}
var hud_ms: float = 0.0
var hud_total_ms: float = 0.0

var cursor_u: float = 0.0
var cursor_valid: bool = false
var mouse_screen: Vector2 = Vector2.ZERO
var mouse_inside: bool = false
## AUTO 自动演示时的合成光标：有限值就盖掉真实鼠标，INF 表示用真鼠标。
var auto_cursor: Vector2 = Vector2.INF

var _bg: TextureRect
var _background_image: TextureRect
var _last_background_path: String = ""
var _video: VideoStreamPlayer
var _viewport_container: SubViewportContainer
var _subviewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _ring_root: Node3D
var _ring_mesh: MeshInstance3D
var _glow_mesh: MeshInstance3D
var _stage_mesh: MeshInstance3D
var _bezel_mesh: MeshInstance3D
var _shadow_mesh: MeshInstance3D
var _disc_mesh: MeshInstance3D
var _beams_mesh: MeshInstance3D
var _frame_mesh: MeshInstance3D
var _amber_mesh: MeshInstance3D
var _rim_mesh: MeshInstance3D
var _overlay: Control
var _cursor_layer: Control
var _ring_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _stage_material: StandardMaterial3D
var _bezel_material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _disc_material: StandardMaterial3D
var _beams_material: StandardMaterial3D
var _frame_material: StandardMaterial3D
var _amber_material: StandardMaterial3D
var _rim_material: StandardMaterial3D

var _last_mesh_beat: float = -9999.0
var _mesh_dirty: bool = true
var _last_chart_ref: Chart = null
var _last_video_path: String = ""
var _video_load_failed: bool = false
## 静图默认 32% 不透明度；改成全局系数后由设置推动。
const BACKGROUND_ALPHA := 0.32
## 背景明暗系数（1.0 = 现在观感）；静图和 BGA 共用。
var background_brightness: float = 1.0
## 暂停时把 BGA 一起停住，恢复后由 _update_video 重新对齐位置。
var video_paused: bool = false
## 播放倍速：BGA 跟着音频一起变速，否则画面会和音乐脱节。
var playback_rate: float = 1.0
## 异步转码的令牌：换谱/换视频后旧结果直接丢掉。
var _video_job_token: int = 0
var _last_cursor_emit: Vector2 = Vector2(-999, -999)
var _cursor_cache_key: String = ""
var _sorted_notes_cache: Array[Note] = []
var _path_runs_cache: Dictionary = {}
var _sorted_notes_chart: Chart = null
var _last_view_key: String = ""
var _last_fit_key: String = ""
var _last_mesh_key: String = ""
var _last_mesh_usec: int = 0
var _last_process_time: float = -9999.0
var _last_mouse_screen: Vector2 = Vector2(-9999, -9999)
var _cursor_trail: Array[Dictionary] = []
## 3D 视口上次重画时间（试玩时限频，不影响 2D/游戏帧率）。
var _last_3d_usec: int = 0
var _last_3d_key: String = ""
## 性能采样：draw_overlay 的平均耗时 + FPS，每 2 秒打印一次（仅试玩）。
var _perf_draw_usec: int = 0
var _perf_frames: int = 0
## [seeks, paths, holds, notes, fx, hud, bar, cursor, audio] 的累计微秒。
var _perf_sections: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var _perf_proc_usec: int = 0
var _perf_mesh_usec: int = 0
var _perf_since_usec: int = 0
## 舞萌星星的默认深蓝色，以及重叠时使用的同色系配色。
const STAR_BLUE := Color(0.22, 0.36, 0.88)
const STAR_BLUE_PALETTE: Array[Color] = [
	Color(0.22, 0.36, 0.88),
	Color(0.16, 0.62, 0.97),
	Color(0.42, 0.52, 1.00),
	Color(0.10, 0.78, 0.90),
	Color(0.30, 0.30, 0.72),
	Color(0.55, 0.72, 1.00),
	Color(0.10, 0.50, 0.62),
]
var _avg_radius_cache: float = 100.0
var _avg_radius_key: String = ""
var _last_overlay_time: float = -9999.0
var _render_mode: int = -1
var _render_frame: int = 0
var _tilt: Vector2 = Vector2.ZERO
var _tilt_target: Vector2 = Vector2.ZERO
var _force_3d_frame: bool = false
var _boundary_frame_cache: BoundaryFrame = null
var _max_design_radius: float = -1.0
var _path_local_cache: Dictionary = {}

var _drag_vertex: int = -1
var _drag_visual: int = -1
var _drag_visual_note: Note = null
var _drag_visual_start: Vector2 = Vector2.ZERO
var _drag_visual_db: float = 0.0
var _drag_visual_da: float = 0.0
var _drawing_red: bool = false
var _red_region: Region = null
var _red_start_u: float = 0.0
var _red_start_beat: float = 0.0
var _red_start_mouse: Vector2 = Vector2.ZERO
var _pulses: Array[Dictionary] = []
var _arc_flashes: Array[Dictionary] = []
var _note_pops: Array[Dictionary] = []
# 音符外观与打击特效方案（网页 Note & Hit Lab 里可对比选择）。
var note_skin: String = "candy"
var hit_fx_style: String = "burst"
var _skin_cache: Dictionary = {}
var _skin_cache_key: String = ""
var path_cuts: Dictionary = {}
## 环分区擦除：note.id -> [{from,to}]，和 path_cuts 分开存，避免每帧的
## set_path_erased_to 把分区擦除覆盖掉。
var path_sector_cuts: Dictionary = {}
var path_cut_versions: Dictionary = {}
var _path_sector_cache: Dictionary = {}
## 星头判定结果（试玩时由 Playtest 写入）：{hit: bool, beat: float}。
var _path_head_state: Dictionary = {}
## 试玩判定结果（note.id -> "hit" / "miss" / "holding"）：
## 判定一出来音符就退场；hold 头部命中后只隐藏头部，长条继续画。
var note_states: Dictionary = {}
## 判成 MISS 时的谱面拍：hold 整条按 0.24 拍淡出，不硬切。
var note_state_beats: Dictionary = {}
## 环编辑工作区模式：左键拖空白旋转、滚轮缩放。
var ring_edit_mode: bool = false
var _ring_rotating: bool = false
var _ring_rot_last: float = 0.0
var _drawing_path: bool = false
var _path_points: Array[Vector2] = []
var _path_head_angle: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_app = get_node_or_null("/root/App")
	_build_layers()
	_build_3d()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.selection_changed.connect(_on_selection_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.tool_changed.connect(_on_tool_changed)
	set_process(true)


func _exit_tree() -> void:
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 画质档：0 = 全开，1 = 省电（只降 3D 背景的渲染分辨率，音符永远按全画质画）。
## 试玩里由实测帧时自动降档，只为让弱机也能稳住节奏。
var quality_level: int = 0
## 音符弧带采样精度：true = 1/4°（全画质），false = 1/6°（省电，边缘略方）。
var note_detail_fine: bool = true
## 音符粉色柔光 / 拖尾长度 / 命中特效强度 / 小节线：全部来自视图菜单的画质项。
var note_glow: bool = true
var cursor_trail_mode: String = "long"
var fx_budget: String = "full"
var bar_lines_visible: bool = true
## 3D 背景渲染分辨率与刷新率（2D 与判定永远按游戏帧率）。
var ring_3d_scale: String = "high"
## 0 = 关，1 = 2x，2 = 4x
var msaa_3d_level: int = 1
var ring_3d_hz: int = 60


func set_quality_level(level: int) -> void:
	var next := clampi(level, 0, 1)
	if next == quality_level:
		return
	quality_level = next
	apply_ring_quality()


## 3D 背景分辨率：菜单选的高/中/低，再叠加弱机自动降档（降一档，最低 0.4）。
func apply_ring_quality() -> void:
	if _subviewport == null:
		return
	var scale := 1.0
	match ring_3d_scale:
		"ssaa15":
			scale = 1.5
		"ssaa12":
			scale = 1.25
		"high":
			scale = 0.85
		"mid":
			scale = 0.65
		"low":
			scale = 0.5
	if quality_level > 0:
		scale = maxf(0.4, scale - 0.15)
	_subviewport.scaling_3d_scale = scale
	# 抗锯齿按模式组合：MSAA / FXAA / TAA / MSAA+FXAA。
	_subviewport.msaa_3d = Viewport.MSAA_DISABLED
	_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_subviewport.use_taa = false
	match msaa_3d_level:
		1:
			_subviewport.msaa_3d = Viewport.MSAA_2X
		2:
			_subviewport.msaa_3d = Viewport.MSAA_4X
		3:
			_subviewport.msaa_3d = Viewport.MSAA_8X
		4:
			_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		5:
			_subviewport.use_taa = true
		6:
			_subviewport.msaa_3d = Viewport.MSAA_2X
			_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		7:
			_subviewport.msaa_3d = Viewport.MSAA_4X
			_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	if _overlay != null:
		_overlay.queue_redraw()


func set_suspended(suspended: bool) -> void:
	set_process(not suspended)
	if _subviewport == null:
		return
	if suspended:
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_render_mode = SubViewport.UPDATE_DISABLED
	else:
		_force_3d_frame = use_3d_ring
		_render_mode = -1


func get_chart() -> Chart:
	if chart_override != null:
		return chart_override
	if _app == null:
		return null
	return _app.chart


func get_time_beat() -> float:
	if follow_app and _app != null:
		return _app.playhead_beat
	return time_beat


func current_view() -> Dictionary:
	var chart := get_chart()
	if chart == null:
		return ViewState.default_state()
	return BoundaryRuntime.eval_view(chart, get_time_beat())


func _build_layers() -> void:
	_bg = TextureRect.new()
	_bg.name = "StageBackground"
	var space := GradientTexture2D.new()
	space.width = 512
	space.height = 512
	space.fill = GradientTexture2D.FILL_RADIAL
	space.fill_from = Vector2(0.5, 0.46)
	space.fill_to = Vector2(1.0, 0.95)
	var space_gradient := Gradient.new()
	space_gradient.set_color(0, Color("#151D2B"))
	space_gradient.set_color(1, Color("#05070B"))
	space.gradient = space_gradient
	_bg.texture = space
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_background_image = TextureRect.new()
	_background_image.name = "BackgroundImage"
	_background_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_image.modulate = Color(1, 1, 1, 0.32)
	_background_image.visible = false
	add_child(_background_image)
	_background_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_video = VideoStreamPlayer.new()
	_video.name = "Video"
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.visible = false
	_video.expand = true
	_video.volume_db = -80.0
	add_child(_video)
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "ViewportContainer"
	_viewport_container.stretch = false
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_subviewport = SubViewport.new()
	_subviewport.name = "SubViewport"
	_subviewport.transparent_bg = true
	_subviewport.own_world_3d = true
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_subviewport.scaling_3d_scale = 1.0
	_subviewport.msaa_3d = Viewport.MSAA_2X
	_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_container.add_child(_subviewport)

	_overlay = Control.new()
	_overlay.set_script(load("res://charter/preview_overlay.gd"))
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set("preview", self)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 光标单独一层：鼠标移动只重绘这一层，不再重画整个场景。
	_cursor_layer = Control.new()
	_cursor_layer.set_script(load("res://charter/preview_overlay.gd"))
	_cursor_layer.name = "CursorLayer"
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.set("preview", self)
	_cursor_layer.set("cursor_only", true)
	add_child(_cursor_layer)
	_cursor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.visible = use_3d_ring


func _build_3d() -> void:
	_world = Node3D.new()
	_world.name = "World3D"
	_subviewport.add_child(_world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.20, 0.26, 1.0)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_world.add_child(world_env)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 42.0
	_camera.near = 1.0
	_camera.far = 6000.0
	_camera.position = Vector3(0, 0, 1200)
	_world.add_child(_camera)
	_camera.current = true
	_camera.look_at(Vector3.ZERO, Vector3.UP)

	_ring_root = Node3D.new()
	_ring_root.name = "RingRoot"
	_world.add_child(_ring_root)

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.albedo_color = Color(0.62, 0.64, 0.68, 0.95)
	_ring_material.render_priority = 3

	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.albedo_color = Color(0.37, 0.85, 0.81, 0.12)
	_glow_material.render_priority = 2

	_stage_material = StandardMaterial3D.new()
	_stage_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stage_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stage_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stage_material.albedo_color = Color(0.62, 0.68, 0.78, 0.16)
	_stage_material.render_priority = -2

	_disc_material = StandardMaterial3D.new()
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc_material.albedo_color = Color(0.05, 0.07, 0.10, 0.45)
	_disc_material.render_priority = -3

	_beams_material = StandardMaterial3D.new()
	_beams_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beams_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beams_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beams_material.albedo_color = Color(0.50, 0.70, 0.78, 0.032)
	_beams_material.render_priority = -2

	_frame_material = StandardMaterial3D.new()
	_frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame_material.albedo_color = Color(0.96, 0.95, 0.90, 0.92)
	_frame_material.render_priority = 4

	_amber_material = StandardMaterial3D.new()
	_amber_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_amber_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_amber_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_amber_material.albedo_color = Color(0.94, 0.55, 0.21, 0.84)
	_amber_material.render_priority = 3

	_rim_material = StandardMaterial3D.new()
	_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_material.albedo_color = Color(0.02, 0.03, 0.045, 0.72)
	_rim_material.render_priority = -4

	_bezel_material = StandardMaterial3D.new()
	_bezel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bezel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bezel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bezel_material.albedo_color = Color(0.95, 0.90, 0.78, 0.80)
	_bezel_material.render_priority = 4

	_shadow_material = StandardMaterial3D.new()
	_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	_shadow_material.render_priority = 1

	_disc_mesh = MeshInstance3D.new()
	_ring_root.add_child(_disc_mesh)
	_build_disc()
	_beams_mesh = MeshInstance3D.new()
	_ring_root.add_child(_beams_mesh)
	_build_beams()
	_rim_mesh = MeshInstance3D.new()
	_rim_mesh.position = Vector3(0, 0, -34)
	_ring_root.add_child(_rim_mesh)
	_build_rim()
	_stage_mesh = MeshInstance3D.new()
	_ring_root.add_child(_stage_mesh)
	_build_stage()
	_bezel_mesh = MeshInstance3D.new()
	_ring_root.add_child(_bezel_mesh)
	_build_bezel_gpu()
	_frame_mesh = MeshInstance3D.new()
	_ring_root.add_child(_frame_mesh)
	_build_frame()
	_amber_mesh = MeshInstance3D.new()
	_ring_root.add_child(_amber_mesh)
	_build_amber()
	_shadow_mesh = MeshInstance3D.new()
	_shadow_mesh.position = Vector3(0, -26, -2)
	_ring_root.add_child(_shadow_mesh)
	_glow_mesh = MeshInstance3D.new()
	_ring_root.add_child(_glow_mesh)
	_ring_mesh = MeshInstance3D.new()
	_ring_root.add_child(_ring_mesh)


## The playtest advances geometry once before judgement, using the same camera
## and beat that the overlay will draw for this frame.
func prepare_playtest_frame(beat: float, delta: float) -> void:
	time_beat = beat
	_process(delta)


func _process(_delta: float) -> void:
	var proc_start := Time.get_ticks_usec()
	var chart := get_chart()
	if chart == null:
		return
	if follow_app and _app != null and _app.chart != _last_chart_ref:
		_last_chart_ref = _app.chart
		_mesh_dirty = true
		_last_video_path = ""
		_last_background_path = ""
		_video_load_failed = false
		_last_fit_key = ""
		_last_mesh_key = ""
	_update_mouse_tilt(_delta)
	for i in range(_pulses.size() - 1, -1, -1):
		_pulses[i]["age"] = float(_pulses[i].get("age", 0.0)) + _delta
		if float(_pulses[i]["age"]) > 0.62:
			_pulses.remove_at(i)
	for i in range(_arc_flashes.size() - 1, -1, -1):
		_arc_flashes[i]["age"] = float(_arc_flashes[i].get("age", 0.0)) + _delta
		if float(_arc_flashes[i]["age"]) > 0.32:
			_arc_flashes.remove_at(i)
	for i in range(_note_pops.size() - 1, -1, -1):
		_note_pops[i]["age"] = float(_note_pops[i].get("age", 0.0)) + _delta
		if float(_note_pops[i]["age"]) > NOTE_POP_SEC:
			_note_pops.remove_at(i)
	var t := get_time_beat()
	var time_changed := absf(t - _last_process_time) > 0.0005
	var mesh_key := _mesh_key(chart, t)
	var view_changed := _update_transform(t)
	var flat_dirty := _mesh_dirty and not use_3d_ring
	if use_3d_ring and (_mesh_dirty or mesh_key != _last_mesh_key):
		# 形变时每帧重建：30Hz 的几何更新会让环比音符慢半拍，看起来就是卡顿。
		var mesh_start := Time.get_ticks_usec()
		_update_ring_mesh(chart, t)
		_perf_mesh_usec += Time.get_ticks_usec() - mesh_start
		_last_mesh_key = mesh_key
		_last_mesh_usec = Time.get_ticks_usec()
		view_changed = true
	if not use_3d_ring and _mesh_dirty:
		_mesh_dirty = false
	_update_background(chart)
	_update_video(chart, t)
	var beat_phase := fposmod(t, 1.0)
	_glow_material.albedo_color = Color(0.37, 0.92, 0.86, 0.10 + 0.09 * exp(-beat_phase * 7.0))
	if playtest_mode:
		mouse_screen = auto_cursor if auto_cursor.is_finite() else get_local_mouse_position()
		mouse_inside = true
		var perf_now := Time.get_ticks_usec()
		if _perf_since_usec == 0:
			_perf_since_usec = perf_now
		elif perf_now - _perf_since_usec >= 2000000 and _perf_frames > 0:
			var per := float(maxi(1, _perf_frames)) * 1000.0
			if OS.is_debug_build():
				print("[perf] fps=%.0f draw=%.2f proc=%.2f mesh=%.2f | path=%.2f hold=%.2f note=%.2f fx=%.2f hud=%.2f bar=%.2f cursor=%.2f audio=%.2f" % [
					Engine.get_frames_per_second(),
					float(_perf_draw_usec) / float(maxi(1, _perf_frames)) / 1000.0,
					float(_perf_proc_usec) / float(maxi(1, _perf_frames)) / 1000.0,
					float(_perf_mesh_usec) / per,
					float(_perf_sections[1]) / per,
					float(_perf_sections[2]) / per,
					float(_perf_sections[3]) / per,
					float(_perf_sections[4]) / per,
					float(_perf_sections[5]) / per,
					float(_perf_sections[6]) / per,
					float(_perf_sections[7]) / per,
					float(_perf_sections[8]) / per,
				])
			_perf_draw_usec = 0
			_perf_frames = 0
			_perf_sections = [0, 0, 0, 0, 0, 0, 0, 0, 0]
			_perf_proc_usec = 0
			_perf_mesh_usec = 0
			_perf_since_usec = perf_now
	var mouse_moved := mouse_screen.distance_to(_last_mouse_screen) > 0.1
	if mouse_inside and (playtest_mode or (playing and Engine.get_process_frames() % 6 == 0) or mouse_moved):
		_update_cursor()
	_update_cursor_trail(_delta)
	# 场景层只在时间/几何/特效变化时重绘；鼠标移动只触发光标层。
	var needs_overlay := time_changed or view_changed or flat_dirty or not _pulses.is_empty() or not _arc_flashes.is_empty() or not _note_pops.is_empty()
	if needs_overlay:
		_overlay.queue_redraw()
	if mouse_moved or time_changed or view_changed or not _cursor_trail.is_empty():
		_cursor_layer.queue_redraw()
	if use_3d_ring:
		var animate_3d := playing or playtest_mode or _tilt.distance_to(_tilt_target) > 0.01
		# 形变时每帧都要重画：UPDATE_ONCE 渲染完会被引擎改回 DISABLED，
		# 而缓存的 _render_mode 还停在 ONCE，后面的帧就再也不更新（正是卡顿/不动的来源）。
		_update_3d_mode(animate_3d, view_changed or _mesh_dirty or mesh_key != _last_mesh_key)
	_last_process_time = t
	_last_mouse_screen = mouse_screen
	_perf_proc_usec += Time.get_ticks_usec() - proc_start


func _mesh_key(chart: Chart, beat: float) -> String:
	# 关键帧模型：缓存键取“当前在哪两个形状之间 + 插值进度”。
	# 少了 p，形变期间键值不变，环网格就永远停在基础形状上。
	var pair := BoundaryRuntime.pair_at(chart, beat)
	if pair.is_empty():
		return "base:" + chart.default_shape_id
	var from_shape: BoundaryShape = pair.get("from")
	var to_shape: BoundaryShape = pair.get("to")
	var from_id := from_shape.id if from_shape != null else "?"
	var to_id := to_shape.id if to_shape != null else "?"
	return "%s>%s:%.4f" % [from_id, to_id, float(pair.get("p", 0.0))]


func _update_3d_mode(animate: bool, changed: bool) -> void:
	if _subviewport == null:
		return
	# 只在“需要连续帧”和“静止”之间切换；UPDATE_ONCE 会被引擎改回 DISABLED，
	# 用它做逐帧更新会卡在第一帧。
	var desired := SubViewport.UPDATE_ALWAYS if (animate or changed or _force_3d_frame) else SubViewport.UPDATE_DISABLED
	_force_3d_frame = false
	if desired != _render_mode:
		_subviewport.render_target_update_mode = desired
		_render_mode = desired


func _update_mouse_tilt(delta: float) -> void:
	if not mouse_tilt or not (mouse_inside or playtest_mode):
		_tilt_target = Vector2.ZERO
	elif size.x > 1.0 and size.y > 1.0:
		var local := get_local_mouse_position()
		var nx := clampf((local.x - size.x * 0.5) / (size.x * 0.5), -1.0, 1.0)
		var ny := clampf((local.y - size.y * 0.5) / (size.y * 0.5), -1.0, 1.0)
		var amount := 7.0 if playtest_mode else MOUSE_TILT_DEGREES
		_tilt_target = Vector2(-ny * amount, nx * amount)
	var weight := 1.0 - exp(-maxf(0.0, delta) * 10.0)
	_tilt = _tilt.lerp(_tilt_target, weight)
	if _tilt_target == Vector2.ZERO and _tilt.length() < 0.01:
		_tilt = Vector2.ZERO


func _update_transform(beat: float) -> bool:
	var chart := get_chart()
	if chart == null:
		return false
	var view := BoundaryRuntime.eval_view(chart, beat)
	var rotation := float(view.get("rotation", 0.0))
	var tilt_x := float(view.get("tilt_x", 0.0))
	var tilt_y := float(view.get("tilt_y", 0.0))
	var zoom := float(view.get("zoom", 1.0))
	var ellipse := float(view.get("ellipse", 1.0))
	if bool(chart.metadata.get("face_camera", true)):
		# 正对镜头只忽略谱面 ViewState 的倾斜；鼠标视差仍然保留。
		tilt_x = 0.0
		tilt_y = 0.0
		ellipse = 1.0
	if playtest_mode:
		# 试玩只保留平面内旋转 + 鼠标视差，不跟随谱面倾斜。
		tilt_x = 0.0
		tilt_y = 0.0
		ellipse = 1.0
	var key := "%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [rotation, tilt_x, tilt_y, zoom, ellipse, _tilt.x, _tilt.y]
	if key == _last_view_key:
		return false
	_last_view_key = key
	var basis := Basis(Vector3(0, 0, 1), deg_to_rad(rotation))
	basis = basis * Basis(Vector3(1, 0, 0), deg_to_rad(tilt_x + _tilt.x))
	basis = basis * Basis(Vector3(0, 1, 0), deg_to_rad(tilt_y + _tilt.y))
	_ring_root.transform = Transform3D(basis.scaled(Vector3(zoom * ellipse, zoom, zoom)), Vector3(-_tilt.y * 2.8, -_tilt.x * 2.8, 0.0))
	var fit_key := "%.3f|%.3f|%d|%.0f|%.0f" % [zoom, ellipse, 1 if playtest_mode else 0, size.x, size.y]
	if fit_key != _last_fit_key:
		_last_fit_key = fit_key
		_update_camera_fit(chart, zoom, ellipse)
	return true


func _update_camera_fit(chart: Chart, zoom: float, ellipse: float) -> void:
	# 环工作区开关会把预览在两个容器间搬动，搬家途中 resized 先到、节点还没入树。
	if not is_inside_tree() or _camera == null or not _camera.is_inside_tree():
		return
	if _max_design_radius < 0.0:
		_max_design_radius = 520.0
		for shape in chart.sorted_shapes():
			for data in shape.sample_points(32):
				var point: Vector2 = data.point
				_max_design_radius = maxf(_max_design_radius, point.length())
	var aspect := maxf(0.2, size.x / maxf(1.0, size.y))
	# 试玩时把环放大到接近 Estella 的满屏比例；编辑器保持原来的留白。
	var margin := 1.06 if playtest_mode else PREVIEW_MARGIN
	var wanted := _max_design_radius * maxf(0.5, zoom) * maxf(0.5, ellipse) * margin
	var distance := wanted / tan(deg_to_rad(_camera.fov * 0.5)) / minf(1.0, aspect)
	distance = clampf(distance, 500.0, 6000.0)
	_camera.position = Vector3(0, 0, distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _update_ring_mesh(chart: Chart, beat: float) -> void:
	var points := _frame_for(chart, beat).sample_points(96)
	_ring_mesh.mesh = _build_ribbon(points, RING_WIDTH, _ring_material)
	_glow_mesh.mesh = _build_ribbon(points, GLOW_WIDTH, _glow_material)
	_shadow_mesh.mesh = _build_ribbon(points, 30.0, _shadow_material)
	_last_mesh_beat = beat
	_mesh_dirty = false


func _build_beams() -> void:
	# 终末地式舞台不再使用八束光，保留空节点避免影响旧的渲染开关。
	_beams_mesh.mesh = ImmediateMesh.new()


func _build_rim() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _rim_material)
	var inner := 512.0
	var outer := 600.0
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		var p0 := Vector2(cos(a0), sin(a0))
		var p1 := Vector2(cos(a1), sin(a1))
		mesh.surface_add_vertex(Vector3(p0.x * inner, p0.y * inner, 0.0))
		mesh.surface_add_vertex(Vector3(p0.x * outer, p0.y * outer, 0.0))
		mesh.surface_add_vertex(Vector3(p1.x * outer, p1.y * outer, 0.0))
		mesh.surface_add_vertex(Vector3(p0.x * inner, p0.y * inner, 0.0))
		mesh.surface_add_vertex(Vector3(p1.x * outer, p1.y * outer, 0.0))
		mesh.surface_add_vertex(Vector3(p1.x * inner, p1.y * inner, 0.0))
	mesh.surface_end()
	_rim_mesh.mesh = mesh


func _build_disc() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _disc_material)
	var radius := 640.0
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, -48.0))
		mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, -48.0))
	mesh.surface_end()
	_disc_mesh.mesh = mesh


func _build_stage() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _stage_material)
	for radius in [360.0, 420.0, 620.0]:
		var steps := 96
		for i in steps:
			var a0 := TAU * float(i) / float(steps)
			var a1 := TAU * float(i + 1) / float(steps)
			mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, -30.0))
			mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, -30.0))
	# 稀疏斜向刻线，替代原来的八条径向线。
	for angle in [-135.0, -45.0, 45.0, 135.0]:
		var a := deg_to_rad(angle)
		var direction := Vector2(cos(a), sin(a))
		for offset in [-2.0, 2.0]:
			var normal: Vector2 = Vector2(-direction.y, direction.x) * offset
			mesh.surface_add_vertex(Vector3((direction * 520.0 + normal).x, (direction * 520.0 + normal).y, -30.0))
			mesh.surface_add_vertex(Vector3((direction * 590.0 + normal).x, (direction * 590.0 + normal).y, -30.0))
	mesh.surface_end()
	_stage_mesh.mesh = mesh


func _build_frame() -> void:
	# 白色分段外弧：角度取自终末地菜单的 5 段开口弧。
	var segments := [[-40.5, -10.0], [-4.0, 44.0], [138.0, 168.0], [174.0, 204.0], [210.0, 234.0]]
	_frame_mesh.mesh = _build_arc_mesh(segments, 505.0, 9.8, _frame_material)


func _build_amber() -> void:
	var segments := [[20.0, 44.0], [137.0, 160.0]]
	_amber_mesh.mesh = _build_arc_mesh(segments, 466.0, 1.6, _amber_material)


func _build_arc_mesh(segments: Array, radius: float, width: float, material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var half := width * 0.5
	for segment in segments:
		var a0 := deg_to_rad(float(segment[0]))
		var a1 := deg_to_rad(float(segment[1]))
		var steps := maxi(8, int(absf(a1 - a0) * radius / 18.0))
		for i in steps:
			var t0 := a0 + (a1 - a0) * float(i) / float(steps)
			var t1 := a0 + (a1 - a0) * float(i + 1) / float(steps)
			var p0 := Vector2(cos(t0), sin(t0)) * radius
			var p1 := Vector2(cos(t1), sin(t1)) * radius
			var n0 := Vector2(-sin(t0), cos(t0)) * half
			var n1 := Vector2(-sin(t1), cos(t1)) * half
			mesh.surface_add_vertex(Vector3(p0.x + n0.x, p0.y + n0.y, 0.0))
			mesh.surface_add_vertex(Vector3(p0.x - n0.x, p0.y - n0.y, 0.0))
			mesh.surface_add_vertex(Vector3(p1.x - n1.x, p1.y - n1.y, 0.0))
			mesh.surface_add_vertex(Vector3(p0.x + n0.x, p0.y + n0.y, 0.0))
			mesh.surface_add_vertex(Vector3(p1.x - n1.x, p1.y - n1.y, 0.0))
			mesh.surface_add_vertex(Vector3(p1.x + n1.x, p1.y + n1.y, 0.0))
	mesh.surface_end()
	return mesh


func _build_bezel_gpu() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _bezel_material)
	# 四条细凹槽
	for radius in [470.0, 474.0, 478.0, 482.0]:
		for i in 96:
			var a0 := TAU * float(i) / 96.0
			var a1 := TAU * float(i + 1) / 96.0
			mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, 0.0))
			mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, 0.0))
	# 稀疏刻度：只保留 5 个方向的小三角，模仿菜单里的黄色旗标。
	for angle in [-101.0, -162.0, -37.0, 29.0, 141.0]:
		var a := deg_to_rad(angle)
		var p := Vector2(cos(a), sin(a)) * 455.0
		var outward := Vector2(cos(a), sin(a))
		var side := Vector2(-outward.y, outward.x) * 7.0
		mesh.surface_add_vertex(Vector3(p.x + side.x, p.y + side.y, 0.0))
		mesh.surface_add_vertex(Vector3((p + outward * 13.0).x, (p + outward * 13.0).y, 0.0))
		mesh.surface_add_vertex(Vector3((p + outward * 13.0).x, (p + outward * 13.0).y, 0.0))
		mesh.surface_add_vertex(Vector3(p.x - side.x, p.y - side.y, 0.0))
	mesh.surface_end()
	_bezel_mesh.mesh = mesh


func _build_ribbon(points: Array[Dictionary], width: float, material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var half := width * 0.5
	var count := points.size()
	# 每个点取相邻两条边的平均法线（miter）：段与段之间共用顶点，
	# 接缝不会裂开，折角也不会出现锯齿状缺口。
	var normals: Array[Vector2] = []
	normals.resize(count)
	for i in count:
		var prev: Vector2 = points[(i - 1 + count) % count].point
		var next: Vector2 = points[(i + 1) % count].point
		var tangent := next - prev
		if tangent.length_squared() < 0.000001:
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x).normalized() * half
		# 尖角限制：miter 最多 2 倍宽度，避免长刺。
		if normal.length() > half * 2.0:
			normal = normal.normalized() * half * 2.0
		normals[i] = normal
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		if bool(a.get("gap", false)) or bool(b.get("gap", false)):
			continue
		var pa: Vector2 = a.point
		var pb: Vector2 = b.point
		if (pb - pa).length_squared() < 0.000001:
			continue
		var na: Vector2 = normals[i]
		var nb: Vector2 = normals[(i + 1) % count]
		var v0 := pa + na
		var v1 := pa - na
		var v2 := pb + nb
		var v3 := pb - nb
		mesh.surface_add_vertex(Vector3(v0.x, v0.y, 0.0))
		mesh.surface_add_vertex(Vector3(v1.x, v1.y, 0.0))
		mesh.surface_add_vertex(Vector3(v2.x, v2.y, 0.0))
		mesh.surface_add_vertex(Vector3(v1.x, v1.y, 0.0))
		mesh.surface_add_vertex(Vector3(v3.x, v3.y, 0.0))
		mesh.surface_add_vertex(Vector3(v2.x, v2.y, 0.0))
	mesh.surface_end()
	return mesh


func _update_background(chart: Chart) -> void:
	var path := String(chart.metadata.get("background", ""))
	# 新标签页没有背景时必须清掉上一张图；不能因为缓存键也是空串就直接返回。
	if path.is_empty():
		_last_background_path = ""
		if _background_image.texture != null or _background_image.visible:
			_background_image.texture = null
			_background_image.visible = false
		return
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		if _app != null and not _app.chart_path.is_empty():
			resolved = ChartIO.resolve_path(_app.chart_path, path)
	# 用解析后的绝对路径做缓存键：不同标签页可以有相同的相对文件名。
	if resolved == _last_background_path:
		return
	_last_background_path = resolved
	var texture: Texture2D = null
	if resolved.begins_with("res://"):
		if ResourceLoader.exists(resolved):
			texture = load(resolved) as Texture2D
	else:
		var image := Image.load_from_file(ProjectSettings.globalize_path(resolved) if resolved.begins_with("user://") else resolved)
		if image != null and image.get_width() > 0 and image.get_height() > 0:
			texture = ImageTexture.create_from_image(image)
	_background_image.texture = texture
	_background_image.visible = background_image_visible(texture != null, _video != null and _video.stream != null)
	_background_image.modulate = Color(1, 1, 1, background_alpha(background_brightness))


## 静图基准不透明度 32%；明暗系数是全局乘数（1.0 = 默认）。
static func background_alpha(brightness: float) -> float:
	return BACKGROUND_ALPHA * maxf(0.0, brightness)


## 有 BGA 时不叠加谱面背景图：两张背景一起画既脏又浪费。
static func background_image_visible(has_texture: bool, has_video: bool) -> bool:
	return has_texture and not has_video


## BGA 的不透明度：谱面自己的 opacity × 全局明暗系数。
static func video_alpha(chart_opacity: float, brightness: float) -> float:
	return clampf(chart_opacity, 0.0, 1.0) * maxf(0.0, brightness)


## 背景明暗：静图和 BGA 共用一个系数（1.0 = 默认观感）。
func set_background_brightness(value: float) -> void:
	# 设置项封顶 100%；这里再钳一次，防止别处直接赋值绕过上限。
	background_brightness = clampf(value, 0.0, 1.0)
	if _background_image != null:
		_background_image.modulate = Color(1, 1, 1, background_alpha(background_brightness))


## 暂停时连 BGA 一起停；恢复后 _update_video 会把播放位置重新对齐。
func set_video_paused(value: bool) -> void:
	video_paused = value
	if _video != null:
		_video.paused = value


func _update_video(chart: Chart, beat: float) -> void:
	var path := chart.video_path
	if path.is_empty():
		_video_job_token += 1
		_video.visible = false
		_video.stream = null
		_refresh_background_layering()
		return
	if path != _last_video_path:
		_last_video_path = path
		_video_load_failed = false
		_video.stream = null
		_video.visible = false
		_video_job_token += 1
		var resolved := path
		if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
			if _app != null and not _app.chart_path.is_empty():
				resolved = ChartIO.resolve_path(_app.chart_path, path)
		_start_video_load(resolved, _video_job_token)
	_refresh_background_layering()
	if _video.stream == null:
		return
	_video.modulate = Color(1, 1, 1, video_alpha(chart.video_opacity, background_brightness))
	if not is_equal_approx(_video.speed_scale, playback_rate):
		_video.speed_scale = maxf(0.1, playback_rate)
	if video_paused:
		_video.paused = true
		return
	var ms := chart.timing.beat_to_chart_ms(beat) - chart.offset_ms + chart.video_offset_ms
	var seconds := maxf(0.0, ms / 1000.0)
	if not playing:
		if not _video.is_playing():
			_video.play()
		_video.paused = true
		if absf(_video.stream_position - seconds) > 0.05:
			_video.stream_position = seconds
	elif _video.paused:
		_video.paused = false
		_video.stream_position = seconds
	elif absf(_video.stream_position - seconds) > 0.20:
		_video.stream_position = seconds


## 有 BGA 时不叠加谱面背景图：两张背景一起画既脏又浪费。
func _refresh_background_layering() -> void:
	_background_image.visible = background_image_visible(_background_image.texture != null, _video.stream != null)


## 优先直接解码（gdffmpeg）：mp4 / webm 等不再转码；解码库缺失才退回转码缓存。
func _start_video_load(resolved: String, token: int) -> void:
	var direct := ChartIO.video_stream_from_path(resolved)
	if direct != null:
		_attach_video(direct)
		return
	if MediaIO.is_native_video(resolved):
		_video_load_failed = true
		notice.emit("视频无法解码：%s" % resolved.get_file(), "warning")
		return
	if FileAccess.file_exists(MediaIO.video_cache_path(resolved)):
		_attach_video(ChartIO.video_stream_from_path(MediaIO.video_cache_path(resolved)))
		return
	var tree := get_tree()
	if tree == null:
		return
	notice.emit("没有直接解码库，后台转码中（不阻塞编辑）：%s" % resolved.get_file(), "info")
	var result := await MediaIO.prepare_video_async(resolved, tree)
	if token != _video_job_token or not is_inside_tree():
		return
	if result.is_empty():
		_video_load_failed = true
		notice.emit("视频不可用：%s" % MediaIO.last_error, "warning")
		return
	_attach_video(ChartIO.video_stream_from_path(result))


func _attach_video(stream: VideoStream) -> void:
	if stream == null:
		_video_load_failed = true
		_video.visible = false
		notice.emit("视频无法解码；保留路径，不影响编辑。", "warning")
		return
	_video.stream = stream
	_video.visible = true
	_video.play()
	_video.paused = true
	_refresh_background_layering()


## 每次进试玩都从干净的轨迹开始（上一局的擦除不能留到下局）。
func reset_path_cuts() -> void:
	path_cuts.clear()
	path_sector_cuts.clear()
	path_cut_versions.clear()
	_path_head_state.clear()
	_path_runs_cache.clear()
	clear_note_states()


## 星头判定结果：决定圆和下落星星什么时候开始淡出。
func set_path_head_state(note_id: int, hit: bool, beat: float) -> void:
	_path_head_state[note_id] = {"hit": hit, "beat": beat}
	if _overlay != null:
		_overlay.queue_redraw()


## 试玩判定结果："hit" / "miss" 让音符当帧退场；"holding" 让 hold 收起头部。
## beat 只给 hold 的 MISS 用：整条从这一刻起淡出。
func set_note_state(note_id: int, state: String, beat: float = NAN) -> void:
	note_states[note_id] = state
	if not is_nan(beat):
		note_state_beats[note_id] = beat
	if _overlay != null:
		_overlay.queue_redraw()


func note_state(note_id: int) -> String:
	return String(note_states.get(note_id, ""))


static func note_is_retired(state: String) -> bool:
	return state == "hit" or state == "miss"


func clear_note_states() -> void:
	_note_pops.clear()
	if note_states.is_empty():
		if _overlay != null:
			_overlay.queue_redraw()
		return
	note_states.clear()
	note_state_beats.clear()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_chart_changed() -> void:
	_sorted_notes_chart = null
	path_cuts.clear()
	path_sector_cuts.clear()
	_path_sector_cache.clear()
	_path_head_state.clear()
	note_states.clear()
	note_state_beats.clear()
	path_cut_versions.clear()
	_path_runs_cache.clear()
	_boundary_frame_cache = null
	_path_local_cache.clear()
	_max_design_radius = -1.0
	_mesh_dirty = true
	_last_video_path = ""
	_video_job_token += 1
	video_paused = false
	_last_background_path = ""
	_last_fit_key = ""
	_last_mesh_key = ""
	_force_3d_frame = true
	queue_redraw()


func _on_chart_live_changed() -> void:
	_sorted_notes_chart = null
	path_cuts.clear()
	path_sector_cuts.clear()
	_path_sector_cache.clear()
	_path_head_state.clear()
	path_cut_versions.clear()
	_path_runs_cache.clear()
	_boundary_frame_cache = null
	_path_local_cache.clear()
	# Note/region drags only change the overlay. Boundary dragging marks the
	# mesh dirty in _update_drag(), where the actual geometry is edited.
	if _mesh_dirty:
		_max_design_radius = -1.0
		_last_fit_key = ""
		_avg_radius_key = ""
		_force_3d_frame = true
	if _overlay != null:
		_overlay.queue_redraw()


func _on_selection_changed() -> void:
	queue_redraw()


func _on_playhead_changed(_beat: float) -> void:
	pass


func _on_tool_changed(_tool: String) -> void:
	queue_redraw()


func _on_resized() -> void:
	_last_fit_key = ""
	_render_mode = -1
	_force_3d_frame = true
	if _subviewport != null:
		_subviewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	var chart := get_chart()
	if chart != null:
		var view := current_view()
		_update_camera_fit(chart, float(view.get("zoom", 1.0)), float(view.get("ellipse", 1.0)))


func _on_mouse_entered() -> void:
	mouse_inside = true
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_update_cursor()
	_cursor_layer.queue_redraw()


func _on_mouse_exited() -> void:
	mouse_inside = false
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_cursor_layer.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if ring_edit_mode and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			ring_zoom.emit(0.02)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ring_zoom.emit(-0.02)
			accept_event()
			return
	if event is InputEventMouseMotion:
		mouse_screen = event.position
		if _ring_rotating:
			ring_rotate.emit((event.position.x - _ring_rot_last) * 0.4)
			_ring_rot_last = event.position.x
			accept_event()
			return
		if playtest_mode:
			_cursor_layer.queue_redraw()
			accept_event()
			return
		if interactive and not playtest_mode:
			if _drag_vertex >= 0:
				_update_drag(event.position)
			elif _drag_visual >= 0:
				_update_visual_drag(event.position)
			elif _drawing_red:
				_update_cursor()
				_update_red_drag(event.position)
			elif _drawing_path:
				_append_path_point(event.position)
		_update_cursor()
		_cursor_layer.queue_redraw()
		if _drag_vertex >= 0 or _drag_visual >= 0 or _drawing_red or _drawing_path:
			_overlay.queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_screen = event.position
		if event.pressed:
			_on_left_press(event)
		else:
			_on_left_release(event)
		accept_event()


func _on_left_press(event: InputEventMouseButton) -> void:
	_update_cursor()
	if not interactive or playtest_mode:
		return
	if _app == null:
		return
	if ring_edit_mode:
		var vertex_pick := _pick_vertex(event.position)
		if vertex_pick >= 0:
			_drag_vertex = vertex_pick
			_app.select_segment(vertex_pick)
			_app.begin_edit()
			return
		if _pick_note(event.position) < 0:
			_ring_rotating = true
			_ring_rot_last = event.position.x
			_app.begin_edit()
			accept_event()
			return
	if _app.boundary_mode:
		if event.double_click:
			_split_segment()
			return
		var vertex := _pick_vertex(event.position)
		if vertex >= 0:
			_drag_vertex = vertex
			_app.select_segment(vertex)
			_app.begin_edit()
			return
		var segment_index := _nearest_segment_index(event.position)
		if segment_index >= 0:
			_app.select_segment(segment_index)
			return
	if _app.tool == "limit":
		if not cursor_valid:
			return
		var chart := get_chart()
		if chart == null:
			return
		var start_beat: float = _app.snap_beat(get_time_beat())
		var region := Region.new(chart.next_region_id(), start_beat, start_beat + 1.0)
		region.angle = cursor_u * 360.0
		region.width = 30.0
		_app.begin_edit()
		chart.regions.append(region)
		_app.select_region(region.id)
		_red_region = region
		_red_start_u = cursor_u
		_red_start_beat = start_beat
		_red_start_mouse = event.position
		_drawing_red = true
		return
	if _app.tool == "select":
		var visual := _pick_visual_node(event.position)
		if visual >= 0:
			_drag_visual = visual
			_drag_visual_note = _app.get_selected_note()
			_drag_visual_start = event.position
			if _drag_visual_note.type == "path":
				var trace_count: int = _drag_visual_note.trace_pts.size()
				if visual < trace_count:
					var point: Dictionary = _drag_visual_note.trace_pts[visual]
					_drag_visual_db = float(point.get("db", 0.0))
				else:
					var design: Dictionary = _drag_visual_note.visual_pts[visual - trace_count]
					_drag_visual_db = float(design.get("db", 0.0))
					_drag_visual_da = float(design.get("da", 0.0))
			else:
				var point: Dictionary = _drag_visual_note.visual_pts[visual]
				_drag_visual_db = float(point.get("db", 0.0))
				_drag_visual_da = float(point.get("da", 0.0))
			_app.begin_edit()
			return
	if _app.tool == "path":
		if cursor_valid:
			_drawing_path = true
			_path_head_angle = fposmod(cursor_u * 360.0, 360.0)
			_path_points.clear()
			_path_points.append(Vector2(cos(deg_to_rad(_path_head_angle)), sin(deg_to_rad(_path_head_angle))))
		return
	if _app.tool in ["tap", "hold", "path", "anchor", "bell"]:
		if cursor_valid:
			_create_note(_app.tool)
		return
	if _app.tool == "select":
		var note_id := _pick_note(event.position)
		if note_id >= 0:
			_app.select_note(note_id)


func _on_left_release(_event: InputEventMouseButton) -> void:
	if _ring_rotating:
		_ring_rotating = false
		if _app != null:
			_app.finish_edit()
	if _drag_visual >= 0:
		_drag_visual = -1
		_drag_visual_note = null
		if _app != null:
			_app.finish_edit()
	if _drag_vertex >= 0:
		_drag_vertex = -1
		if _app != null:
			_app.finish_edit()
		_warn_if_invalid()
	if _drawing_red:
		_drawing_red = false
		_red_region = null
		if _app != null:
			_app.finish_edit()
	if _drawing_path:
		_drawing_path = false
		_create_path()


func _update_drag(screen_position: Vector2) -> void:
	if _drag_vertex < 0:
		return
	var shape := _active_shape()
	if shape == null:
		return
	var design := _screen_to_ring_plane(screen_position)
	if not design.is_finite():
		return
	shape.set_vertex(_drag_vertex, design)
	_app.touch_chart()
	_mesh_dirty = true


func _update_visual_drag(screen_position: Vector2) -> void:
	if _drag_visual_note == null or _drag_visual < 0:
		return
	var design := _screen_to_ring_plane(screen_position)
	if not design.is_finite():
		return
	if _drag_visual_note.type == "path":
		var trace_count: int = _drag_visual_note.trace_pts.size()
		if _drag_visual >= trace_count:
			var design_index := _drag_visual - trace_count
			if design_index >= _drag_visual_note.visual_pts.size():
				return
			var marker: Dictionary = _drag_visual_note.visual_pts[design_index]
			var duration := _drag_visual_note.duration()
			marker["db"] = clampf(_drag_visual_db + (screen_position.y - _drag_visual_start.y) / 36.0, 0.001, maxf(0.001, duration - 0.001))
			marker["da"] = JudgeMath.angle_delta(_drag_visual_note.angle, rad_to_deg(atan2(design.y, design.x)))
			_app.touch_chart()
			return
		if _drag_visual >= _drag_visual_note.trace_pts.size():
			return
		var local := _design_to_path_local(design)
		var point: Dictionary = _drag_visual_note.trace_pts[_drag_visual]
		point["x"] = local.x
		point["y"] = local.y
		if _drag_visual == 0:
			_drag_visual_note.angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
		elif _drag_visual == _drag_visual_note.trace_pts.size() - 1:
			_drag_visual_note.tail_angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
		_app.touch_chart()
		return
	if _drag_visual >= _drag_visual_note.visual_pts.size():
		return
	var point: Dictionary = _drag_visual_note.visual_pts[_drag_visual]
	var duration := _drag_visual_note.duration()
	point["db"] = clampf(_drag_visual_db + (screen_position.y - _drag_visual_start.y) / 36.0, 0.001, maxf(0.001, duration - 0.001))
	var angle := rad_to_deg(atan2(design.y, design.x))
	point["da"] = JudgeMath.angle_delta(_drag_visual_note.angle, angle)
	_app.touch_chart()


func _design_to_path_local(design: Vector2) -> Vector2:
	var chart := get_chart()
	if chart == null or design.length() <= 0.001:
		return Vector2(0.7, 0.0)
	var angle := fposmod(rad_to_deg(atan2(design.y, design.x)), 360.0)
	var data := _boundary_point(chart, angle / 360.0, get_time_beat())
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	var ring_radius := maxf(0.001, (data.point as Vector2).length())
	return design / ring_radius


func _update_red_drag(screen_position: Vector2) -> void:
	if _red_region == null:
		return
	var delta := (cursor_u - _red_start_u) * 360.0
	if absf(delta) < 8.0:
		delta = 30.0 if delta >= 0.0 else -30.0
	_red_region.angle = fposmod(_red_start_u * 360.0 + delta * 0.5, 360.0)
	_red_region.width = clampf(absf(delta), 10.0, 359.0)
	var beat := _red_start_beat + (screen_position.y - _red_start_mouse.y) / 40.0
	_red_region.start_beat = minf(_red_start_beat, beat)
	_red_region.end_beat = maxf(_red_start_beat + 0.25, minf(beat, _red_start_beat + 4.0))
	_app.touch_chart()


func _append_path_point(screen: Vector2) -> void:
	var design := _screen_to_ring_plane(screen)
	if not design.is_finite():
		return
	var local := _design_to_path_local(design)
	if not local.is_finite():
		return
	var radius := local.length()
	if radius <= 0.001:
		return
	radius = clampf(radius, 0.06, 0.985)
	local = local.normalized() * radius
	if _path_points.is_empty() or _path_points[-1].distance_to(local) > 0.012:
		_path_points.append(local)


func _create_path() -> void:
	if _app == null:
		_path_points.clear()
		return
	var chart := get_chart()
	if chart == null or _path_points.is_empty():
		_path_points.clear()
		return
	if _path_points.size() < 2:
		var angle := deg_to_rad(_path_head_angle + 60.0)
		_path_points.append(Vector2(cos(angle), sin(angle)) * 0.70)
	var start: float = _app.snap_beat(get_time_beat())
	var note := Note.new("path", start, _path_head_angle, 62.0)
	note.id = chart.next_note_id()
	note.end_beat = start + 1.0
	note.tail_width = 45.0
	note.tolerance = 0.24
	note.samples_per_beat = 4.0
	note.space = "plane"
	var last: Vector2 = _path_points[-1]
	note.tail_angle = fposmod(rad_to_deg(atan2(last.y, last.x)), 360.0)
	for i in _path_points.size():
		var point := _path_points[i]
		note.trace_pts.append({
			"x": point.x,
			"y": point.y,
			"db": note.duration() * float(i) / float(_path_points.size() - 1),
		})
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)
	_path_points.clear()


func _create_note(type: String) -> void:
	if _app == null or not cursor_valid:
		return
	var chart := get_chart()
	if chart == null:
		return
	var beat: float = _app.snap_beat(get_time_beat())
	var angle := fposmod(cursor_u * 360.0, 360.0)
	var added: Array[Note] = []
	if type == "anchor":
		# Anchor 是双押配置：一次放两颗同拍反向的锚点。
		added = chart.make_anchor_pair(beat, angle)
	else:
		var note := Note.new(type, beat, angle, 60.0)
		note.id = chart.next_note_id()
		match type:
			"hold":
				note.end_beat = beat + 1.0
				note.hold = true
				note.hold_style = "straight"
			"path":
				note.end_beat = beat + 1.0
				note.tail_angle = fposmod(angle + 60.0, 360.0)
				note.tail_width = 45.0
				note.tolerance = 0.24
				note.samples_per_beat = 4.0
				note.trace_pts = [
					{"x": cos(deg_to_rad(angle)), "y": sin(deg_to_rad(angle)), "db": 0.0},
					{"x": cos(deg_to_rad(note.tail_angle)) * 0.70, "y": sin(deg_to_rad(note.tail_angle)) * 0.70, "db": 1.0},
				]
			"bell":
				note.width = Note.BELL_MAX_WIDTH
				note.center_u = cursor_u
				note.radius = 26.0
		added = [note]
	_app.begin_edit()
	for item in added:
		chart.notes.append(item)
	_app.finish_edit()
	_app.select_note(added[0].id)


func _pick_vertex(screen: Vector2) -> int:
	var shape := _active_shape()
	if shape == null:
		return -1
	var best := -1
	var best_distance := 18.0
	var points := shape.vertices()
	for index in points.size():
		var distance := project_design(points[index]).distance_to(screen)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## 松手后只提示，不回退：编辑中允许暂时不合法，保存/试玩时才拦。
func _warn_if_invalid() -> void:
	var shape := _active_shape()
	if shape == null:
		return
	var issues := shape.validate()
	if not issues.is_empty():
		notice.emit("%s（保存前需要修正）" % issues[0], "warning")


func _nearest_segment_index(screen: Vector2) -> int:
	var shape := _active_shape()
	if shape == null:
		return -1
	var chart := get_chart()
	if chart == null:
		return -1
	var result := BoundaryRuntime.nearest_u(chart, get_time_beat(), screen, func(point: Vector2) -> Vector2: return project_design(point), 512)
	if float(result["distance"]) > 28.0:
		return -1
	var u := float(result["u"])
	var segment := shape.segment_at(u)
	if segment == null:
		return -1
	var sorted := shape.sorted_segments()
	return sorted.find(segment)


func _pick_note(screen: Vector2) -> int:
	var chart := get_chart()
	if chart == null:
		return -1
	var t := get_time_beat()
	var pre := _pre_read_beats(chart, t)
	var best := -1
	var best_distance := 20.0
	for note in chart.notes:
		match note.type:
			"path":
				var head := _flying_position(chart, note.angle, note.beat, t, pre)
				var tail := _flying_position(chart, note.tail_angle, note.end_beat, t, pre)
				if head.distance_to(screen) < best_distance:
					best_distance = head.distance_to(screen)
					best = note.id
				if tail.distance_to(screen) < best_distance:
					best_distance = tail.distance_to(screen)
					best = note.id
			_:
				var u := note.center_u if note.type == "bell" else fposmod(note.angle, 360.0) / 360.0
				var target := _flying_position(chart, u * 360.0, note.beat, t, pre)
				var boundary := project_u(u, t)
				var distance := minf(target.distance_to(screen), boundary.distance_to(screen))
				if distance < best_distance:
					best_distance = distance
					best = note.id
	return best


func _active_shape() -> BoundaryShape:
	var chart := get_chart()
	if chart == null:
		return null
	if follow_app and _app != null:
		var selected: BoundaryShape = _app.get_selected_shape()
		if selected != null:
			return selected
	return chart.get_default_shape()


func _split_segment() -> void:
	if _app == null:
		return
	var shape := _active_shape()
	if shape == null:
		return
	if shape.vertex_count() >= BoundaryShape.MAX_VERTICES:
		notice.emit("顶点数已达上限 %d" % BoundaryShape.MAX_VERTICES, "warning")
		return
	var index := _nearest_segment_index(mouse_screen)
	if index < 0:
		return
	_app.begin_edit()
	if shape.insert_vertex(index):
		_app.select_segment(mini(index + 1, shape.vertex_count() - 1))
	_app.finish_edit()
	_mesh_dirty = true


func _pre_read_beats(chart: Chart, beat: float) -> float:
	return chart.pre_read_ms / maxf(0.1, flow_scale) / 60000.0 * chart.timing.bpm_at(beat)


## 预读时长（毫秒）。和 BPM 无关，所以变 BPM 时不会跳。
func _pre_read_ms(chart: Chart) -> float:
	return maxf(30.0, chart.pre_read_ms / maxf(0.1, flow_scale))


## 这个音符开始从圆心飞出的拍号（毫秒反推，变 BPM 处连续）。
func _spawn_beat(chart: Chart, target_beat: float) -> float:
	return chart.timing.spawn_beat(target_beat, _pre_read_ms(chart))


## 0..1 的接近进度（毫秒恒速，不会在变 BPM 时忽然跳到一半）。
func _approach(chart: Chart, target_beat: float, current_beat: float) -> float:
	return chart.timing.approach(target_beat, current_beat, _pre_read_ms(chart))


## 星星从圆心落到环上的时长（固定 0.5 秒，换算成拍；不超过预读）。
func _star_fall_beats(chart: Chart, beat: float) -> float:
	var pre := _pre_read_beats(chart, beat)
	var bpm := chart.timing.bpm_at(beat)
	return clampf(0.5 * bpm / 60.0, 0.15, maxf(0.15, pre))


## 屏幕点到圆心的距离占环半径的比例 → min_scale..max_scale。
## 用来做“离圆心越远，头越大”的星头缩放。
func _radial_scale(point: Vector2, min_scale: float, max_scale: float, beat: float = 0.0) -> float:
	if not _valid_point(point):
		return max_scale
	var center := project_design(Vector2.ZERO)
	var ring := 0.0
	for u in [0.0, 0.25, 0.5, 0.75]:
		var edge := project_u(u, beat)
		if _valid_point(edge):
			ring = maxf(ring, center.distance_to(edge))
	if ring <= 1.0:
		return max_scale
	return lerpf(min_scale, max_scale, clampf(center.distance_to(point) / ring, 0.0, 1.0))


## 星星开始下落（落到环上 0.5 秒前）的拍号。
func _fall_beat(chart: Chart, target_beat: float) -> float:
	return chart.timing.spawn_beat(target_beat, minf(_pre_read_ms(chart), 500.0))


func _flying_position(chart: Chart, angle: float, target_beat: float, current_beat: float, _pre: float) -> Vector2:
	var u := fposmod(angle, 360.0) / 360.0
	var boundary := project_u(u, current_beat)
	var center := project_design(Vector2.ZERO)
	return center.lerp(boundary, _approach(chart, target_beat, current_beat))


func _update_cursor_trail(delta: float) -> void:
	for i in range(_cursor_trail.size() - 1, -1, -1):
		var age := float(_cursor_trail[i].get("age", 0.0)) + delta
		_cursor_trail[i]["age"] = age
		if age > 0.26:
			_cursor_trail.remove_at(i)
	if not mouse_inside:
		_cursor_trail.clear()
		return
	var moved := _last_mouse_screen.distance_to(mouse_screen)
	if moved <= 1.0:
		return
	_cursor_trail.append({"pos": mouse_screen, "age": 0.0})
	# 拖尾长度按画质项；快速划动时再缩短，减少绘制量。
	var cap := 28
	match cursor_trail_mode:
		"off":
			_cursor_trail.clear()
			return
		"short":
			cap = 12
	if moved > 60.0:
		cap = mini(cap, 8)
	while _cursor_trail.size() > cap:
		_cursor_trail.pop_front()


func _update_cursor() -> void:
	var chart := get_chart()
	if chart == null:
		return
	if playtest_mode:
		# 试玩完全按鼠标屏幕位置判定（osu 式自由移动），不再反解环上角度。
		# 仍要刷新平均半径缓存：音符缩放和光标尺寸都靠它。
		var center_pt := project_design(Vector2.ZERO)
		var average_key := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, get_time_beat()), _last_view_key, size.x, size.y]
		if average_key != _avg_radius_key:
			_avg_radius_key = average_key
			var total := 0.0
			var counted := 0
			var samples := 12
			for i in samples:
				var sample_point := project_u(float(i) / float(samples), get_time_beat())
				if _valid_point(sample_point):
					total += sample_point.distance_to(center_pt)
					counted += 1
			_avg_radius_cache = total / float(maxi(1, counted)) if counted > 0 else 100.0
		cursor_valid = true
		return
	var t := get_time_beat()
	# 鼠标和边界几何都没变时，直接复用上一帧的 u，避免每帧 96 次反解。
	var cache_key := "%s|%.1f|%.1f|%s" % [_mesh_key(chart, t), mouse_screen.x, mouse_screen.y, _last_view_key]
	if cache_key == _cursor_cache_key:
		return
	_cursor_cache_key = cache_key
	var result := BoundaryRuntime.nearest_u(chart, t, mouse_screen, func(point: Vector2) -> Vector2: return project_design(point), 96, _frame_for(chart, t))
	var u := float(result["u"])
	var distance := float(result["distance"])
	var center := project_design(Vector2.ZERO)
	var average_key := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, t), _last_view_key, size.x, size.y]
	if average_key != _avg_radius_key:
		_avg_radius_key = average_key
		var total := 0.0
		var counted := 0
		var samples := 12
		for i in samples:
			var sample_point := project_u(float(i) / float(samples), t)
			if _valid_point(sample_point):
				total += sample_point.distance_to(center)
				counted += 1
		_avg_radius_cache = total / float(maxi(1, counted)) if counted > 0 else 100.0
	var average := _avg_radius_cache
	# 判定环吸附范围：环内整片 + 环外再留一大段缓冲，边缘稍偏也不会失效。
	var threshold := maxf(64.0, average * 0.75)
	var inside_circle := mouse_screen.distance_to(center) <= average * 1.15
	var near_center := mouse_screen.distance_to(center) < average * 0.05
	var valid := (inside_circle or distance <= threshold) and not near_center
	if playtest_mode:
		# Estella 式外环：内圈外整片有效，鼠标离开环/舞台后仍按最近 u 判定。
		valid = mouse_screen.distance_to(center) >= average * 0.45
	elif not mouse_inside:
		valid = false
	cursor_u = u
	cursor_valid = valid
	if _last_cursor_emit.distance_to(Vector2(u, 1.0 if valid else 0.0)) > 0.0001:
		_last_cursor_emit = Vector2(u, 1.0 if valid else 0.0)
		cursor_changed.emit(u, valid)


func _screen_to_ring_plane(screen: Vector2) -> Vector2:
	if _camera == null or _ring_root == null:
		return Vector2(INF, INF)
	var normal := (_ring_root.transform.basis * Vector3(0, 0, 1)).normalized()
	var plane := Plane(normal, -normal.dot(_ring_root.transform.origin))
	var hit: Variant = plane.intersects_ray(_camera.project_ray_origin(screen), _camera.project_ray_normal(screen))
	if hit == null:
		return Vector2(INF, INF)
	var hit_point: Vector3 = hit
	var local: Vector3 = _ring_root.transform.affine_inverse() * hit_point
	return Vector2(local.x, local.y)


func project_design(point: Vector2) -> Vector2:
	if _camera == null or _ring_root == null:
		return Vector2.ZERO
	var world: Vector3 = _ring_root.transform * Vector3(point.x, point.y, 0.0)
	return _camera.unproject_position(world)


func _frame_for(chart: Chart, beat: float) -> BoundaryFrame:
	if _boundary_frame_cache == null or _boundary_frame_cache.chart != chart or _boundary_frame_cache.beat != beat:
		if _boundary_frame_cache != null and _boundary_frame_cache.chart != chart:
			_max_design_radius = -1.0
			_path_local_cache.clear()
		_boundary_frame_cache = BoundaryFrame.new(chart, beat, _boundary_frame_cache)
	return _boundary_frame_cache


func _boundary_point(chart: Chart, u: float, beat: float) -> Dictionary:
	return _frame_for(chart, beat).point_at(u)


func project_u(u: float, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	var data := _boundary_point(chart, u, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design(data.point)


func draw_overlay(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var started_usec := Time.get_ticks_usec()
	var t := get_time_beat()
	var pre := _pre_read_beats(chart, t)
	if not use_3d_ring:
		_draw_flat_stage(canvas, chart, t)
		_draw_flat_ring(canvas, chart, t)
	if not use_3d_ring:
		_draw_bezel(canvas, chart, t)
	var t_bar := Time.get_ticks_usec()
	_draw_bar_lines(canvas, chart, t, pre)
	_draw_red_regions(canvas, chart, t)
	_perf_sections[6] += Time.get_ticks_usec() - t_bar
	# 图层顺序：滑条底带 → Path → Hold → Tap/Anchor/Bell，命中目标始终在上层。
	# Combo 单独压在音符层下面，下落音符可以盖住它；左右两列仍在 HUD 层。
	if playtest_mode and show_hud:
		_draw_play_combo_layer(canvas)
	var sec_usec := Time.get_ticks_usec()
	_draw_seeks(canvas, chart, t)
	var sec2 := Time.get_ticks_usec()
	_perf_sections[0] += sec2 - sec_usec
	_draw_paths(canvas, chart, t, pre)
	sec_usec = Time.get_ticks_usec()
	_perf_sections[1] += sec_usec - sec2
	_draw_holds(canvas, chart, t, pre)
	sec2 = Time.get_ticks_usec()
	_perf_sections[2] += sec2 - sec_usec
	_draw_notes(canvas, chart, t, pre)
	if show_path_judgement:
		_draw_path_judgement(canvas, chart, t, pre)
	_draw_note_pops(canvas)
	sec_usec = Time.get_ticks_usec()
	_perf_sections[3] += sec_usec - sec2
	var t_hud := Time.get_ticks_usec()
	_draw_onion(canvas, chart, t)
	_draw_boundary_controls(canvas, chart)
	if show_hud:
		_draw_hud(canvas, chart, t)
	_perf_sections[5] += Time.get_ticks_usec() - t_hud
	sec2 = Time.get_ticks_usec()
	_draw_arc_flashes(canvas)
	_draw_pulses(canvas)
	_perf_sections[4] += Time.get_ticks_usec() - sec2
	if show_debug:
		_draw_debug(canvas, chart, t)
	_perf_draw_usec += Time.get_ticks_usec() - started_usec
	_perf_frames += 1


## 光标层：鼠标移动时只重绘这里。
func draw_cursor_overlay(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var t_cursor := Time.get_ticks_usec()
	_draw_cursor(canvas, chart, get_time_beat())
	_perf_sections[7] += Time.get_ticks_usec() - t_cursor


## 试玩把 _chart_ms 的耗时（含每次按键查询）累加进来，便于判断音频是不是瓶颈。
func note_audio_usec(usec: int) -> void:
	_perf_sections[8] += usec


## Match the timeline's bar grid, including local time-signature changes.
static func bar_line_beats(timing: TimingMap, beat: float, pre: float) -> Array[float]:
	var result: Array[float] = []
	if pre <= 0.0:
		return result
	for index in range(maxi(0, ceili(beat)), floori(beat + pre) + 1):
		if index % timing.beats_per_bar_at(float(index)) == 0:
			result.append(float(index))
	return result


func _draw_bar_lines(canvas: Control, chart: Chart, beat: float, pre: float) -> void:
	if not bar_lines_visible:
		return
	var bars := bar_line_beats(chart.timing, beat, pre)
	if bars.is_empty():
		return
	# Reuse the boundary evaluator for every ring; scale before camera projection
	# so the lines follow deformations and tilt exactly like the note bands.
	var frame := _frame_for(chart, beat)
	var boundary: Array[Dictionary] = []
	for i in 72:
		boundary.append(frame.point_at(float(i) / 72.0))
	# Reuse the exact start point: evaluating u=1 can select the first
	# segment but interpolate its far endpoint, leaving a spur at the seam.
	boundary.append(boundary[0])
	for target in bars:
		var progress := clampf(1.0 - (target - beat) / pre, 0.0, 1.0)
		var alpha := 0.58 * smoothstep(0.0, 0.15, progress)
		if alpha <= 0.001:
			continue
		var run := PackedVector2Array()
		for item in boundary:
			var point := project_design((item["point"] as Vector2) * progress)
			if bool(item.get("gap", false)) or not _valid_point(point):
				if run.size() > 1:
					canvas.draw_polyline(run, Color(1, 1, 1, alpha), 1.2, true)
				run = PackedVector2Array()
			else:
				run.append(point)
		if run.size() > 1:
			canvas.draw_polyline(run, Color(1, 1, 1, alpha), 1.2, true)


func _screen_affine() -> Array:
	var center := project_design(Vector2.ZERO)
	var x_axis := project_design(Vector2(100, 0)) - center
	var y_axis := project_design(Vector2(0, 100)) - center
	return [center, x_axis / 100.0, y_axis / 100.0]


func _affine_point(point: Vector2, affine: Array) -> Vector2:
	var center: Vector2 = affine[0]
	var x_axis: Vector2 = affine[1]
	var y_axis: Vector2 = affine[2]
	return center + x_axis * point.x + y_axis * point.y


func _draw_flat_stage(canvas: Control, chart: Chart, t: float) -> void:
	var affine := _screen_affine()
	for radius in [360.0, 420.0, 620.0]:
		var points := PackedVector2Array()
		for i in 97:
			var a := TAU * float(i) / 96.0
			points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(0.56, 0.62, 0.72, 0.08), 1.0, false)
	for angle in [-135.0, -45.0, 45.0, 135.0]:
		var a := deg_to_rad(angle)
		for offset in [-2.0, 2.0]:
			var normal: Vector2 = Vector2(-sin(a), cos(a)) * offset
			var p0 := _affine_point(Vector2(cos(a), sin(a)) * 520.0 + normal, affine)
			var p1 := _affine_point(Vector2(cos(a), sin(a)) * 590.0 + normal, affine)
			canvas.draw_line(p0, p1, Color(0.56, 0.62, 0.72, 0.10), 1.0, false)


func _draw_flat_ring(canvas: Control, chart: Chart, t: float) -> void:
	var points := _frame_for(chart, t).sample_points(192)
	var run := PackedVector2Array()
	for item in points:
		if bool(item.get("gap", false)):
			if run.size() > 1:
				canvas.draw_polyline(run, Color(0.37, 0.85, 0.81, 0.10), 18.0, true)
				canvas.draw_polyline(run, Color(0.55, 0.60, 0.70, 0.95), 4.0, true)
				canvas.draw_polyline(run, Color(1, 1, 1, 0.18), 1.0, true)
			run = PackedVector2Array()
			continue
		var p := project_design(item.point)
		if _valid_point(p):
			run.append(p)
	if run.size() > 1:
		canvas.draw_polyline(run, Color(0.37, 0.85, 0.81, 0.10), 18.0, true)
		canvas.draw_polyline(run, Color(0.55, 0.60, 0.70, 0.95), 4.0, true)
		canvas.draw_polyline(run, Color(1, 1, 1, 0.18), 1.0, true)


func _draw_bezel(canvas: Control, chart: Chart, t: float) -> void:
	var affine := _screen_affine()
	var center: Vector2 = affine[0]
	if not _valid_point(center):
		return
	for radius in [470.0, 474.0, 478.0, 482.0]:
		var points := PackedVector2Array()
		for i in 97:
			var angle := TAU * float(i) / 96.0
			points.append(_affine_point(Vector2(cos(angle), sin(angle)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(1, 1, 1, 0.09), 1.0, false)
	_draw_affine_arcs(canvas, affine, [[20.0, 44.0], [137.0, 160.0]], 466.0, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.82), 1.8)
	_draw_affine_arcs(canvas, affine, [[-40.5, -10.0], [-4.0, 44.0], [138.0, 168.0], [174.0, 204.0], [210.0, 234.0]], 505.0, Color(1, 1, 1, 0.92), 9.8)
	for angle in [-101.0, -162.0, -37.0, 29.0, 141.0]:
		var a := deg_to_rad(angle)
		var p := _affine_point(Vector2(cos(a), sin(a)) * 462.0, affine)
		var outward := (_affine_point(Vector2(cos(a), sin(a)) * 470.0, affine) - p).normalized()
		var side := Vector2(-outward.y, outward.x) * 6.0
		canvas.draw_colored_polygon(PackedVector2Array([p + side, p - side, p + outward * 12.0]), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.8))


func _draw_affine_arcs(canvas: Control, affine: Array, segments: Array, radius: float, color: Color, width: float) -> void:
	for segment in segments:
		var points := PackedVector2Array()
		var a0 := deg_to_rad(float(segment[0]))
		var a1 := deg_to_rad(float(segment[1]))
		var steps := maxi(8, int(absf(a1 - a0) * 18.0))
		for i in steps + 1:
			var a := a0 + (a1 - a0) * float(i) / float(steps)
			points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, color, width, false)


func _draw_red_regions(canvas: Control, chart: Chart, t: float) -> void:
	var pre := _pre_read_beats(chart, t)
	for region in chart.regions:
		var active := region.active_at(t)
		var incoming := t >= _spawn_beat(chart, region.start_beat) and t < region.start_beat
		if not active and not incoming:
			continue
		var outer := _arc_points_scaled(region.angle, region.width, t, 40, 1.0)
		var inner := _arc_points_scaled(region.angle, region.width, t, 40, 0.68)
		if outer.size() < 2 or inner.size() < 2:
			continue
		var fill_alpha := (0.52 + 0.06 * sin(t * PI * 2.0)) if active else 0.12
		var polygon := PackedVector2Array()
		for point in outer:
			polygon.append(point)
		for i in range(inner.size() - 1, -1, -1):
			polygon.append(inner[i])
		canvas.draw_colored_polygon(polygon, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, fill_alpha))
		canvas.draw_polyline(outer, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.25 if active else 0.06), 18.0, false)
		canvas.draw_polyline(outer, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.98 if active else 0.35), 3.0, false)
		canvas.draw_polyline(inner, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.75 if active else 0.18), 1.5, false)
		for i in 5:
			var slice := float(i) / 4.0
			var a := region.angle - region.width * 0.5 + region.width * slice
			var p0 := _arc_point_scaled(a, t, 0.78)
			var p1 := _arc_point_scaled(a, t, 0.97)
			if _valid_point(p0) and _valid_point(p1):
				canvas.draw_line(p0, p1, Color(1.0, 0.42, 0.34, 0.26 if active else 0.05), 1.0, false)
		var label_point := _arc_point_scaled(region.angle, t, 0.86)
		if _valid_point(label_point):
			_draw_badge(canvas, "LIMIT" if active else "LIMIT IN", label_point + Vector2(0, -4), UITheme.RED)


## 红区的可见多边形（外弧 + 内弧），判定和绘制共用同一份几何。
func red_region_polygon(region: Region, beat: float) -> PackedVector2Array:
	var outer := _arc_points_scaled(region.angle, region.width, beat, 40, 1.0)
	var inner := _arc_points_scaled(region.angle, region.width, beat, 40, 0.68)
	if outer.size() < 2 or inner.size() < 2:
		return PackedVector2Array()
	var polygon := PackedVector2Array()
	for point in outer:
		polygon.append(point)
	for i in range(inner.size() - 1, -1, -1):
		polygon.append(inner[i])
	return polygon


func _arc_points_scaled(angle: float, width: float, beat: float, steps: int, scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_width := clampf(width, 0.1, 360.0)
	var count := maxi(steps, 4)
	for i in count + 1:
		var a := angle - safe_width * 0.5 + safe_width * float(i) / float(count)
		var p := _arc_point_scaled(a, beat, scale)
		if _valid_point(p):
			points.append(p)
	return points


func _arc_point_scaled(angle: float, beat: float, scale: float) -> Vector2:
	var data := _boundary_point(get_chart(), fposmod(angle, 360.0) / 360.0, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * scale)


func _pick_visual_node(screen_position: Vector2) -> int:
	if _app == null:
		return -1
	var note: Note = _app.get_selected_note()
	if note == null or note.type not in ["path", "hold"]:
		return -1
	var chart := get_chart()
	if chart == null:
		return -1
	var t := get_time_beat()
	if note.type == "hold":
		for i in note.visual_pts.size():
			var point: Dictionary = note.visual_pts[i]
			var p := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
			if _valid_point(p) and p.distance_to(screen_position) <= 12.0:
				return i
		return -1
	for i in note.trace_pts.size():
		var point: Dictionary = note.trace_pts[i]
		var local := Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
		var p := _path_local_screen(chart, local, t)
		if _valid_point(p) and p.distance_to(screen_position) <= 12.0:
			return i
	# 中间设计判定点用轨迹时间定位，单独编号排在平面点之后。
	for i in note.visual_pts.size():
		var point: Dictionary = note.visual_pts[i]
		var p := _path_screen_point(chart, note, float(point.get("db", 0.0)), t)
		if _valid_point(p) and p.distance_to(screen_position) <= 10.0:
			return note.trace_pts.size() + i
	return -1


## 音符最终颜色：单音符覆盖 > 配色组 > 类型默认；预览与试玩共用同一条路径。
func _note_tint(note: Note, fallback: Color) -> Color:
	return note.resolved_color(get_chart(), fallback)


func _draw_paths(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	# A part chain is drawn as one synthetic Path: one head star at part0, one
	# progress ball travelling the whole chain, and one final tail ring.
	var by_id := {}
	for item in chart.notes:
		by_id[item.id] = item
	var visible: Array = []
	for root in chart.notes:
		if root.type != "path":
			continue
		if root.path_prev_id >= 0 and by_id.has(root.path_prev_id):
			continue
		var chain: Array[Note] = [root]
		var cursor: Note = root
		var guard := 0
		while cursor.path_next_id >= 0 and by_id.has(cursor.path_next_id) and guard < 64:
			cursor = by_id[cursor.path_next_id]
			chain.append(cursor)
			guard += 1
		var on_screen := false
		for part in chain:
			if t >= _spawn_beat(chart, part.beat) and t <= part.end_beat + 0.5:
				on_screen = true
				break
		if not on_screen:
			continue
		visible.append(build_path_chain_note(root, chain) if chain.size() > 1 else root)
	# 旧 Path 先画、新的最后画：多星星重叠时，新星和它的擦除缺口始终在最上层。
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	# 舞萌式同色系：所有星共用一个主色，重叠时只压明明度，不换色相。
	# 谱师自定义过的单星颜色优先。
	var any_overlap := false
	for i in visible.size():
		for j in range(i + 1, visible.size()):
			if _paths_overlap(chart, visible[i], visible[j]):
				any_overlap = true
				break
		if any_overlap:
			break
	var base := Note.DEFAULT_PATH_COLOR
	var colors := {}
	var shade := 0
	for note in visible:
		var tint := _note_tint(note, base)
		if not any_overlap:
			colors[note] = tint
		else:
			colors[note] = tint.darkened(0.18 * float(shade % 4))
			shade += 1
	# 接力高亮：还没划完的星里，只有尾判定最早的那条（或几条同时到点）保持全亮。
	# 未来星只要还在预读期就已经整条可见，所以也要参与压暗，否则屏幕上会有
	# 2–3 条同样亮的轨迹，看不出该先划哪条。
	var active_end := INF
	for note in visible:
		if t > note.end_beat:
			continue
		active_end = minf(active_end, note.end_beat)
	var active_list: Array = []
	for note in visible:
		if t > note.end_beat:
			continue
		if note.end_beat <= active_end + 0.05:
			active_list.append(note)
	# 当前该划的最后画，保证它在最上层。
	var order: Array = visible.duplicate()
	for note in active_list:
		order.erase(note)
		order.append(note)
	for note in order:
		var dim := 1.0 if active_list.has(note) else PATH_RELAY_DIM
		_draw_one_path(canvas, chart, note, t, pre, true, visible.size(), colors[note], dim, active_list.has(note))
	if _drawing_path and _path_points.size() > 1:
		var preview := PackedVector2Array()
		for local in _path_points:
			var p := _path_local_screen(chart, local, t)
			if _valid_point(p):
				preview.append(p)
		if preview.size() > 1:
			canvas.draw_polyline(preview, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.75), 3.0, false)
			for p in preview:
				canvas.draw_circle(p, 2.5, UITheme.CYAN)


## One synthetic Path for a part chain: one head, one guide ball, one tail.
## Shared by drawing and judgement so the whole chain is judged as drawn.
static func build_path_chain_note(root: Note, chain: Array[Note]) -> Note:
	var result := Note.new("path", root.beat, root.angle, root.width)
	result.id = root.id
	result.end_beat = chain[-1].end_beat
	result.tail_angle = chain[-1].tail_angle
	result.tail_width = chain[-1].tail_width
	result.path_speed = root.path_speed
	result.wait_beat = root.wait_beat
	result.samples_per_beat = root.samples_per_beat
	result.has_custom_color = root.has_custom_color
	result.custom_color = root.custom_color
	result.path_chain = true
	result.path_next_id = root.path_next_id
	result.trace_pts = []
	for part in chain:
		var total := maxf(0.001, part.duration())
		var count := maxi(6, int(total * 18.0))
		for i in count + 1:
			var rel := total * float(i) / float(count)
			var local := part.path_local_at(rel)
			result.trace_pts.append({
				"x": local.x,
				"y": local.y,
				"db": (part.beat - root.beat) + rel,
			})
	return result


## 两条星在时间上重叠、且轨迹在盘面内靠得足够近，就算“有重叠”。
func _paths_overlap(chart: Chart, a: Note, b: Note) -> bool:
	if a.end_beat < b.beat - 0.25 or b.end_beat < a.beat - 0.25:
		return false
	var a_duration := maxf(0.01, a.duration())
	var b_duration := maxf(0.01, b.duration())
	var steps := 12
	for i in steps + 1:
		var pa := a.path_local_at(a_duration * float(i) / float(steps))
		for j in steps + 1:
			var pb := b.path_local_at(b_duration * float(j) / float(steps))
			if pa.distance_to(pb) < 0.22:
				return true
	return false


func path_screen_runs(note: Note, t: float, grow: float = 1.0) -> Array[PackedVector2Array]:
	var chart := get_chart()
	if chart == null:
		return []
	var total := note.duration()
	if total <= 0.001:
		return []
	var count := clampi(int(total * 18.0), 40, 96)
	var points := PackedVector2Array()
	var erased_flags: Array[bool] = []
	for i in count + 1:
		var rel := total * float(i) / float(count)
		erased_flags.append(path_erased(note, rel))
		points.append(_path_screen_point(chart, note, rel, t, false, 1.0))
	var runs := split_path_runs(points, erased_flags)
	if grow < 0.999:
		var center := project_design(Vector2.ZERO)
		var scaled_runs: Array[PackedVector2Array] = []
		for piece in runs:
			var scaled := PackedVector2Array()
			for p in piece:
				scaled.append(center.lerp(p, grow))
			scaled_runs.append(scaled)
		runs = scaled_runs
	return runs


static func split_path_runs(points: PackedVector2Array, erased: Array) -> Array[PackedVector2Array]:
	# 只在真正擦除/无效点处分段；不再用像素距离阈值，避免长轨迹被误切。
	var result: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in points.size():
		var point := points[i]
		var hidden := i < erased.size() and bool(erased[i])
		if hidden or not is_finite(point.x) or not is_finite(point.y) or point.x > 1.0e9 or point.y > 1.0e9:
			if run.size() > 1:
				result.append(run)
			run = PackedVector2Array()
			continue
		run.append(point)
	if run.size() > 1:
		result.append(run)
	return result


func _draw_one_path(canvas: Control, chart: Chart, note: Note, t: float, pre: float, top: bool, visible_count: int = 1, accent: Color = Color(0.22, 0.36, 0.88), dim: float = 1.0, active: bool = false) -> void:
	var total := note.duration()
	if total <= 0.001:
		return
	# 尾判后 0.1s 内整条轨迹（轨迹 / 进度球 / 尾环）一起淡出，不再等到 end+0.5 拍硬消失。
	var end_span := end_fade_beats(chart.timing.bpm_at(note.beat))
	var end_fade := clampf(1.0 - (t - note.end_beat) / end_span, 0.0, 1.0)
	# 每条 Path 都按"顶层"完整画（箭头链 / 星头 / 尾环 / 进度球）。
	top = true
	# 先铺轨迹，再落星星：轨迹从生成开始淡入，星星落下的那一刻正好铺满。
	var spawn_beat := _spawn_beat(chart, note.beat)
	var fall_beat := _fall_beat(chart, note.beat)
	var trail_fade := smoothstep(0.0, 1.0, chart.timing.ms_fraction(spawn_beat, fall_beat, t))
	var ns := _note_scale()
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, total - 0.001))
	var q := clampf((t - note.beat - wait) / maxf(0.001, total - wait), 0.0, 1.0)
	var progress := 1.0 - pow(1.0 - q, maxf(0.05, note.path_speed))
	var runs: Array[PackedVector2Array] = []
	var mesh := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, t), _last_view_key, size.x, size.y]
	var cache_key := "%d|%d|%s" % [note.id, int(path_cut_versions.get(note.id, 0)), mesh]
	if _path_runs_cache.has(cache_key):
		runs = _path_runs_cache[cache_key]
	else:
		var count := clampi(int(total * 18.0), 40, 96)
		if visible_count >= 4:
			count = clampi(int(total * 12.0), 28, 64)
		var points := PackedVector2Array()
		var erased_flags: Array[bool] = []
		for i in count + 1:
			var rel := total * float(i) / float(count)
			erased_flags.append(path_erased(note, rel))
			points.append(_path_screen_point(chart, note, rel, t, true, 1.0))
		runs = split_path_runs(points, erased_flags)
		if _path_runs_cache.size() > 64:
			_path_runs_cache.clear()
		_path_runs_cache[cache_key] = runs
	# 颜色由 _draw_paths 统一分配（自定义优先，重叠时同色系压明度）。
	var trail_dim := dim * trail_fade * end_fade
	var future := Color(accent.r, accent.g, accent.b, 0.98 * trail_dim)
	var passed := Color(accent.r, accent.g, accent.b, 0.14 * trail_dim)
	if trail_fade > 0.001:
		for piece in runs:
			if piece.size() < 2:
				continue
			# 所有星都用同一条粗带；还没轮到的那条只压明度（PATH_RELAY_DIM），
			# 不再缩成细线，否则多条星先后出现时后一条完全读不出路径。
			var path_band := float(_skin()["band"])
			var band_width := 5.0 * PATH_SIZE_SCALE * ns * path_band
			canvas.draw_polyline(piece, Color(0, 0, 0, 0.50 * trail_dim), band_width + 4.0, false)
			canvas.draw_polyline(piece, Color(accent.r, accent.g, accent.b, 0.95 * trail_dim), band_width, false)
			# 箭头链也画在所有星上：后面的星和前面的星同形，只靠 dim 压暗。
			var piece_length := 0.0
			for i in piece.size() - 1:
				piece_length += piece[i].distance_to(piece[i + 1])
			var chevron_cap := 10 if visible_count < 4 else (8 if visible_count < 8 else 6)
			var chevron_count := clampi(int(piece_length / maxf(40.0, 52.0 * ns)), 2, chevron_cap)
			for k in chevron_count:
				var fraction := (float(k) + 0.5) / float(chevron_count)
				var sample: Dictionary = _polyline_sample(piece, fraction)
				# 试玩时轨迹已经被擦到光标处，剩下的每一段都在前方，不该再按“piece 内比例”压暗。
				var chevron_color := future if playtest_mode else (passed if fraction < progress else future)
				_draw_chevron(canvas, sample["point"], sample["direction"], chevron_color, 12.0 * ns * PATH_SIZE_SCALE)
	var selected_note: Note = _app.get_selected_note() if _app != null else null
	var selected := selected_note != null and selected_note.id == note.id
	if selected:
		# 中间判定点只在选中时绘制，避免多星星铺满采样点拖慢编辑器。
		for sample_beat in note.path_sample_beats():
			var rel := clampf(sample_beat - note.beat, 0.0, total)
			if path_erased(note, rel):
				continue
			var p := _path_screen_point(chart, note, rel, t, true, 1.0)
			if _valid_point(p):
				canvas.draw_circle(p, 2.6 * ns, Color(0, 0, 0, 0.5))
				canvas.draw_circle(p, 1.8 * ns, Color(accent.r, accent.g, accent.b, 0.85))
		# 手动放置的中间设计点。
		for point in note.visual_pts:
			var rel := clampf(float(point.get("db", 0.0)), 0.0, total)
			if path_erased(note, rel):
				continue
			var p := _path_screen_point(chart, note, rel, t, true, 1.0)
			if _valid_point(p):
				_draw_diamond(canvas, p, 4.5, UITheme.GOLD)
	_draw_target_arc(canvas, note.angle, note.width, t, UITheme.CORAL, 14.0 * PATH_SIZE_SCALE, trail_fade * end_fade)
	if selected:
		for point in note.trace_pts:
			var node := _path_local_screen(chart, Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))), t, 1.0)
			if _valid_point(node):
				_draw_diamond(canvas, node, 5.0, UITheme.CYAN)
				canvas.draw_circle(node, 1.8, UITheme.INK)
	var fall_progress := chart.timing.ms_fraction(fall_beat, note.beat, t)
	# 环上固定的落点（圆的中心）和滑动终点。
	var ring_head := _path_screen_point(chart, note, 0.0, t, true, 1.0)
	var tail := _path_screen_point(chart, note, total, t, true, 1.0)
	# 尾点倒计时环：距尾判定 2 拍内从大圈收到尾环，贴合时正是尾判定时刻。
	# 多条星同时在场时，环先缩满的那条就是要先划完的。
	if _valid_point(tail) and t >= note.beat - 0.15:
		var remain := note.end_beat - t
		if remain <= 2.0 and remain > -end_span:
			var k := clampf(1.0 - remain / 2.0, 0.0, 1.0)
			var ring_radius := lerpf(52.0, 14.0, k) * ns
			var ring_alpha := lerpf(0.10, 0.95, k * k) * maxf(dim, 0.75) * trail_fade * end_fade
			canvas.draw_arc(tail, ring_radius, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, ring_alpha), 2.6, false)
			if active:
				canvas.draw_arc(tail, ring_radius + 3.5, 0.0, TAU, 40, Color(1, 1, 1, 0.30 * ring_alpha), 1.2, false)
	# 星头拆成两部分：
	#   环上的圆 = 落点标记（预读出现，头判后淡出）
	#   下落的星星 = 星形 + 光晕（从圆心飞到圆上；击中后继续落到圆上再淡出，
	#   打空则停在圆上淡出）
	var head_state: Dictionary = _path_head_state.get(note.id, {})
	var state_beat := float(head_state.get("beat", note.beat))
	var head_hit := bool(head_state.get("hit", true))
	var fade_start := maxf(note.beat, state_beat) if head_hit else state_beat
	var fade_beats := 0.3 * chart.timing.bpm_at(note.beat) / 60.0
	var head_alpha := 1.0 - clampf((t - fade_start) / maxf(0.001, fade_beats), 0.0, 1.0)
	# 头部标记和轨迹一起淡入，避免轨迹还没亮就先蹦出一个满不透明的圆。
	var head_fade := head_alpha * dim * trail_fade
	var ring_mul := 0.5 if note.path_chain else 1.0
	var wait_mode := String(_app.path_wait_indicator) if _app != null else "progress"
	var wait_state := path_wait_indicator_state(chart.timing, note, t)
	if wait_mode != "off" and wait_state.y > 0.0:
		# The landing circle becomes the countdown and survives the head-hit fade.
		head_fade = 0.0
	if head_fade > 0.01 and _valid_point(ring_head):
		_draw_path_circle(canvas, ring_head, ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE, accent, head_fade, ring_mul)
		# 重叠 Path 用不同明度的外环区分星头。
		canvas.draw_arc(ring_head, 28.0 * ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE * ring_mul, 0.0, TAU, 30, Color(accent.r, accent.g, accent.b, 0.95 * head_fade), 2.4, false)
		# 音符编号只在编辑器和调试叠层里显示，试玩时不添乱。
		if not playtest_mode or show_debug:
			canvas.draw_string(UITheme.mono_font(), ring_head + Vector2(14, -13), "#%d" % note.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(accent.r, accent.g, accent.b, 0.9 * head_fade))
		# 头部的白色箭头指向轨迹内侧，进一步区分头和尾。
		var ahead := _path_screen_point(chart, note, minf(total, maxf(0.05, total * 0.08)), t, true, 1.0)
		if _valid_point(ahead):
			_draw_arrowhead(canvas, ring_head + (ahead - ring_head).normalized() * 29.0 * ns * PATH_SIZE_SCALE, ahead - ring_head, Color(1, 1, 1, 0.95 * head_fade))
		if show_debug:
			canvas.draw_string(UITheme.bold_font(), ring_head + Vector2(-12, -22), "PATH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.85))
	# 滑动开始后星星交给进度球，不再留在起点。星星在轨迹铺满之后才开始下落。
	if head_alpha > 0.01 and t >= fall_beat and t < note.beat + wait + 0.02 and _valid_point(ring_head):
		var star_in := clampf(fall_progress / 0.55, 0.0, 1.0)
		var star_head := project_design(Vector2.ZERO).lerp(ring_head, fall_progress)
		# 离圆心越远，星头越大：飞到环上时回到 1.0。
		# 下落星星全程都要能看清：从圆心出发时也不再缩到 0.2。
		var star_grow := _radial_scale(star_head, 0.8, 1.0, t)
		_draw_path_star(canvas, star_head, ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE * star_grow, accent, head_alpha * dim * star_in)
	_draw_path_tail(canvas, tail, top, ns * PATH_SIZE_SCALE, accent, dim * trail_fade * end_fade)
	# 大号发光球 + 短拖尾：当前进度点始终比星头更亮，方向一目了然。
	if t >= note.beat and t <= note.end_beat + end_span:
		var ball_dim := dim * end_fade
		var rel := note.path_motion_beat(progress)
		for trail_index in range(4, 0, -1):
			var trail_rel := rel - float(trail_index) * 0.035 * total
			if trail_rel < 0.0 or path_erased(note, trail_rel):
				continue
			var trail_point := _path_screen_point(chart, note, trail_rel, t, false)
			if _valid_point(trail_point):
				var fade := 0.34 * (1.0 - float(trail_index) / 5.0) * ball_dim
				canvas.draw_circle(trail_point, (18.0 - float(trail_index) * 1.6) * ns * PATH_SIZE_SCALE, Color(accent.r, accent.g, accent.b, fade))
		var p := _path_screen_point(chart, note, rel, t, false)
		if _valid_point(p):
			canvas.draw_circle(p, 32.0 * ns * PATH_SIZE_SCALE, Color(accent.r, accent.g, accent.b, 0.18 * ball_dim))
			canvas.draw_circle(p, 19.0 * ns * PATH_SIZE_SCALE, Color(0, 0, 0, 0.58 * ball_dim))
			canvas.draw_circle(p, 16.0 * ns * PATH_SIZE_SCALE, Color(accent.r, accent.g, accent.b, ball_dim))
			canvas.draw_circle(p, 10.0 * ns * PATH_SIZE_SCALE, Color(1, 1, 1, 0.96 * ball_dim))
			canvas.draw_circle(p, 4.5 * ns * PATH_SIZE_SCALE, Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, ball_dim))
	if wait_mode != "off" and wait_state.y > 0.0 and _valid_point(ring_head):
		# Shrinking mode lands exactly on the original blue head ring; the progress
		# arc retains its larger radius so it remains readable outside the guide ball.
		var head_radius := 28.0 * ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE * ring_mul
		var wait_radius := head_radius if wait_mode == "shrink" else maxf(head_radius, 24.0 * ns * PATH_SIZE_SCALE)
		_draw_path_wait_indicator(canvas, ring_head, wait_radius,
			wait_state.x, wait_state.y * dim * trail_fade, wait_mode)


## Use elapsed chart milliseconds so BPM changes inside the wait stay in sync.
## x = completion, y = opacity; no countdown for zero wait or before landing.
static func path_wait_indicator_state(timing: TimingMap, note: Note, beat: float) -> Vector2:
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, note.duration() - 0.001))
	if wait <= 0.0 or beat < note.beat:
		return Vector2.ZERO
	var start_ms := timing.beat_to_chart_ms(note.beat)
	var end_ms := timing.beat_to_chart_ms(note.beat + wait)
	var now_ms := timing.beat_to_chart_ms(beat)
	var completion := clampf((now_ms - start_ms) / maxf(0.001, end_ms - start_ms), 0.0, 1.0)
	var opacity := 1.0 - clampf((now_ms - end_ms) / 160.0, 0.0, 1.0)
	return Vector2(completion, opacity)


func _draw_path_wait_indicator(canvas: Control, center: Vector2, radius: float, completion: float, opacity: float, mode: String) -> void:
	if mode == "shrink":
		var ring_radius := radius * lerpf(2.5, 1.0, completion)
		var alpha := opacity * completion
		canvas.draw_arc(center, ring_radius, 0.0, TAU, 64, Color(0.55, 0.75, 1.0, 0.16 * alpha), 7.0, true)
		canvas.draw_arc(center, ring_radius, 0.0, TAU, 64, Color(0.55, 0.75, 1.0, 0.95 * alpha), 2.4, true)
		return
	var color := Color(0.35, 1.0, 0.62, 0.95 * opacity)
	canvas.draw_arc(center, radius, 0.0, TAU, 64, Color(0.02, 0.03, 0.05, 0.65 * opacity), 6.0, true)
	canvas.draw_arc(center, radius, 0.0, TAU, 64, Color(0.65, 0.75, 0.85, 0.22 * opacity), 2.4, true)
	if completion > 0.001:
		canvas.draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * completion, 64, color, 3.2, true)


func path_point(note: Note, relative_beat: float, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	return _path_screen_point(chart, note, relative_beat, beat, false)


static func path_erase_ranges(points: PackedVector2Array, from: Vector2, to: Vector2, radius: float) -> Array[Vector2]:
	# 返回被鼠标（或本帧鼠标扫过的线段）覆盖的时间比例区间。
	var ranges: Array[Vector2] = []
	if points.size() < 2:
		return ranges
	var segments := points.size() - 1
	var point_only := from.distance_to(to) < 0.5
	var start := -1
	for i in segments:
		var a := points[i]
		var b := points[i + 1]
		if not a.is_finite() or not b.is_finite():
			if start >= 0:
				ranges.append(Vector2(float(start) / float(segments), float(i) / float(segments)))
				start = -1
			continue
		var distance := INF
		if point_only:
			distance = from.distance_to(Geometry2D.get_closest_point_to_segment(from, a, b))
		else:
			var pair := Geometry2D.get_closest_points_between_segments(a, b, from, to)
			if pair.size() >= 2:
				distance = pair[0].distance_to(pair[1])
		if distance <= radius:
			if start < 0:
				start = i
		elif start >= 0:
			ranges.append(Vector2(float(start) / float(segments), float(i) / float(segments)))
			start = -1
	if start >= 0:
		ranges.append(Vector2(float(start) / float(segments), 1.0))
	return ranges


func _point_polyline_distance(points: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if not a.is_finite() or not b.is_finite():
			continue
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best


func erase_path_overlap(note: Note, from: Vector2, to: Vector2, beat: float) -> bool:
	var chart := get_chart()
	if chart == null:
		return false
	var total := note.duration()
	if total <= 0.001:
		return false
	var count := 96
	var points := PackedVector2Array()
	for i in count + 1:
		points.append(_path_screen_point(chart, note, total * float(i) / float(count), beat, false))
	var brush := 26.0 * _note_scale()
	# 多星星保护：只有鼠标当前或上一帧确实贴着这条 Path 时才擦，
	# 避免从 A 星移到 B 星时把路上穿过的 C 星误削。
	var guard := 72.0 * _note_scale()
	if minf(_point_polyline_distance(points, from), _point_polyline_distance(points, to)) > guard:
		return false
	var ranges := path_erase_ranges(points, from, to, brush)
	for span in ranges:
		_add_path_erase_range(note, span.x, span.y)
	return not ranges.is_empty()


static func merge_erase_ranges(ranges: Array, from_fraction: float, to_fraction: float) -> Array:
	var a := clampf(minf(from_fraction, to_fraction), 0.0, 1.0)
	var b := clampf(maxf(from_fraction, to_fraction), 0.0, 1.0)
	if a < 0.08:
		a = 0.0
	if b - a <= 0.002:
		return ranges
	var all: Array = ranges.duplicate(true)
	all.append({"from": a, "to": b})
	all.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.get("from", 0.0)) < float(y.get("from", 0.0)))
	var merged: Array = []
	for item in all:
		if merged.is_empty() or float(item.get("from", 0.0)) > float(merged[-1].get("to", 0.0)) + 0.035:
			merged.append({"from": float(item.get("from", 0.0)), "to": float(item.get("to", 0.0))})
		else:
			merged[-1]["to"] = maxf(float(merged[-1].get("to", 0.0)), float(item.get("to", 0.0)))
	return merged


func path_judgement_points(local_points: PackedVector2Array, beat: float) -> PackedVector2Array:
	var projected := PackedVector2Array()
	var chart := get_chart()
	if chart == null:
		return projected
	for point in local_points:
		projected.append(_path_local_screen(chart, point, beat))
	return projected


func path_judgement_scale() -> float:
	# Input tolerance follows the visible ring size, independently of cursor art.
	return maxf(1.0, _avg_radius_cache)


func path_judgement_debug(note: Note, beat: float) -> Dictionary:
	var state: Dictionary = path_judgement_states.get(note.id, {})
	var tracker: PathProgress = state.get("path_tracker")
	if tracker == null:
		return {}
	return {"points": path_judgement_points(tracker.points, beat),
		"radius": tracker.contact_radius * path_judgement_scale(),
		"next": tracker.next_index, "mandatory": tracker.mandatory,
		"required": tracker.required_index, "coverage": tracker.coverage,
		"progress": tracker.progress, "covered": tracker.covered, "gates": tracker.gates,
		"gate_radii": tracker.gate_radii, "next_gate": tracker.next_gate,
		"cleared": tracker.cleared, "group_count": tracker.group_count,
		"tolerance": tracker.tolerance, "remaining": tracker.remaining_groups(),
		"tail_radius": float(state.get("path_tail_radius", 0.0)),
		"missed": bool(state.get("tail_judged", false)) and not bool(state.get("tail_hit", false))}


func set_path_judgement_visible(value: bool) -> void:
	show_path_judgement = value
	if _overlay != null:
		_overlay.queue_redraw()


func _draw_path_judgement(canvas: Control, chart: Chart, beat: float, pre: float) -> void:
	var font := UITheme.mono_font()
	var confirmed := Color(0.25, 1.0, 0.55)
	var pending := Color(0.25, 0.65, 1.0)
	var current := Color(1.0, 0.65, 0.15)
	var failed := Color(1.0, 0.25, 0.3)
	for note in chart.notes:
		if note.type != "path" or note.beat > beat + pre or beat > note.end_beat + 0.8:
			continue
		var data := path_judgement_debug(note, beat)
		if data.is_empty():
			continue
		var points: PackedVector2Array = data["points"]
		var radius := float(data["radius"])
		var next := int(data["next_gate"])
		var gates: PackedInt32Array = data["gates"]
		var radii: PackedFloat32Array = data["gate_radii"]
		var covered: PackedByteArray = data["covered"]
		var cleared: PackedByteArray = data["cleared"]
		# Draw only valid segments, so boundary gaps never become fake corridors.
		var run := PackedVector2Array()
		var run_covered := false
		for i in points.size() - 1:
			if not _valid_point(points[i]) or not _valid_point(points[i + 1]):
				_draw_path_corridor_run(canvas, run, radius, confirmed if run_covered else pending)
				run.clear()
				continue
			var is_covered := covered[i] != 0
			if not run.is_empty() and run_covered != is_covered:
				_draw_path_corridor_run(canvas, run, radius, confirmed if run_covered else pending)
				run.clear()
			if run.is_empty():
				run.append(points[i])
				run_covered = is_covered
			run.append(points[i + 1])
		_draw_path_corridor_run(canvas, run, radius, confirmed if run_covered else pending)
		for i in gates.size():
			var point := points[gates[i]]
			if not _valid_point(point):
				continue
			var gate_radius := float(radii[i]) * path_judgement_scale()
			var color := confirmed if i < cleared.size() and cleared[i] != 0 else pending
			if i == next:
				color = failed if bool(data["missed"]) else current
			canvas.draw_circle(point, gate_radius, Color(color, 0.045))
			canvas.draw_arc(point, gate_radius, 0.0, TAU, 40, Color(color, 0.85), 2.4 if i == next else 1.0, true)
			var label := str(i + 1)
			var offset := Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, 4)
			canvas.draw_string_outline(font, point + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
			canvas.draw_string(font, point + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		if not points.is_empty() and _valid_point(points[0]):
			var label := "#%d  组%d/%d  容差%d  剩余%d" % [note.id, mini(next, int(data["group_count"])), int(data["group_count"]), int(data["tolerance"]), int(data["remaining"])]
			var position := points[0] + Vector2(12, -radius - 12)
			canvas.draw_string_outline(UITheme.FONT_REGULAR, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			canvas.draw_string(UITheme.FONT_REGULAR, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if not points.is_empty() and _valid_point(points[-1]) and float(data["tail_radius"]) > 0.0:
			canvas.draw_arc(points[-1], float(data["tail_radius"]), 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.0, true)
	var legend := "F10：绿=已消组 / 蓝=未消组 / 橙=下一组 / 白圈=尾区，容差=可跳组数"
	canvas.draw_string_outline(UITheme.FONT_REGULAR, Vector2(24, 72), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(24, 72), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_path_corridor_run(canvas: Control, run: PackedVector2Array, radius: float, color: Color) -> void:
	if run.size() < 2:
		return
	# Rounded outlines avoid miter spikes that would falsely imply extra area
	# at sharp corners. Outlines also preserve holes in a closed loop.
	for outline in Geometry2D.offset_polyline(run, radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
		if outline.size() >= 2:
			outline.append(outline[0])
			canvas.draw_polyline(outline, Color(color, 0.45), 1.4, true)
	canvas.draw_polyline(run, Color(color, 0.65), 1.0, true)


func set_path_erased_to(note: Note, fraction: float) -> void:
	# 试玩时只保留一个连续缺口：从头部到当前进度，轨迹始终是连续的一段。
	var target := clampf(fraction, 0.0, 1.0)
	if target <= 0.004:
		return
	var current: Array = path_cuts.get(note.id, [])
	if current.size() == 1 and absf(float(current[0].get("to", -1.0)) - target) <= 0.001:
		return
	path_cuts[note.id] = [{"from": 0.0, "to": target}]
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


func path_fraction(note: Note, mouse: Vector2, beat: float) -> Dictionary:
	var chart := get_chart()
	if chart == null:
		return {"fraction": 0.0, "distance": INF}
	var points := PackedVector2Array()
	var count := 48
	for i in count + 1:
		var p := _path_screen_point(chart, note, note.duration() * float(i) / float(count), beat, false)
		if _valid_point(p):
			points.append(p)
	if points.size() < 2:
		return {"fraction": 0.0, "distance": INF}
	var best := INF
	var best_fraction := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var length_squared := ab.length_squared()
		var q := 0.0 if length_squared <= 0.0001 else clampf((mouse - a).dot(ab) / length_squared, 0.0, 1.0)
		var distance := mouse.distance_to(a + ab * q)
		if distance < best:
			best = distance
			best_fraction = (float(i) + q) / float(points.size() - 1)
	return {"fraction": best_fraction, "distance": best}


func _add_path_erase_range(note: Note, from_fraction: float, to_fraction: float) -> void:
	var merged := merge_erase_ranges(path_cuts.get(note.id, []), from_fraction, to_fraction)
	if merged == path_cuts.get(note.id, []):
		return
	path_cuts[note.id] = merged
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


func path_erased(note: Note, relative_beat: float) -> bool:
	if note.erased_at(relative_beat):
		return true
	var total := maxf(0.000001, note.duration())
	var p := clampf(relative_beat / total, 0.0, 1.0)
	for gap in path_cuts.get(note.id, []):
		if p >= float(gap.get("from", 0.0)) and p <= float(gap.get("to", 1.0)):
			return true
	for gap in path_sector_cuts.get(note.id, []):
		if p >= float(gap.get("from", 0.0)) and p <= float(gap.get("to", 1.0)):
			return true
	return false


## 8 分区（45°，边界在 22.5° + 45°k），和 8 个按键 / 车道对齐。
static func ring_sector(angle_deg: float) -> int:
	return int(floor((fposmod(angle_deg, 360.0) + 22.5) / 45.0)) % 8


## 一条 Path 的轨迹按环分区切出的分数区间：sector -> [{from,to}]。
## 结果缓存到 note 上，轨迹不变就不用重算。
func path_sector_ranges(note: Note) -> Dictionary:
	if _path_sector_cache.has(note):
		return _path_sector_cache[note]
	var result := {}
	var total := maxf(0.000001, note.duration())
	var pts: Array = note.trace_pts
	if pts.size() >= 2:
		var current := -1
		var start := 0.0
		var last_frac := 0.0
		for i in pts.size():
			var point: Dictionary = pts[i]
			var angle := fposmod(rad_to_deg(atan2(float(point.get("y", 0.0)), float(point.get("x", 0.0)))), 360.0)
			var sector := ring_sector(angle)
			var frac := clampf(float(point.get("db", 0.0)) / total, 0.0, 1.0)
			if sector != current:
				if current >= 0:
					if not result.has(current):
						result[current] = []
					(result[current] as Array).append({"from": start, "to": last_frac})
				current = sector
				start = frac
			last_frac = frac
		if current >= 0:
			if not result.has(current):
				result[current] = []
			(result[current] as Array).append({"from": start, "to": last_frac})
	_path_sector_cache[note] = result
	return result


## 星星扫到某个分区时，把该分区里这条 Path 的中段擦掉（头 10% / 尾 15% 保留）。
func cut_path_sector(note: Note, sector: int) -> void:
	var ranges: Array = (path_sector_ranges(note) as Dictionary).get(sector, [])
	if ranges.is_empty():
		return
	var cuts: Array = path_sector_cuts.get(note.id, [])
	var changed := false
	for span in ranges:
		var a := maxf(0.10, float(span.get("from", 0.0)))
		var b := minf(0.85, float(span.get("to", 0.0)))
		if b - a <= 0.01:
			continue
		var duplicate := false
		for old in cuts:
			if absf(float(old.get("from", 0.0)) - a) < 0.005 and absf(float(old.get("to", 0.0)) - b) < 0.005:
				duplicate = true
				break
		if duplicate:
			continue
		cuts.append({"from": a, "to": b})
		changed = true
	if not changed:
		return
	path_sector_cuts[note.id] = cuts
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


func _path_local_screen(chart: Chart, local: Vector2, t: float, scale: float = 1.0) -> Vector2:
	var radius := local.length()
	if radius <= 0.0001:
		return project_design(Vector2.ZERO)
	var degrees := fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
	var data := _boundary_point(chart, degrees / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * radius * clampf(scale, 0.0, 1.0))


func _path_screen_point(chart: Chart, note: Note, relative_beat: float, t: float, cache_sample: bool = true, scale: float = 1.0) -> Vector2:
	var local: Vector2
	if cache_sample:
		if not _path_local_cache.has(note):
			_path_local_cache[note] = {}
		var samples: Dictionary = _path_local_cache[note]
		if not samples.has(relative_beat):
			samples[relative_beat] = note.path_local_at(relative_beat)
		local = samples[relative_beat]
	else:
		# The moving marker has a new relative time every frame; do not retain it.
		local = note.path_local_at(relative_beat)
	return _path_local_screen(chart, local, t, scale)


static func skin_presets() -> Dictionary:
	return {
		"candy": {"label": "糖霜胶囊", "scale": 1.20, "band": 1.14, "outline": 1.0, "glow": 1.3, "gloss": 0.6, "shadow": 0.8, "fill": 0.95},
		"neon": {"label": "霓虹线框", "scale": 1.10, "band": 1.06, "outline": 0.45, "glow": 2.0, "gloss": 0.15, "shadow": 0.0, "fill": 0.70},
		"glass": {"label": "玻璃棱镜", "scale": 1.16, "band": 1.10, "outline": 0.8, "glow": 0.9, "gloss": 0.9, "shadow": 0.35, "fill": 0.42},
		"sticker": {"label": "街机贴纸", "scale": 1.28, "band": 1.20, "outline": 1.55, "glow": 0.15, "gloss": 0.0, "shadow": 1.0, "fill": 1.0},
	}


static func hit_fx_presets() -> Dictionary:
	return {"burst": "迸裂", "ring": "圆环", "prism": "棱镜", "ink": "墨滴"}


func refresh_style() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _skin() -> Dictionary:
	if _skin_cache_key == note_skin and not _skin_cache.is_empty():
		return _skin_cache
	var presets := skin_presets()
	var chosen: Dictionary = presets.get(note_skin, {})
	if chosen.is_empty():
		chosen = presets["candy"]
	_skin_cache = chosen.duplicate()
	_skin_cache["id"] = note_skin if presets.has(note_skin) else "candy"
	_skin_cache_key = note_skin
	return _skin_cache


func _stroke_band(canvas: Control, points: PackedVector2Array, color: Color, width: float, alpha: float = 1.0, size_scale: float = -1.0, glow_mul: float = 1.0) -> void:
	# 所有音符共用同一套描边/高光/发光，换肤只改参数，不改判定。
	if points.size() < 2:
		return
	var skin := _skin()
	var k := float(skin["scale"]) if size_scale < 0.0 else size_scale
	var band := float(skin["band"]) if size_scale < 0.0 else 1.0
	var outline := float(skin["outline"])
	var glow := float(skin["glow"])
	var gloss := float(skin["gloss"])
	var shadow := float(skin["shadow"])
	var w := width * k * band
	if glow > 0.01 and glow_mul > 0.01:
		# 柔光层很宽、对比低，关掉 AA 省下的三角形很可观，观感几乎不变。
		# glow_mul = 0 表示画质项关了柔光：只跳这一层，描边/白边/色带照画。
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.10 * glow * glow_mul * alpha), w + 18.0 * glow_mul, false)
	if shadow > 0.01:
		var offset := PackedVector2Array()
		for p in points:
			offset.append(p + Vector2(5, 7) * shadow)
		canvas.draw_polyline(offset, Color(0, 0, 0, 0.38 * shadow * alpha), w + 10.0, false)
	canvas.draw_polyline(points, Color(0, 0, 0, 0.62 * outline * alpha), w + 5.0 * outline, false)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.92 * alpha), w, false)
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.94 * alpha), maxf(3.0, w * 0.62), false)
	if gloss > 0.01:
		canvas.draw_polyline(points, Color(1, 1, 0.94, 0.34 * gloss * alpha), maxf(1.5, w * 0.16), false)
	if String(skin["id"]) == "neon":
		canvas.draw_polyline(points, Color(0.04, 0.06, 0.08, 0.85 * alpha), maxf(2.0, w * 0.20), false)


## 环上的圆：星头的落点标记（不再包含星星本体）。
func _draw_path_circle(canvas: Control, point: Vector2, scale: float, color: Color, alpha: float, ring_mul: float = 1.0) -> void:
	if not _valid_point(point):
		return
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE * PATH_HEAD_SCALE
	canvas.draw_circle(point, 31.0 * s * ring_mul, Color(color.r, color.g, color.b, 0.16 * alpha))
	canvas.draw_circle(point, 24.0 * s * ring_mul, Color(0, 0, 0, 0.30 * alpha))
	canvas.draw_arc(point, 24.0 * s * ring_mul, 0.0, TAU, 30, Color(1, 1, 1, 0.30 * alpha), 2.0, false)


## 下落中的星星：只保留星形 + 光晕。
func _draw_path_star(canvas: Control, point: Vector2, scale: float, color: Color, alpha: float) -> void:
	if not _valid_point(point):
		return
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE * PATH_HEAD_SCALE
	canvas.draw_circle(point, 32.0 * s, Color(color.r, color.g, color.b, 0.18 * alpha))
	canvas.draw_circle(point, 20.0 * s, Color(color.r, color.g, color.b, 0.10 * alpha))
	_draw_star_filled(canvas, point, 22.0 * s, Color(color.r, color.g, color.b, alpha))


func _draw_star_filled(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for layer in 3:
		points = PackedVector2Array()
		var layer_radius := radius + (3.6 if layer == 0 else (1.2 if layer == 1 else 0.0))
		for i in 10:
			var angle := -PI * 0.5 + TAU * float(i) / 10.0
			var r := layer_radius if i % 2 == 0 else layer_radius * 0.45
			points.append(point + Vector2(cos(angle), sin(angle)) * r)
		canvas.draw_colored_polygon(points, Color(0, 0, 0, 0.68) if layer == 0 else (Color(1, 1, 1, 0.96) if layer == 1 else color))
		points.append(points[0])
		canvas.draw_polyline(points, Color(0, 0, 0, 0.7) if layer == 0 else (Color(1, 1, 1, 0.96) if layer == 1 else UITheme.INK), 1.4, false)
	canvas.draw_circle(point, radius * 0.24, Color(0, 0, 0, 0.82))


func _draw_path_tail(canvas: Control, point: Vector2, top: bool, scale: float = 1.0, color: Color = UITheme.GOLD, dim: float = 1.0) -> void:
	if not _valid_point(point):
		return
	var alpha := (1.0 if top else 0.45) * dim
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE
	# 尾部不再画星星，只留一个细环标记终点。
	canvas.draw_circle(point, 8.0 * s, Color(color.r, color.g, color.b, 0.08 * alpha))
	canvas.draw_arc(point, 6.5 * s, 0.0, TAU, 30, Color(color.r, color.g, color.b, 0.70 * alpha), 1.6, false)


func _hold_node_screen(chart: Chart, note: Note, relative_beat: float, relative_angle: float, t: float) -> Vector2:
	var duration := maxf(0.001, note.duration())
	var q := clampf(relative_beat / duration, 0.0, 1.0)
	var angle := fposmod(note.angle + relative_angle, 360.0)
	var data := _boundary_point(chart, angle / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	var center := project_design(Vector2.ZERO)
	var boundary := project_design(data.point)
	return center.lerp(boundary, 0.25).lerp(boundary, q)


## Hold 头/尾共用的圆角金条贴图。
func _draw_hold_cap_band(canvas: Control, band_a: Vector2, band_b: Vector2, fade: float, tint: Color = UITheme.GOLD) -> void:
	var ns := _note_scale()
	var band_w := 16.0 * ns
	canvas.draw_line(band_a, band_b, Color(0, 0, 0, 0.55 * fade), band_w + 6.0 * ns, false)
	canvas.draw_line(band_a, band_b, Color(1, 1, 1, 0.92 * fade), band_w, false)
	canvas.draw_line(band_a, band_b, Color(tint.r, tint.g, tint.b, 0.95 * fade), band_w * 0.62, false)
	canvas.draw_circle(band_a, band_w * 0.5, Color(tint.r, tint.g, tint.b, 0.95 * fade))
	canvas.draw_circle(band_b, band_w * 0.5, Color(tint.r, tint.g, tint.b, 0.95 * fade))
	canvas.draw_circle(band_a, band_w * 0.5, Color(1, 1, 1, 0.92 * fade), false, 2.0, true)
	canvas.draw_circle(band_b, band_w * 0.5, Color(1, 1, 1, 0.92 * fade), false, 2.0, true)
	canvas.draw_line(band_a + Vector2(0, -band_w * 0.18), band_b + Vector2(0, -band_w * 0.18), Color(1, 1, 0.94, 0.45 * fade), band_w * 0.18, false)


## Hold 尾端：形状同头，但用多层柔光代替锐利描边，一眼就能分清头尾。
func _draw_hold_tail_band(canvas: Control, band_a: Vector2, band_b: Vector2, fade: float, tint: Color = UITheme.GOLD) -> void:
	var ns := _note_scale()
	var band_w := 16.0 * ns
	for layer in 4:
		var k := float(layer) / 3.0
		var w := band_w * lerpf(2.0, 0.9, k)
		var a := lerpf(0.05, 0.28, k) * fade
		var c := Color(tint.r, tint.g, tint.b, a)
		canvas.draw_line(band_a, band_b, c, w, false)
		canvas.draw_circle(band_a, w * 0.5, c)
		canvas.draw_circle(band_b, w * 0.5, c)
	# 中间只留一点白芯，保证尾巴位置读得出来，但不抢头部的注意力。
	canvas.draw_line(band_a, band_b, Color(1, 1, 1, 0.30 * fade), band_w * 0.34, false)
	canvas.draw_circle(band_a, band_w * 0.17, Color(1, 1, 1, 0.30 * fade))
	canvas.draw_circle(band_b, band_w * 0.17, Color(1, 1, 1, 0.30 * fade))


func _draw_hold_sector(canvas: Control, chart: Chart, note: Note, t: float, pre: float, fade: float, hide_head: bool = false, tint: Color = UITheme.GOLD, part: int = 0, highlight: bool = false) -> void:
	# 直长条 = 一个从圆心张开的扇形。整根条按**同一个径向速度**往判定环落：
	# 头部（外缘）在 pre 拍内从圆心走到环上，尾部（内缘）晚 duration 拍跟随，
	# 所以看起来是匀速下落，而不是"先快速长出来再慢慢收"。
	# part 0 = 身体，1 = 头/尾/高亮；分两遍画，同角度的 Hold 头永远压在身体上层。
	var width := maxf(4.0, note.arc_width())
	var half := width * 0.5
	var steps := clampi(int(width / 3.0), 8, 48)
	var duration := maxf(0.001, note.duration())
	var head_start := _spawn_beat(chart, note.beat)
	var read := maxf(0.001, note.beat - head_start)
	var outer_scale := clampf((t - head_start) / read, 0.0, 1.0)
	var inner_scale := clampf((t - note.beat - duration + read) / read, 0.0, 1.0)
	# 尾端压到环上（inner_scale 到 1）后不再返回：退化成零宽的最后一帧要留着，
	# 让尾端光带停在环上淡出，而不是当帧消失。
	if outer_scale <= 0.005:
		return
	var center := project_design(Vector2.ZERO)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var edges := PackedVector2Array()
	for i in steps + 1:
		var angle := note.angle - half + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, t)
		if bool(data.get("gap", false)):
			continue
		var edge := project_design(data.point)
		edges.append(edge)
		outer.append(center.lerp(edge, outer_scale))
		inner.append(center.lerp(edge, inner_scale))
	if outer.size() < 2:
		return
	if part == 0:
		var polygon := PackedVector2Array()
		polygon.append_array(outer)
		for i in range(inner.size() - 1, -1, -1):
			polygon.append(inner[i])
		# 头亮尾暗：从内缘到外缘分 10 段渐亮（世界计划式）。
		var slices := 10
		for s in slices:
			var s0 := lerpf(inner_scale, outer_scale, float(s) / float(slices))
			var s1 := lerpf(inner_scale, outer_scale, float(s + 1) / float(slices))
			if s1 - s0 < 0.004 or edges.size() < 2:
				continue
			var quad := PackedVector2Array()
			for k in edges.size():
				quad.append(center.lerp(edges[k], s1))
			for k in range(edges.size() - 1, -1, -1):
				quad.append(center.lerp(edges[k], s0))
			var alpha := lerpf(0.07, 0.42, float(s) / float(maxi(1, slices - 1)))
			canvas.draw_colored_polygon(quad, Color(tint.r, tint.g, tint.b, alpha * fade))
		# 外弧：贴着判定环的高亮边。
		canvas.draw_polyline(outer, Color(1, 1, 1, 0.72 * fade), 2.0, false)
		canvas.draw_polyline(outer, Color(tint.r, tint.g, tint.b, 0.95 * fade), 1.0, false)
		# 内弧：长条尾端，往判定环方向收缩；越窄越亮。
		if inner.size() > 1 and inner_scale > 0.002:
			var tail_alpha := lerpf(0.35, 1.0, clampf(inner_scale, 0.0, 1.0))
			canvas.draw_polyline(inner, Color(tint.r, tint.g, tint.b, tail_alpha * fade), 3.0, false)
			canvas.draw_polyline(inner, Color(1, 1, 1, 0.28 * tail_alpha * fade), 1.2, false)
		# 两侧的径向边，让扇形边界清楚。
		if outer.size() == inner.size() and outer.size() > 1:
			var edge_alpha := 0.30 * fade
			canvas.draw_line(outer[0], inner[0], Color(1, 1, 1, edge_alpha), 1.0, false)
			canvas.draw_line(outer[-1], inner[-1], Color(1, 1, 1, edge_alpha), 1.0, false)
		return
	# 头部：圆角金条 + 白色内高光（世界计划式的圆润端头）；尾部虚化。
	if outer.size() > 1 and not hide_head:
		if highlight:
			# 下一颗要按的 Hold：头带外再垫一层柔光，叠在一起时先看它。
			canvas.draw_line(outer[0], outer[outer.size() - 1], Color(tint.r, tint.g, tint.b, 0.22 * fade), 30.0 * _note_scale(), false)
			canvas.draw_line(outer[0], outer[outer.size() - 1], Color(1, 1, 1, 0.30 * fade), 24.0 * _note_scale(), false)
		_draw_hold_cap_band(canvas, outer[0], outer[outer.size() - 1], fade, tint)
	if inner.size() > 1 and inner_scale > 0.002:
		_draw_hold_tail_band(canvas, inner[0], inner[inner.size() - 1], fade, tint)


## 同角度多颗 Hold 的深度：越晚到越淡，先到的保持实心；下限 0.65 保证还看得见。
static func hold_stack_alpha(lead_beats: float, pre_beats: float) -> float:
	var k := clampf(lead_beats / maxf(0.5, pre_beats * 2.0), 0.0, 1.0)
	return lerpf(1.0, 0.65, k)


func _draw_bent_hold(canvas: Control, chart: Chart, note: Note, t: float, pre: float, fade: float, hide_head: bool, tint: Color, part: int = 0, highlight: bool = false) -> void:
	var ns := _note_scale()
	var center := project_design(Vector2.ZERO)
	var body := PackedVector2Array()
	if not note.visual_pts.is_empty():
		# Hold 体节点：和 Path 共用 visual_pts，节点只改画面，不改头部判定。
		var design_points: Array[Dictionary] = [{"db": 0.0, "da": 0.0}]
		design_points.append_array(note.visual_pts)
		design_points.append({"db": note.duration(), "da": 0.0})
		design_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("db", 0.0)) < float(b.get("db", 0.0)))
		for point in design_points:
			var p := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
			if _valid_point(p):
				body.append(center.lerp(p, _approach(chart, note.beat, t)))
	if body.size() < 2:
		return
	var boundary: Vector2 = body[-1]
	var hs := ns * float(_skin()["scale"])
	var cs := ns
	var direction := (boundary - body[maxi(0, body.size() - 2)]).normalized()
	if direction.length_squared() < 0.5:
		direction = (boundary - center).normalized()
	var normal := Vector2(-direction.y, direction.x)
	if part == 0:
		canvas.draw_polyline(body, Color(0, 0, 0, 0.55 * fade), 11.0 * cs, false)
		canvas.draw_polyline(body, Color(1, 1, 1, 0.90 * fade), 6.0 * cs, false)
		canvas.draw_polyline(body, Color(tint.r, tint.g, tint.b, 0.92 * fade), 3.0 * cs, false)
		# 尾端同为虚化：柔光层代替实心金点。
		canvas.draw_circle(body[0], 9.0 * cs, Color(tint.r, tint.g, tint.b, 0.10 * fade))
		canvas.draw_circle(body[0], 6.0 * cs, Color(tint.r, tint.g, tint.b, 0.20 * fade))
		canvas.draw_circle(body[0], 3.0 * cs, Color(tint.r, tint.g, tint.b, 0.70 * fade))
		canvas.draw_circle(body[0], 1.6 * cs, Color(1, 1, 1, 0.30 * fade))
		return
	# 按住中的白点也放在这一遍：同角度有后续 Hold 时不会被身体盖住。
	if t >= note.beat and t <= note.end_beat:
		var progress := clampf((t - note.beat) / maxf(0.001, note.duration()), 0.0, 1.0)
		var marker_index := progress * float(body.size() - 1)
		var lower := clampi(int(marker_index), 0, body.size() - 1)
		var upper := mini(lower + 1, body.size() - 1)
		var marker := body[lower].lerp(body[upper], marker_index - float(lower))
		canvas.draw_circle(marker, 12.0 * hs, Color(1, 1, 1, 0.28))
		canvas.draw_circle(marker, 8.0 * hs, Color(1, 1, 1, 0.96))
		canvas.draw_circle(marker, 4.0 * hs, tint)
	# 外端：一小段横杆当"头"，宽度随整体一起放大。
	var knob := 9.0 * cs
	if not hide_head:
		if highlight:
			canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(tint.r, tint.g, tint.b, 0.22 * fade), 15.0 * cs, false)
			canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(1, 1, 1, 0.30 * fade), 11.0 * cs, false)
		canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(0, 0, 0, 0.55 * fade), 7.0 * cs, false)
		canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(1, 1, 1, 0.95 * fade), 5.0 * cs, false)
		canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(tint.r, tint.g, tint.b, 0.95 * fade), 2.6 * cs, false)
	if show_debug and t < note.beat + 0.02:
		var head := _flying_position(chart, note.angle, note.beat, t, pre)
		if _valid_point(head):
			canvas.draw_string(UITheme.bold_font(), head + Vector2(-14, -22), "HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(tint.r, tint.g, tint.b, 0.85))
	if not hide_head and t >= note.beat and t <= note.end_beat:
		var glow := 0.5 + 0.5 * sin(t * PI)
		canvas.draw_arc(boundary, 28.0 * hs, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.28 * glow), 2.6, false)
	if _app != null and not note.visual_pts.is_empty():
		var selected: Note = _app.get_selected_note()
		if selected != null and selected.id == note.id:
			for point in note.visual_pts:
				var marker := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
				if _valid_point(marker):
					_draw_diamond(canvas, marker, 5.5, tint)


func _draw_holds(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var ns := _note_scale()
	var visible: Array[Note] = []
	for note in _notes_in_range(chart, t - pre - 128.0, t + pre + 0.3):
		if note.type != "hold":
			continue
		var fade_beats := end_fade_beats(chart.timing.bpm_at(note.beat))
		if t >= _spawn_beat(chart, note.beat) and t <= note.end_beat + maxf(0.3, fade_beats):
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	var draw: Dictionary = {}
	var next_id := -1
	var next_lead := INF
	for note in visible:
		var state := note_state(note.id)
		var tint := _note_tint(note, UITheme.GOLD)
		var fade_beats := end_fade_beats(chart.timing.bpm_at(note.beat))
		var fade := 1.0
		if state == "hit":
			fade = clampf(1.0 - (t - float(note_state_beats.get(note.id, note.end_beat))) / fade_beats, 0.0, 1.0)
		elif state == "miss":
			if not note_state_beats.has(note.id):
				continue
			fade = clampf(1.0 - (t - float(note_state_beats[note.id])) / 0.24, 0.0, 1.0)
		elif t > note.end_beat:
			fade = clampf(1.0 - (t - note.end_beat) / fade_beats, 0.0, 1.0)
		if state == "slip":
			fade *= HOLD_SLIP_DIM
		if fade <= 0.01:
			continue
		var hide_head := state == "holding" or state == "slip" or t >= note.end_beat
		var straight := true
		for point in note.visual_pts:
			if absf(float(point.get("da", 0.0))) > 0.5:
				straight = false
				break
		var lead := note.beat - t
		var depth := hold_stack_alpha(lead, pre)
		draw[note.id] = {
			"fade": fade, "hide_head": hide_head, "tint": tint, "straight": straight,
			"body_fade": fade * depth,
			"cap_fade": fade * lerpf(1.0, 0.85, clampf(lead / maxf(0.5, pre * 2.0), 0.0, 1.0)),
		}
		if lead >= -0.02 and lead < next_lead:
			next_lead = lead
			next_id = note.id
	# 身体按 beat 降序：先到的最后画，叠在上面；后到的整体更淡。
	for note in visible:
		var d: Dictionary = draw.get(note.id, {})
		if d.is_empty():
			continue
		if bool(d["straight"]):
			_draw_hold_sector(canvas, chart, note, t, pre, float(d["body_fade"]), bool(d["hide_head"]), d["tint"], 0, false)
		else:
			_draw_bent_hold(canvas, chart, note, t, pre, float(d["body_fade"]), bool(d["hide_head"]), d["tint"], 0, false)
	# 头/尾/按住标记统一最后画：同角度叠在一起时，每个 Hold 的头都看得见。
	for note in visible:
		var d: Dictionary = draw.get(note.id, {})
		if d.is_empty():
			continue
		if bool(d["straight"]):
			_draw_hold_sector(canvas, chart, note, t, pre, float(d["cap_fade"]), bool(d["hide_head"]), d["tint"], 1, note.id == next_id)
		else:
			_draw_bent_hold(canvas, chart, note, t, pre, float(d["cap_fade"]), bool(d["hide_head"]), d["tint"], 1, note.id == next_id)


func _draw_notes(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var visible: Array[Note] = []
	# 试玩里音符留到判定出来为止（MISS 窗口最长 0.3s），编辑器预览仍只多留 0.3 拍。
	var tail_beats := 2.0 if playtest_mode else 0.3
	for note in _notes_around(chart, t, 0.1, 0.1):
		if note.type in ["path", "hold", "seek"]:
			continue
		if t >= _spawn_beat(chart, note.beat) and t <= note.beat + tail_beats:
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	for note in visible:
		if note_is_retired(note_state(note.id)):
			continue
		match note.type:
			"tap":
				_draw_tap_note(canvas, chart, note, t, pre)
			"anchor":
				var grow := _approach(chart, note.beat, t)
				var p := _flying_position(chart, note.angle, note.beat, t, pre)
				var ns := maxf(1.0, _note_scale())
				if _valid_point(p):
					canvas.draw_circle(p, 40.0 * ns * grow, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.14))
				# 多押线：两颗锚点之间一条细实线，随下落逐渐显现。
				var partner := chart.anchor_partner(note)
				if partner != null and note.id < partner.id:
					var q := _flying_position(chart, partner.angle, partner.beat, t, pre)
					if _valid_point(p) and _valid_point(q):
						canvas.draw_line(p, q, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.55 * grow), 2.0, true)
				_draw_diamond(canvas, p, 24.0 * ns * clampf(grow, 0.35, 1.0), UITheme.VIOLET)
			"bell":
				_draw_bell(canvas, chart, note, t)


func _draw_tap_donut(canvas: Control, point: Vector2, radius: float, color: Color, alpha: float = 1.0) -> void:
	# 舞萌式 Tap：固定大小的粉色圆环，不随判定宽度拉成长条。
	var skin := _skin()
	var outline := float(skin["outline"])
	var glow := float(skin["glow"])
	var gloss := float(skin["gloss"])
	canvas.draw_circle(point, radius + 10.0, Color(color.r, color.g, color.b, 0.10 * glow * alpha))
	canvas.draw_circle(point, radius + 3.5 * outline, Color(0, 0, 0, 0.66 * alpha))
	canvas.draw_circle(point, radius + 1.2, Color(1, 1, 1, 0.94 * alpha))
	canvas.draw_circle(point, radius - 1.0, Color(color.r, color.g, color.b, 0.95 * alpha))
	canvas.draw_circle(point, radius * 0.58, Color(0.04, 0.05, 0.07, 0.92 * alpha))
	canvas.draw_arc(point, radius * 0.58, 0.0, TAU, 28, Color(1, 1, 1, 0.55 * alpha), 1.4, false)
	canvas.draw_circle(point, radius * 0.18, Color(color.r, color.g, color.b, 0.65 * alpha))
	if gloss > 0.01:
		canvas.draw_arc(point, radius * 0.82, -PI * 0.85, -PI * 0.25, 16, Color(1, 1, 1, 0.42 * gloss * alpha), 2.0, false)


func _draw_tap_note(canvas: Control, chart: Chart, note: Note, t: float, pre: float) -> void:
	# 长度系统：普通 Tap = 0.5 l，大小 Tap = size_ratio × l；条带随半径从 1/6 长到 1。
	var progress := _approach(chart, note.beat, t)
	var q := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress)
	var tint := _note_tint(note, UITheme.PINK)
	var center_point := _draw_length_band(canvas, chart, note.angle, note.arc_width(), q, t, tint)
	if show_debug and _valid_point(center_point):
		var ns := _note_scale()
		canvas.draw_string(UITheme.bold_font(), center_point + Vector2(-12, -22), "TAP %.0f°%s" % [note.arc_width(), " ×l %.2f" % note.size_ratio if note.sized else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(tint.r, tint.g, tint.b, 0.85))


## Tap 与 Hold 头共用的“长度条”：一段按 radius_scale 缩放的弧带 + 两端圆头 + 中心点。
## 返回中心点屏幕坐标（可能为 INF）。
func _draw_length_band(canvas: Control, chart: Chart, angle: float, width: float, radius_scale: float, t: float, color: Color, alpha: float = 1.0) -> Vector2:
	var ns := _note_scale()
	var radius := clampf(radius_scale, 0.0, 1.0)
	if width <= 0.05:
		# 长度为 0 的大小 Tap 仍然占一个位置，留一个点提示它存在。
		var tip := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, t)
		if bool(tip.get("gap", false)):
			return Vector2(INF, INF)
		var dot := project_design((tip.point as Vector2) * radius)
		if _valid_point(dot):
			canvas.draw_circle(dot, 7.0 * ns, Color(color.r, color.g, color.b, 0.90 * alpha))
		return dot
	# 省电档也只是降采样，不能再低到把长条画成折线。
	var steps := clampi(int(width / (4.0 if note_detail_fine else 6.0)), 16, 96)
	var points := PackedVector2Array()
	for i in steps + 1:
		var sample_angle := angle - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(sample_angle, 360.0) / 360.0, t)
		if bool(data.get("gap", false)):
			continue
		var p := project_design(data.point * radius)
		if _valid_point(p):
			points.append(p)
	if points.size() < 2:
		return Vector2(INF, INF)
	# 胶囊本体（黑描边 + 白边 + 色带 + 高光）永远画；画质项只决定最外层柔光。
	# 之前把整次 _stroke_band 塞进 if note_glow，关光晕时 Tap / Hold 头只剩几个点。
	_stroke_band(canvas, points, color, 18.0 * ns, alpha, -1.0, 0.35 if note_glow else 0.0)
	var cap_scale := ns * float(_skin()["scale"])
	var center_point := points[points.size() / 2]
	# 两端圆头：让长条读成一根胶囊，而不是一段没有边界的弧。
	for cap in [points[0], points[-1]]:
		canvas.draw_circle(cap, 12.0 * cap_scale, Color(0, 0, 0, 0.66 * alpha))
		canvas.draw_circle(cap, 9.5 * cap_scale, Color(1, 1, 1, 0.94 * alpha))
		canvas.draw_circle(cap, 6.0 * cap_scale, Color(color.r, color.g, color.b, alpha))
	# 中心命中点：宽度变化时仍然知道该按哪里。
	canvas.draw_circle(center_point, 8.0 * cap_scale, Color(0, 0, 0, 0.55 * alpha))
	canvas.draw_circle(center_point, 6.0 * cap_scale, Color(1, 1, 1, 0.96 * alpha))
	canvas.draw_circle(center_point, 3.0 * cap_scale, color)
	return center_point


func _draw_seeks(canvas: Control, chart: Chart, t: float) -> void:
	var pre := _pre_read_beats(chart, t)
	var center := project_design(Vector2.ZERO)
	# 环半径必须从真实边界点取；project_design(1,0) 只是设计坐标 1px，不是环。
	var ring_radius := 0.0
	for u in [0.0, 0.25, 0.5, 0.75]:
		var edge := project_u(u, t)
		if _valid_point(edge):
			ring_radius = maxf(ring_radius, center.distance_to(edge))
	ring_radius = maxf(20.0, ring_radius)
	# 必须把整个预读窗口都取进来：Seek 从 note.beat - pre 就开始从圆心长大。
	for note in _notes_around(chart, t, 2.0, 0.5):
		if note.type != "seek" or t < _spawn_beat(chart, note.beat) or t > note.beat + 0.5:
			continue
		var grow := _approach(chart, note.beat, t)
		var fade := clampf((note.beat + 0.5 - t) / 0.5, 0.0, 1.0)
		var color := UITheme.SEEK_IN if note.seek_orien == 1 else UITheme.SEEK_OUT
		var radius := ring_radius * grow
		canvas.draw_arc(center, radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.16 * fade), 10.0, true)
		canvas.draw_arc(center, radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.95 * fade), 3.0, true)
		var inward := note.seek_orien == 1
		var count := 8
		for i in count:
			var a := TAU * float(i) / float(count) - PI * 0.5
			var dir := Vector2(cos(a), sin(a))
			# 里向心、外向外：方向与滚轮一致（外 = 上滑）。
			var tip := center + dir * radius + dir * (-8.0 if inward else 8.0)
			var base := center + dir * radius
			var side := Vector2(-dir.y, dir.x) * 4.5
			canvas.draw_colored_polygon(PackedVector2Array([
				tip, base + side, base - side,
			]), Color(color.r, color.g, color.b, 0.9 * fade))
		var label := "SEEK IN" if inward else "SEEK OUT"
		_draw_label(canvas, label, center + Vector2(radius + 12.0, -radius - 8.0), color)


func _draw_onion(canvas: Control, chart: Chart, beat: float) -> void:
	if onion_shapes.is_empty():
		return
	for item in onion_shapes:
		if not (item is BoundaryShape):
			continue
		var shape: BoundaryShape = item
		var run := PackedVector2Array()
		for i in 97:
			var data := shape.point_at(float(i) / 96.0)
			if bool(data.get("gap", false)):
				if run.size() > 1:
					canvas.draw_polyline(run, Color(1, 1, 1, 0.16), 1.0, true)
				run = PackedVector2Array()
				continue
			var p := project_design(data.point)
			if _valid_point(p):
				run.append(p)
		if run.size() > 1:
			canvas.draw_polyline(run, Color(1, 1, 1, 0.16), 1.0, true)


func _draw_boundary_controls(canvas: Control, chart: Chart) -> void:
	if not show_debug and not (_app != null and _app.boundary_mode):
		return
	var shape := _active_shape()
	if shape == null:
		return
	var sorted := shape.sorted_segments()
	var points := shape.vertices()
	var selected: int = -1 if _app == null else int(_app.selected_segment_index)
	for index in points.size():
		var color := UITheme.CORAL if index == selected else UITheme.CYAN
		var p := project_design(points[index])
		if _valid_point(p):
			var rect := Rect2(p - Vector2(5, 5), Vector2(10, 10))
			canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.95))
			canvas.draw_rect(rect, UITheme.BG, false, 1.0)
		if index == selected and index < sorted.size():
			_draw_segment_highlight(canvas, sorted[index], selected)


func _draw_segment_highlight(canvas: Control, segment: BoundarySegment, _index: int) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var p := project_design(segment.point_at(float(i) / 32.0))
		if _valid_point(p):
			points.append(p)
	if points.size() > 1:
		canvas.draw_polyline(points, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.45), 6.0, false)


func _draw_cursor(canvas: Control, chart: Chart, t: float) -> void:
	if not custom_cursor_visible or (not mouse_inside and not playtest_mode):
		return
	_draw_player_cursor(canvas)
	if playtest_mode:
		return
	var p := project_u(cursor_u, t)
	if cursor_valid and _valid_point(p):
		canvas.draw_circle(p, 7.0, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.22))
		canvas.draw_arc(p, 6.5, 0.0, TAU, 24, UITheme.CORAL, 1.6, false)
		canvas.draw_circle(p, 1.8, UITheme.CORAL)
		if show_debug:
			canvas.draw_string(UITheme.mono_font(), p + Vector2(12, 22), "u %.1f°" % (cursor_u * 360.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func _draw_player_cursor(canvas: Control) -> void:
	var accent := UITheme.CYAN if cursor_valid or playtest_mode else UITheme.MUTED
	var cs := clampf(cursor_scale, 0.5, 2.0)
	# osu 风格拖尾：连续线段填补采样空隙，越靠近光标越大、越亮，停手后自然消失。
	for i in range(1, _cursor_trail.size()):
		var previous: Dictionary = _cursor_trail[i - 1]
		var current: Dictionary = _cursor_trail[i]
		var life := clampf(1.0 - float(current.get("age", 0.0)) / 0.26, 0.0, 1.0)
		if life <= 0.01:
			continue
		var ratio := float(i) / float(maxi(1, _cursor_trail.size() - 1))
		canvas.draw_line(previous["pos"], current["pos"], Color(accent.r, accent.g, accent.b, 0.10 * life), lerpf(2.5, 9.0, ratio) * cs, false)
	for i in _cursor_trail.size():
		var item: Dictionary = _cursor_trail[i]
		var age := float(item.get("age", 0.0))
		var life := clampf(1.0 - age / 0.26, 0.0, 1.0)
		if life <= 0.01:
			continue
		var ratio := float(i + 1) / float(maxi(1, _cursor_trail.size()))
		var point: Vector2 = item["pos"]
		var radius := lerpf(3.0, 10.5, ratio) * cs
		canvas.draw_circle(point, radius, Color(accent.r, accent.g, accent.b, 0.26 * life))
		canvas.draw_circle(point, radius * 0.45, Color(1, 1, 1, 0.16 * life))
	var m := mouse_screen
	var spin := Time.get_ticks_msec() / 1000.0 * 2.2
	canvas.draw_circle(m, 27.0 * cs, Color(accent.r, accent.g, accent.b, 0.035))
	canvas.draw_circle(m, 20.0 * cs, Color(accent.r, accent.g, accent.b, 0.06))
	canvas.draw_arc(m, 19.5 * cs, spin, spin + PI * 0.85, 22, Color(accent.r, accent.g, accent.b, 0.72), 1.7 * cs, false)
	canvas.draw_arc(m, 19.5 * cs, spin + PI, spin + PI * 1.75, 22, Color(accent.r, accent.g, accent.b, 0.34), 1.2 * cs, false)
	canvas.draw_arc(m, 14.0 * cs, 0.0, TAU, 48, Color(0, 0, 0, 0.62), 5.4 * cs, false)
	canvas.draw_arc(m, 14.0 * cs, 0.0, TAU, 48, Color(1, 1, 1, 0.96), 2.6 * cs, false)
	canvas.draw_arc(m, 9.2 * cs, 0.0, TAU, 36, Color(accent.r, accent.g, accent.b, 0.95), 2.0 * cs, false)
	canvas.draw_circle(m, 4.4 * cs, Color(0, 0, 0, 0.78))
	canvas.draw_circle(m, 2.5 * cs, Color(1, 1, 1, 0.98))
	for k in 4:
		var direction := Vector2.from_angle(float(k) * PI * 0.5)
		canvas.draw_line(m + direction * 15.5 * cs, m + direction * 19.0 * cs, Color(1, 1, 1, 0.42), 1.2 * cs, false)
	if not cursor_valid and playtest_mode and show_debug:
		canvas.draw_string(UITheme.mono_font(), m + Vector2(18, -16), "环外", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func request_redraw() -> void:
	_mesh_dirty = true
	if _overlay != null:
		_overlay.queue_redraw()


func add_hit_pulse(point: Vector2, color: Color, label: String = "HIT", kind: String = "tap", detail: String = "") -> void:
	if not _valid_point(point):
		return
	var sparks: Array[float] = []
	for i in 6:
		sparks.append(randf_range(0.0, TAU))
	# 同一位置连续判定时把文字错开，避免完全叠在一起。
	var stack := 0
	for other in _pulses:
		if (other["pos"] as Vector2).distance_to(point) < 56.0:
			stack += 1
	_pulses.append({
		"pos": point, "age": 0.0, "color": color, "label": label, "kind": kind,
		"sparks": sparks, "detail": detail,
		"scale": tier_fx_scale(label),
		"label_y": float(stack % 3) * 22.0,
	})
	# 特效预算：密集段最多同时保留 20 个脉冲，超出丢最旧的。
	while _pulses.size() > 20:
		_pulses.pop_front()
	if _overlay != null:
		_overlay.queue_redraw()


## 命中退场的淡出时长换算成拍：绘制用的是拍时间，手感按秒算。
static func end_fade_beats(bpm: float) -> float:
	return END_FADE_SEC * maxf(1.0, bpm) / 60.0


## 档位越差，爆点越小：BAD 看起来不该和 PERFECT 一样大。
static func tier_fx_scale(label: String) -> float:
	match label:
		"GREAT": return 0.92
		"GOOD": return 0.82
		"BAD": return 0.68
	return 1.0


func add_arc_flash(angle_degrees: float, width: float, beat: float, color: Color) -> void:
	if not playtest_mode or _overlay == null:
		return
	_arc_flashes.append({"angle": angle_degrees, "width": width, "beat": beat, "color": color, "age": 0.0})
	while _arc_flashes.size() > 10:
		_arc_flashes.pop_front()
	_overlay.queue_redraw()


func _draw_arc_flashes(canvas: Control) -> void:
	# 弧闪光同样有预算：密集段只给最新的 4 个画粗描边，旧的只留一条细线。
	var crowded := _arc_flashes.size() > 4
	for index in _arc_flashes.size():
		var flash: Dictionary = _arc_flashes[index]
		var age := float(flash.get("age", 0.0))
		var alpha := clampf(1.0 - age / 0.32, 0.0, 1.0)
		var color: Color = flash["color"]
		var width := float(flash.get("width", 60.0)) * lerpf(1.0, 1.35, age / 0.32)
		var points := _arc_points(float(flash["angle"]), width, float(flash["beat"]), 22)
		if points.size() < 2:
			continue
		if crowded and index < _arc_flashes.size() - 4:
			canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.55 * alpha), 3.0, false)
			continue
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.28 * alpha), 34.0, false)
		canvas.draw_polyline(points, Color(1, 1, 1, 0.7 * alpha), 10.0 * alpha + 2.0, false)
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.95 * alpha), 3.0, false)


## 命中后留在原地的音符本体：整体放大到数倍并淡出（osu!std 击打光）。
func add_note_pop(kind: String, note: Note, beat: float) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var ns := _note_scale()
	var pop := {"kind": kind, "age": 0.0}
	if kind == "anchor":
		var point := note_head_screen(note, beat)
		if not _valid_point(point):
			return
		pop["point"] = point
		pop["color"] = UITheme.VIOLET
		pop["base"] = 24.0 * maxf(1.0, _note_scale())
	elif kind == "path":
		# 只放大环上的星头标记；下落星星和尾环继续走原来的淡出。
		var point := _path_screen_point(chart, note, 0.0, beat)
		if not _valid_point(point):
			return
		pop["point"] = point
		pop["color"] = note.resolved_color(chart, Note.DEFAULT_PATH_COLOR)
		var base_scale := clampf(ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE, 0.2, 2.0)
		pop["base"] = base_scale * float(_skin()["scale"]) * PATH_SIZE_SCALE * PATH_HEAD_SCALE
		pop["arc_base"] = ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE
	else:
		var points := note_live_band(note, beat)
		if points.size() < 2:
			return
		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= float(points.size())
		var skin := _skin()
		pop["points"] = points
		pop["center"] = center
		pop["color"] = UITheme.GOLD if kind == "hold" else UITheme.PINK
		pop["width"] = 18.0 * ns * float(skin["scale"]) * float(skin["band"])
		pop["cap"] = 6.0 * ns * float(skin["scale"])
	_note_pops.append(pop)
	while _note_pops.size() > 24:
		_note_pops.pop_front()
	if _overlay != null:
		_overlay.queue_redraw()


static func note_pop_scale(age: float) -> float:
	var t := clampf(age / NOTE_POP_SEC, 0.0, 1.0)
	return 1.0 + (NOTE_POP_SCALE - 1.0) * (1.0 - pow(1.0 - t, 2.0))


func _draw_note_pops(canvas: Control) -> void:
	for pop in _note_pops:
		var age := float(pop.get("age", 0.0))
		var t := clampf(age / NOTE_POP_SEC, 0.0, 1.0)
		var alpha := 1.0 - t
		if alpha <= 0.01:
			continue
		var pop_scale := note_pop_scale(age)
		var color: Color = pop["color"]
		var flash := clampf(1.0 - age / 0.08, 0.0, 1.0)
		if String(pop.get("kind", "")) == "anchor":
			# 菱形放大淡出 + 四片小菱形向外濺开 + 白色十字光，观感对齐 Tap。
			var point: Vector2 = pop["point"]
			var s := float(pop["base"]) * pop_scale
			var diamond := PackedVector2Array([
				point + Vector2(0.0, -s),
				point + Vector2(s, 0.0),
				point + Vector2(0.0, s),
				point + Vector2(-s, 0.0),
				point + Vector2(0.0, -s),
			])
			canvas.draw_circle(point, s * 2.1, Color(color.r, color.g, color.b, 0.12 * alpha))
			canvas.draw_circle(point, s * 1.4, Color(color.r, color.g, color.b, 0.16 * alpha))
			var spread := s * (1.25 + 1.55 * t)
			for i in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				var shard_center := point + Vector2(cos(a), sin(a)) * spread
				var shard_r := s * 0.30 * (1.0 - 0.45 * t)
				canvas.draw_colored_polygon(PackedVector2Array([
					shard_center + Vector2(0.0, -shard_r),
					shard_center + Vector2(shard_r, 0.0),
					shard_center + Vector2(0.0, shard_r),
					shard_center + Vector2(-shard_r, 0.0),
				]), Color(color.r, color.g, color.b, 0.75 * alpha))
			canvas.draw_polyline(diamond, Color(0, 0, 0, 0.60 * alpha), 5.0)
			canvas.draw_polyline(diamond, Color(1, 1, 1, 0.92 * alpha), 3.0)
			canvas.draw_colored_polygon(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3]]),
				Color(color.r, color.g, color.b, 0.32 * alpha))
			if flash > 0.0:
				var arm := s * (1.5 + 0.9 * (1.0 - flash))
				canvas.draw_line(point - Vector2(arm, 0.0), point + Vector2(arm, 0.0),
					Color(1, 1, 1, 0.75 * flash), 2.5, true)
				canvas.draw_line(point - Vector2(0.0, arm), point + Vector2(0.0, arm),
					Color(1, 1, 1, 0.75 * flash), 2.5, true)
				canvas.draw_circle(point, s * 0.9, Color(1, 1, 1, 0.30 * flash))
			continue
		if String(pop.get("kind", "")) == "path":
			# 星头落点标记整体放大：软光 + 黑底 + 白环 + 颜色外弧。
			var point: Vector2 = pop["point"]
			var s := float(pop["base"]) * pop_scale
			canvas.draw_circle(point, 31.0 * s, Color(color.r, color.g, color.b, 0.16 * alpha))
			canvas.draw_circle(point, 24.0 * s, Color(0, 0, 0, 0.30 * alpha))
			canvas.draw_arc(point, 24.0 * s, 0.0, TAU, 30, Color(1, 1, 1, 0.30 * alpha), 2.0, true)
			canvas.draw_arc(point, 28.0 * float(pop["arc_base"]) * pop_scale, 0.0, TAU, 30,
				Color(color.r, color.g, color.b, 0.95 * alpha), 2.4, true)
			if flash > 0.0:
				canvas.draw_circle(point, 16.0 * s, Color(1, 1, 1, 0.35 * flash))
			continue
		# Tap / Hold 头：把整条音符（带体 + 两端圆头 + 中心点）一起放大淡出。
		var points: PackedVector2Array = pop["points"]
		var center: Vector2 = pop["center"]
		var scaled := PackedVector2Array()
		for p in points:
			scaled.append(center + (p - center) * pop_scale)
		if scaled.size() < 2:
			continue
		var width := float(pop["width"]) * pop_scale
		var cap := float(pop["cap"]) * pop_scale
		canvas.draw_polyline(scaled, Color(0, 0, 0, 0.55 * alpha), width + 5.0 * pop_scale, true)
		canvas.draw_polyline(scaled, Color(1, 1, 1, 0.92 * alpha), width, true)
		canvas.draw_polyline(scaled, Color(color.r, color.g, color.b, 0.94 * alpha), maxf(3.0, width * 0.62), true)
		for endpoint in [scaled[0], scaled[-1]]:
			canvas.draw_circle(endpoint, cap * 2.0, Color(0, 0, 0, 0.66 * alpha))
			canvas.draw_circle(endpoint, cap * 1.58, Color(1, 1, 1, 0.94 * alpha))
			canvas.draw_circle(endpoint, cap, Color(color.r, color.g, color.b, 0.95 * alpha))
		var middle := scaled[scaled.size() / 2]
		canvas.draw_circle(middle, cap * 1.33, Color(0, 0, 0, 0.55 * alpha))
		canvas.draw_circle(middle, cap, Color(1, 1, 1, 0.96 * alpha))
		canvas.draw_circle(middle, cap * 0.5, color)
		if flash > 0.0:
			canvas.draw_polyline(scaled, Color(1, 1, 1, 0.50 * flash), maxf(2.0, width * 0.30), true)


func _draw_pulses(canvas: Control) -> void:
	# 判定字位置（试玩可切）：跟音符 / 屏幕中心 / 关。
	var judge_mode := "note"
	var judge_anchor := Vector2.ZERO
	var center_label_index := -1
	if playtest_mode:
		judge_mode = String(hud_options.get("judge_position", "ring_out"))
		if judge_mode == "center":
			judge_anchor = _screen_affine()[0] + Vector2(0, -90.0 * clampf(size.y / 900.0, 0.8, 1.8))
			# 居中固定位只画最新一条判定，否则 0.42s 内的脉冲会叠成一团。
			for i in range(_pulses.size() - 1, -1, -1):
				if not String(_pulses[i].get("label", "")).is_empty():
					center_label_index = i
					break
	# 脉冲多时只给最新的 6 个画完整特效，其余降级成一个细环。
	# 画质项「精简」永远走降级分支，「关」只留判定字。
	var crowded := fx_budget != "full" or _pulses.size() > 6
	for index in _pulses.size():
		var pulse: Dictionary = _pulses[index]
		var age := float(pulse.get("age", 0.0))
		var alpha := clampf(1.0 - age / 0.42, 0.0, 1.0)
		var point: Vector2 = pulse["pos"]
		var color: Color = pulse["color"]
		var sparks: Array = pulse.get("sparks", []) if fx_budget == "full" else []
		var kind := String(pulse.get("kind", "tap"))
		# 星头单独一套 osu!std 式发散：密度再高也不降级，否则根本看不见。
		if fx_budget == "off" and kind != "path":
			pass
		elif kind != "path" and crowded and index < _pulses.size() - 6:
			canvas.draw_arc(point, 16.0 + age * 30.0, 0.0, TAU, 16, Color(color.r, color.g, color.b, 0.5 * alpha), 2.0, false)
			continue
		# 档位越差，爆点越小；位置按脉冲缩放，文字不缩。
		var fx_scale := float(pulse.get("scale", 1.0))
		var scaled := absf(fx_scale - 1.0) > 0.001
		if scaled:
			canvas.draw_set_transform(point, 0.0, Vector2(fx_scale, fx_scale))
		var fx_point := Vector2.ZERO if scaled else point
		if kind == "path":
			_draw_fx_path_head(canvas, fx_point, color, age)
		elif kind == "lock":
			_draw_fx_lock(canvas, fx_point, age)
		else:
			match hit_fx_style:
				"ring":
					_draw_fx_ring(canvas, fx_point, color, age, sparks)
				"prism":
					_draw_fx_prism(canvas, fx_point, color, age, sparks)
				"ink":
					_draw_fx_ink(canvas, fx_point, color, age, sparks)
				_:
					_draw_fx_burst(canvas, fx_point, color, age, sparks)
		if scaled:
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		match kind:
			"hold":
				canvas.draw_line(point + Vector2(0, -92.0 * (1.0 - alpha)), point - Vector2(0, 20), Color(color.r, color.g, color.b, 0.35 * alpha), 12.0, false)
		var label := String(pulse.get("label", ""))
		# 试玩 HUD 只留档位；偏差明细在结算页和暂停页看。
		var detail := "" if playtest_mode else String(pulse.get("detail", ""))
		var label_y := float(pulse.get("label_y", 0.0))
		var pos := point + Vector2(30, -40 - age * 30 + label_y)
		var label_alpha := alpha
		var detail_alpha := 0.72 * alpha
		var outline_alpha := 0.55 * alpha
		# 街机判定字：26px 基准（900 高），随 HUD 缩放；命中 0.1s 内从 1.25 倍缩回原大。
		var hud_scale := clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
		var judge_base := 26.0 * clampf(canvas.size.y / 900.0, 0.8, 1.8) * hud_scale
		var font_size := int(round(judge_base * (1.0 + 0.25 * clampf(1.0 - age / 0.10, 0.0, 1.0))))
		var detail_size := 12
		var outline_size := 6
		if kind == "path":
			# 星星判定字：不跟命中特效一起淡；满亮 0.25s，0.55s 淡完；画到白爆环外面。
			label_alpha = clampf((0.55 - age) / 0.30, 0.0, 1.0)
			detail_alpha = 0.9 * label_alpha
			outline_alpha = 0.85 * label_alpha
			font_size = _path_label_font_size()
			detail_size = 14
			outline_size = maxi(4, int(font_size * 0.24))
			if judge_mode == "note":
				pos = _path_label_point(point, canvas.size, label, detail, font_size, detail_size)
				pos.y += label_y
		if judge_mode == "ring_in" or judge_mode == "ring_out":
			# 所有音符类型统一贴判定环：内侧/外侧由同一个偏移和缩放决定。
			pos = _ring_judge_label_point(point, canvas.size, label, detail, font_size, detail_size, judge_mode == "ring_out", label_y)
		elif judge_mode == "center":
			if index != center_label_index:
				continue
			pos = judge_anchor + Vector2(0, -age * 30.0)
			pos.x -= UITheme.bold_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		elif judge_mode == "off":
			continue
		canvas.draw_string_outline(UITheme.bold_font(), pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, Color(0, 0, 0, outline_alpha))
		canvas.draw_string(UITheme.bold_font(), pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color.r, color.g, color.b, label_alpha))
		# 早/晚提示：Estella 被批评判定反馈不清，这里把偏差方向直接写在判定字下面。
		if not detail.is_empty():
			# 这里原本用等宽字体，但它没有中文字形，每个不同的“早/晚 X ms”都会触发一次
			# 系统字体回退查找（单次约 18ms），判定密集时会周期性卡顿。改用含中文的正文字体。
			canvas.draw_string(UITheme.FONT_REGULAR, pos + Vector2(0, detail_size + 2), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size, Color(1, 1, 1, detail_alpha))


## 星星判定字字号：约环半径 6.5%，随 HUD 缩放，小预览自动缩、大屏封顶。
func _path_label_font_size() -> int:
	var hud_scale := clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
	return int(round(clampf(_avg_radius_cache * 0.065, 18.0, 40.0) * hud_scale))


func _path_label_point(point: Vector2, bounds: Vector2, label: String, detail: String, font_size: int, detail_size: int) -> Vector2:
	var width := UITheme.bold_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if not detail.is_empty():
		width = maxf(width, UITheme.FONT_REGULAR.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x)
	var block := Vector2(width, float(font_size) + float(detail_size) + 6.0)
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	return path_label_pos(point, center, bounds, block, float(font_size) * 0.82)


## 环内/环外判定字：以音符落点为方向，贴判定环内侧或外侧。
## 偏移随字号和环半径缩放；同角度的多条判定沿半径方向错开。
func _ring_judge_label_point(point: Vector2, bounds: Vector2, label: String, detail: String, font_size: int, detail_size: int, outward: bool, stack: float) -> Vector2:
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	var offset := clampf(maxf(float(font_size) * 1.2, _avg_radius_cache * 0.08), 26.0, 90.0)
	var anchor := judge_label_anchor(point, center, _avg_radius_cache, offset, outward, stack)
	var width := UITheme.bold_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if not detail.is_empty():
		width = maxf(width, UITheme.FONT_REGULAR.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x)
	var block_h := float(font_size) + float(detail_size) + 6.0
	var pos := anchor - Vector2(width * 0.5, float(font_size) * 0.36)
	var margin := 8.0
	pos.x = clampf(pos.x, margin, maxf(margin, bounds.x - width - margin))
	pos.y = clampf(pos.y, float(font_size) * 0.8 + margin, maxf(float(font_size) * 0.8 + margin, bounds.y - block_h - margin))
	return pos


## 判定字锚点：方向取音符落点，半径取落点到环心；落点在圆心时退回环半径。
static func judge_label_anchor(point: Vector2, center: Vector2, fallback_radius: float, offset: float, outward: bool, stack: float = 0.0) -> Vector2:
	var dir := point - center
	var dist := dir.length()
	if dist < 4.0:
		dir = Vector2.UP
		dist = maxf(1.0, fallback_radius)
	else:
		dir /= dist
	var radius := maxf(dist, maxf(1.0, fallback_radius) * 0.55)
	var signed := (offset + stack) if outward else -(offset + stack)
	return center + dir * (radius + signed)


## 星头爆环半径 116px：优先推到外侧，放不下就换内侧，最后夹进画面避免裁切。
static func path_label_pos(point: Vector2, center: Vector2, bounds: Vector2, block: Vector2, ascent: float, dist: float = 132.0) -> Vector2:
	var dir := point - center
	dir = dir.normalized() if dir.length() > 4.0 else Vector2.UP
	var margin := 10.0
	var outward := point + dir * dist
	if _label_fits(outward, bounds, block, ascent, margin):
		return outward
	var inward := point - dir * dist
	if _label_fits(inward, bounds, block, ascent, margin):
		return inward
	return Vector2(
		clampf(outward.x, margin, maxf(margin, bounds.x - block.x - margin)),
		clampf(outward.y, ascent + margin, maxf(ascent + margin, bounds.y - block.y - margin)))


static func _label_fits(pos: Vector2, bounds: Vector2, block: Vector2, ascent: float, margin: float) -> bool:
	return pos.x >= margin and pos.x + block.x <= bounds.x - margin \
		and pos.y - ascent >= margin and pos.y + block.y <= bounds.y - margin


func _draw_fx_path_head(canvas: Control, point: Vector2, color: Color, age: float) -> void:
	# osu!std 式发散：白闪 + 双层扩散圆环 + 12 道放射线，星头命中一眼可见。
	var t := clampf(age / 0.46, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.10, 0.0, 1.0)
	if flash > 0.0:
		canvas.draw_circle(point, 14.0 + 26.0 * flash, Color(1, 1, 1, 0.55 * flash))
		canvas.draw_circle(point, 8.0 + 8.0 * flash, Color(1, 1, 1, 0.95 * flash))
	var main_radius := 12.0 + 104.0 * (1.0 - pow(1.0 - t, 2.4))
	canvas.draw_arc(point, main_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.85 * fade), 2.0 + 5.0 * fade, false)
	var delayed := clampf((age - 0.05) / 0.46, 0.0, 1.0)
	if delayed > 0.0:
		var fade2 := 1.0 - delayed
		var second_radius := 8.0 + 74.0 * (1.0 - pow(1.0 - delayed, 2.0))
		canvas.draw_arc(point, second_radius, 0.0, TAU, 36, Color(color.r, color.g, color.b, 0.65 * fade2), 1.6 + 3.0 * fade2, false)
	for k in 12:
		var angle := float(k) * TAU / 12.0 + age * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var inner := point + direction * (10.0 + 18.0 * t)
		var outer := point + direction * (24.0 + 78.0 * t)
		canvas.draw_line(inner, outer, Color(1, 1, 1, 0.80 * fade), 1.6 + 1.6 * fade, false)
	canvas.draw_circle(point, 14.0 * fade, Color(color.r, color.g, color.b, 0.35 * fade))
	canvas.draw_circle(point, 7.0 * fade, Color(1, 1, 1, 0.95 * fade))


func _draw_fx_lock(canvas: Control, point: Vector2, age: float) -> void:
	# 在场锁定：一圈快速收束的金环，不写判定字；告诉玩家“已经算上了”。
	var t := clampf(age / 0.18, 0.0, 1.0)
	var fade := 1.0 - t
	canvas.draw_arc(point, lerpf(30.0, 12.0, t), 0.0, TAU, 32,
		Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.9 * fade), 2.0 + 2.0 * fade, false)
	canvas.draw_circle(point, 3.0 * fade, Color(1, 1, 1, 0.85 * fade))


func _draw_fx_burst(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# 舞萌式：白闪 + 冲击环 + 锥形碎片，落点最明确。
	var t := clampf(age / 0.40, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.16, 0.0, 1.0)
	if flash > 0.0:
		canvas.draw_circle(point, 48.0 * flash + 8.0, Color(color.r, color.g, color.b, 0.18 * flash))
		canvas.draw_circle(point, 26.0 * flash + 5.0, Color(1, 1, 1, 0.30 * flash))
		canvas.draw_circle(point, 13.0 * flash + 3.0, Color(1, 1, 1, 0.92 * flash))
		# 舞萌式四角星：命中瞬间在音符上炸开一颗星。
		var star_points := PackedVector2Array()
		var spin := -PI * 0.5 + age * 0.9
		for i in 8:
			var angle := spin + TAU * float(i) / 8.0
			var radius := (40.0 * flash + 10.0) if i % 2 == 0 else (13.0 * flash + 5.0)
			star_points.append(point + Vector2(cos(angle), sin(angle)) * radius)
		canvas.draw_colored_polygon(star_points, Color(1, 1, 1, 0.26 * flash))
		var star_outline := star_points.duplicate()
		star_outline.append(star_points[0])
		canvas.draw_polyline(star_outline, Color(1, 1, 1, 0.78 * flash), 2.0, false)
	# 实心冲击盘 + 双层环。
	canvas.draw_circle(point, 30.0 + 42.0 * t, Color(color.r, color.g, color.b, 0.12 * fade))
	var ring_radius := 14.0 + 82.0 * (1.0 - pow(1.0 - t, 3.0))
	canvas.draw_arc(point, ring_radius, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.78 * fade), 3.0 + 6.0 * fade, false)
	canvas.draw_arc(point, ring_radius * 1.26, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.24 * fade), 1.2 + 2.0 * fade, false)
	for i in sparks.size():
		var angle := float(sparks[i])
		var length := 0.40 + 0.60 * absf(sin(float(i) * 2.3))
		var direction := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-direction.y, direction.x)
		var inner := point + direction * (9.0 + 16.0 * t)
		var outer := point + direction * (24.0 + 88.0 * t * length)
		var half := 3.6 * (1.0 - t) + 1.0
		canvas.draw_colored_polygon(PackedVector2Array([inner + normal * half, inner - normal * half, outer]), Color(color.r, color.g, color.b, 0.88 * fade))
		canvas.draw_line(inner, outer, Color(1, 1, 1, 0.72 * fade), 1.2, false)
		canvas.draw_circle(outer, 3.4 * fade, Color(1, 1, 1, 0.90 * fade))
	canvas.draw_circle(point, 8.0 * fade, Color(color.r, color.g, color.b, fade))


func _draw_fx_ring(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# osu 式：实心 hit circle + 向外扩散的光环，干净不挡读谱。
	var t := clampf(age / 0.40, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.12, 0.0, 1.0)
	var core := 34.0 * (1.0 - 0.50 * t)
	if flash > 0.0:
		canvas.draw_circle(point, core + 18.0 * flash, Color(1, 1, 1, 0.22 * flash))
	canvas.draw_circle(point, core + 9.0, Color(color.r, color.g, color.b, 0.26 * fade))
	canvas.draw_circle(point, core, Color(1, 1, 1, 0.92 * fade))
	canvas.draw_arc(point, core + 2.5, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.95 * fade), 4.0 * fade + 1.0, false)
	canvas.draw_arc(point, maxf(2.0, core - 6.0), 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.55 * fade), 1.6, false)
	var ring_radius := 20.0 + 74.0 * (1.0 - pow(1.0 - t, 2.0))
	canvas.draw_arc(point, ring_radius, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.80 * fade), 2.6 + 2.0 * fade, false)
	canvas.draw_arc(point, ring_radius + 11.0, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.28 * fade), 1.2, false)
	for k in 4:
		var angle := PI * 0.25 + float(k) * PI * 0.5
		var spark := point + Vector2(cos(angle), sin(angle)) * (30.0 + 48.0 * t)
		_draw_diamond(canvas, spark, 8.5 * fade, color)
	canvas.draw_circle(point, 6.0 * fade, Color(color.r, color.g, color.b, fade))


func _draw_fx_prism(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# 棱镜式：三色三角碎片旋出，适合高亮曲目。
	var t := clampf(age / 0.32, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.12, 0.0, 1.0)
	canvas.draw_circle(point, 26.0 * flash + 4.0, Color(1, 1, 1, 0.55 * flash))
	var palette: Array[Color] = [color, UITheme.CYAN, UITheme.GOLD]
	for i in 3:
		var base := float(sparks[i % maxi(1, sparks.size())]) if not sparks.is_empty() else float(i) * TAU / 3.0
		var angle := base + t * 1.6
		var center := point + Vector2(cos(angle), sin(angle)) * (12.0 + 72.0 * t)
		var size := (13.0 + 7.0 * sin(float(i))) * (1.0 - 0.5 * t)
		var spin := angle + PI * 0.5 + t * 2.4 * float(i - 1)
		var triangle := PackedVector2Array()
		for j in 3:
			var a := spin + TAU * float(j) / 3.0
			triangle.append(center + Vector2(cos(a), sin(a)) * size)
		var tint: Color = palette[i % palette.size()]
		canvas.draw_colored_polygon(triangle, Color(tint.r, tint.g, tint.b, 0.44 * fade))
		triangle.append(triangle[0])
		canvas.draw_polyline(triangle, Color(1, 1, 1, 0.80 * fade), 1.8, false)
	canvas.draw_circle(point, 8.0 * fade, Color(1, 1, 1, 0.90 * fade))
	canvas.draw_arc(point, 18.0 + 40.0 * t, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.45 * fade), 1.2, false)


func _draw_fx_ink(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# 墨滴式：低多边形飞溅，安静但有重量。
	var t := clampf(age / 0.45, 0.0, 1.0)
	var fade := 1.0 - t
	canvas.draw_circle(point, 18.0 * (1.0 - 0.6 * t), Color(color.r, color.g, color.b, 0.55 * fade))
	canvas.draw_circle(point, 10.0 * (1.0 - 0.5 * t), Color(color.r, color.g, color.b, 0.78 * fade))
	var count := mini(10, sparks.size())
	for i in count:
		var angle := float(sparks[i])
		var distance := (10.0 + 80.0 * t) * (0.35 + 0.65 * absf(sin(float(i) * 1.7)))
		var radius := (3.0 + 5.0 * absf(cos(float(i) * 2.1))) * (1.0 - t)
		canvas.draw_circle(point + Vector2(cos(angle), sin(angle)) * distance, radius, Color(color.r, color.g, color.b, 0.60 * fade))
	if not sparks.is_empty():
		var angle0 := float(sparks[0])
		canvas.draw_line(point, point + Vector2(cos(angle0), sin(angle0)) * (36.0 + 72.0 * t), Color(color.r, color.g, color.b, 0.50 * fade), 3.5 * (1.0 - t) + 0.5, false)
	canvas.draw_circle(point, 3.0 * fade, Color(1, 1, 1, 0.65 * fade))


## draw_string 每帧都会重新排版（CJK 尤其贵）：缓存 TextLine，只在文字变化时重建。
var _hud_text: Dictionary = {}
## 连击动画：上一次的连击数 + 放大/断连的时间戳。
var _hud_combo_prev: int = 0
var _hud_combo_pop_at: int = -100000
var _hud_combo_break_at: int = -100000
var _hud_combo_broken: int = 0


func _draw_cached_text(canvas: Control, key: String, font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var entry: Dictionary = _hud_text.get(key, {})
	if entry.is_empty() or String(entry["text"]) != text or int(entry["size"]) != font_size:
		var line := TextLine.new()
		line.add_string(text, font, font_size)
		entry = {"text": text, "size": font_size, "line": line}
		_hud_text[key] = entry
	(entry["line"] as TextLine).draw(canvas.get_canvas_item(), pos, color)


func _draw_hud(canvas: Control, chart: Chart, t: float) -> void:
	if playtest_mode:
		_draw_play_hud(canvas, chart, t)
		return
	_draw_editor_hud(canvas, chart, t)


## 编辑器预览的旧仪表：进度 / 评级 / 准度三段弧 + 误差条。
func _draw_editor_hud(canvas: Control, chart: Chart, t: float) -> void:
	var width := size.x
	var cx := width * 0.5
	var cy := minf(136.0, size.y * 0.20)
	var radius := minf(width * 0.32, 124.0)
	if playtest_mode:
		cy = maxf(170.0, size.y * 0.20)
		radius = minf(width * 0.18, 148.0)
	if radius < 40.0:
		return
	var start := -PI * 0.5 - PI / 6.0
	var end := -PI * 0.5 + PI / 6.0
	var third := (end - start) / 3.0
	if _video != null and _video.visible:
		canvas.draw_rect(Rect2(cx - radius - 24, cy - radius - 18, radius * 2.0 + 48, radius * 1.25 + 54), Color(0, 0, 0, 0.26))
	canvas.draw_arc(Vector2(cx, cy), radius, start, end, 48, Color(0, 0, 0, 0.55), 30.0, false)
	for i in 3:
		var seg_start := start + third * float(i)
		var seg_end := seg_start + third
		canvas.draw_arc(Vector2(cx, cy), radius, seg_start, seg_end, 24, Color(1, 1, 1, 0.06), 24.0, false)
	var progress := clampf(t / maxf(1.0, chart.duration_beats()), 0.0, 1.0)
	canvas.draw_arc(Vector2(cx, cy), radius, start, start + third * progress, 24, UITheme.INK, 24.0, false)
	if hud_rating != "—" and not hud_rating.is_empty():
		canvas.draw_arc(Vector2(cx, cy), radius, start + third, start + third * 2.0, 24, UITheme.GOLD, 24.0, false)
	var accuracy_ratio := 0.5 if hud_accuracy < 0.0 else clampf(hud_accuracy / 100.0, 0.0, 1.0)
	canvas.draw_arc(Vector2(cx, cy), radius, end - third, end - third + third * accuracy_ratio, 24, UITheme.CYAN, 24.0, false)
	var font := UITheme.bold_font()
	var mono := UITheme.mono_font()
	_draw_cached_text(canvas, "hud_progress", font, Vector2(cx - radius * 0.68, cy - radius * 0.52), "进度", 11, UITheme.INK)
	_draw_cached_text(canvas, "hud_rating", font, Vector2(cx - 18, cy - radius * 0.52), hud_rating, 20, UITheme.INK)
	_draw_cached_text(canvas, "hud_accuracy_label", font, Vector2(cx + radius * 0.48, cy - radius * 0.52), "准度", 11, UITheme.CYAN)
	_draw_cached_text(canvas, "hud_progress_value", mono, Vector2(cx - radius * 0.68, cy - radius * 0.32), "%d%%" % roundi(progress * 100.0), 12, UITheme.INK)
	_draw_cached_text(canvas, "hud_accuracy_value", mono, Vector2(cx + radius * 0.48, cy - radius * 0.32), "—" if hud_accuracy < 0.0 else "%.2f%%" % hud_accuracy, 12, UITheme.INK)
	var baseline_y := cy + radius * 0.44
	var tick_left := cx - radius * 0.80
	var tick_right := cx + radius * 0.80
	canvas.draw_line(Vector2(tick_left, baseline_y), Vector2(tick_right, baseline_y), Color(1, 1, 1, 0.16), 1.0, false)
	for i in 20:
		var x := lerpf(tick_left, tick_right, float(i) / 19.0)
		var error := 0.0
		if i < hud_errors.size():
			error = hud_errors[hud_errors.size() - 1 - i]
		var length := 4.0 + minf(12.0, absf(error) / 32.0 * 12.0) if i < hud_errors.size() else 3.0
		var color := Color(1, 1, 1, 0.14)
		if i < hud_errors.size():
			color = UITheme.CYAN if error < 0.0 else UITheme.CORAL
		canvas.draw_line(Vector2(x, baseline_y - 2.0), Vector2(x, baseline_y - 2.0 - length), color, 2.0, false)
	_draw_cached_text(canvas, "hud_preview", mono, Vector2(cx - 34, baseline_y + 20), "预览 / 非正式", 10, UITheme.MUTED)


## Combo 单独走一层：在音符之前绘制，下落 Tap/Hold/Path 会盖住它。
## 左右两列仍在 HUD 层，不受影响。
func _draw_play_combo_layer(canvas: Control) -> void:
	var bounds := size
	if bounds.x < 320.0 or bounds.y < 240.0:
		return
	var op := clampf(float(hud_options.get("opacity", 100)) / 100.0, 0.3, 1.0)
	var hs := clampf(bounds.y / 900.0, 0.8, 1.8)
	var s := hs * clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	var combo_mode := String(hud_options.get("combo_mode", "center"))
	if combo_mode == "off":
		return
	if combo_mode == "center":
		_draw_combo(canvas, UITheme.bold_font(), center, s, 78.0 * s, 2, op)
		return
	# 右侧：和 _draw_hud_score_column 同一套列起点与纵向排布。
	var margin := 14.0 * s
	var ring_r := _hud_ring_radius(get_time_beat()) * 1.2
	var gap := 20.0 * s
	var right_x := center.x + ring_r + gap
	var acc_size := int(round(38.0 * s))
	var label_row := 24.0 * s
	var height := label_row + float(acc_size) + 8.0 * s + 50.0 * s
	var top_y := center.y - height * 0.5
	var combo_y := top_y + label_row + float(acc_size) + 8.0 * s + 34.0 * s
	_draw_combo(canvas, UITheme.bold_font(), Vector2(right_x, combo_y), s, 34.0 * s, 0, op)


## 试玩 HUD v3：信息贴着环的左右两侧，垂直居中。
## 左：TRACK / 曲名 / 难度 / 可选进度与用时；右：ACCURACY / 大字准度 / 评级章 / 连击。
## 判定字仍在音符处；五档计数只在暂停页和结算页显示。
func _draw_play_hud(canvas: Control, chart: Chart, t: float) -> void:
	var bounds := size
	if bounds.x < 320.0 or bounds.y < 240.0:
		return
	var op := clampf(float(hud_options.get("opacity", 100)) / 100.0, 0.3, 1.0)
	var hs := clampf(bounds.y / 900.0, 0.8, 1.8)
	var s := hs * clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
	var margin := 14.0 * s
	var bold := UITheme.bold_font()
	var mono := UITheme.mono_font()
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	var accuracy := hud_accuracy
	var progress := clampf(t / maxf(1.0, chart.duration_beats()), 0.0, 1.0)
	_draw_ring_gauge(canvas, progress, accuracy, s, op)
	# 舞台外圈刻度大约在判定环的 1.19×；HUD 再退到 1.2×，避免压到装饰环。
	var ring_r := _hud_ring_radius(t) * 1.2
	var gap := 20.0 * s
	var side := minf(center.x, bounds.x - center.x) - ring_r - margin - gap
	var col_w := clampf(side, 90.0 * s, 320.0 * s)
	var left_x := center.x - ring_r - gap - col_w
	var right_x := center.x + ring_r + gap
	_draw_hud_track_column(canvas, left_x + col_w, col_w, center.y, s, op, progress, bold, mono)
	_draw_hud_score_column(canvas, right_x, col_w, center.y, s, op, accuracy, bold, mono)
	var combo_mode := String(hud_options.get("combo_mode", "center"))
	if combo_mode == "center" and hud_auto:
		_draw_hud_text(canvas, "p_auto", mono, Vector2(center.x, center.y + 74.0 * s), "AUTO", _hud_small(s), _hud_tint(UITheme.AMBER, op), 2)
	if bool(hud_options.get("show_watermark", false)):
		_draw_hud_text(canvas, "p_watermark", mono, Vector2(margin, bounds.y - margin), "试玩预览 / 非正式", _hud_small(s), _hud_tint(UITheme.MUTED, op))


## 左列：垂直居中，宽度随窗口收窄；长曲名截断成省略号。
func _draw_hud_track_column(canvas: Control, right_x: float, col_w: float, center_y: float, s: float, op: float, progress: float, bold: Font, mono: Font) -> void:
	var show_title := bool(hud_options.get("show_title", true))
	var show_diff := bool(hud_options.get("show_difficulty", true)) and not hud_difficulty.is_empty()
	var show_pct := bool(hud_options.get("show_percent", false))
	var show_time := bool(hud_options.get("show_time", false))
	var height := 0.0
	if show_title:
		height += 15.0 * s
		if not hud_title.is_empty():
			height += 25.0 * s
	if show_diff:
		height += 27.0 * s
	if show_pct:
		height += 15.0 * s
	if show_time:
		height += 15.0 * s
	var y := center_y - height * 0.5
	if show_title:
		_draw_hud_text(canvas, "p_track", mono, Vector2(right_x, y), "TRACK", _hud_small(s), _hud_tint(UITheme.MUTED, 0.85 * op), 1)
		y += 15.0 * s
		if not hud_title.is_empty():
			var title := _hud_fit_text(hud_title, bold, int(round(19.0 * s)), col_w)
			_draw_hud_text(canvas, "p_title", bold, Vector2(right_x, y), title, int(round(19.0 * s)), _hud_tint(UITheme.INK, op), 1)
			y += 25.0 * s
	if show_diff:
		_draw_chip(canvas, Vector2(right_x, y), hud_difficulty, s, op, UITheme.CYAN, 1)
		y += 27.0 * s
	if show_pct:
		_draw_hud_text(canvas, "p_percent", mono, Vector2(right_x, y), "进度 %d%%" % roundi(progress * 100.0), _hud_small(s), _hud_tint(UITheme.MUTED, op), 1)
		y += 15.0 * s
	if show_time:
		_draw_hud_text(canvas, "p_time", mono, Vector2(right_x, y), "%s / %s" % [_hud_time(hud_ms), _hud_time(hud_total_ms)], _hud_small(s), _hud_tint(UITheme.MUTED, op), 1)


## 右列：准度是主体；评级章与 ACCURACY 同排右对齐，连击在下方。
func _draw_hud_score_column(canvas: Control, x: float, col_w: float, center_y: float, s: float, op: float, accuracy: float, bold: Font, mono: Font) -> void:
	var acc_text := "—" if accuracy < 0.0 else "%.2f%%" % accuracy
	var acc_size := int(round(38.0 * s))
	var combo_mode := String(hud_options.get("combo_mode", "center"))
	var reserve_combo := combo_mode == "corner"
	# 标签行要容得下 22px 的评级章，否则章底会压到准度数字顶部。
	var label_row := 24.0 * s
	var height := label_row + acc_size
	if reserve_combo:
		height += 8.0 * s + 50.0 * s
	var y := center_y - height * 0.5
	var small := _hud_small(s)
	var label_w := mono.get_string_size("ACCURACY", HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	var chip_w := mono.get_string_size(hud_rating, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(11, int(round(13.0 * s)))).x + 14.0 * s
	_draw_hud_text(canvas, "p_acc_label", mono, Vector2(x, y), "ACCURACY", small, _hud_tint(UITheme.MUTED, 0.85 * op))
	# 评级章贴着 ACCURACY 标签，不甩到列的最右边。
	_draw_rank_chip(canvas, x + label_w + 10.0 * s + chip_w, y, hud_rating, s, op)
	y += label_row
	_draw_hud_text(canvas, "p_acc", bold, Vector2(x, y), acc_text, acc_size, _hud_tint(UITheme.INK, op))
	y += acc_size + 8.0 * s
	# Combo 已在音符层下面单独绘制；这里只保留占位高度，避免准度/评级压到连击。


## 环的横向像素半径（取进度带所在的那一圈）；侧栏据此贴住环的切线。
func _hud_ring_radius(t: float) -> float:
	if _max_design_radius > 0.0:
		var affine := _screen_affine()
		return _max_design_radius * (affine[1] as Vector2).length()
	var center := project_design(Vector2.ZERO)
	var radius := 0.0
	for u in [0.0, 0.25, 0.5, 0.75]:
		var edge := project_u(u, t)
		if _valid_point(edge):
			radius = maxf(radius, center.distance_to(edge))
	return radius


## 曲名太长时截成“前缀…”；按文字/字号/宽度缓存，避免每帧重排。
var _hud_fit_cache: Dictionary = {}

func _hud_fit_text(text: String, font: Font, font_size: int, max_width: float) -> String:
	var key := "%s|%d|%d" % [text, font_size, int(max_width)]
	if _hud_fit_cache.has(key):
		return String(_hud_fit_cache[key])
	var result := text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		var cut := text
		result = "…"
		while cut.length() > 1:
			cut = cut.substr(0, cut.length() - 1)
			if font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
				result = cut + "…"
				break
	_hud_fit_cache[key] = result
	return result


func _hud_small(s: float) -> int:
	return maxi(9, int(round(10.0 * s)))


## 环量表：底轨 + 8px 进度带 + 亮点；准度 2px 在外侧。
func _draw_ring_gauge(canvas: Control, progress: float, accuracy: float, s: float, op: float) -> void:
	if _max_design_radius <= 0.0 or String(hud_options.get("progress_style", "ring")) != "ring":
		return
	var affine := _screen_affine()
	var band_r := _max_design_radius * 1.012
	_hud_arc(canvas, affine, 0.0, 360.0, band_r, _hud_tint(Color(1, 1, 1, 0.10), op), 8.0 * s)
	_hud_arc(canvas, affine, 90.0, 90.0 - 360.0 * progress, band_r, _hud_tint(Color(1, 1, 1, 0.78), op), 8.0 * s)
	var head := 90.0 - 360.0 * progress
	var hp := _affine_point(Vector2(cos(deg_to_rad(head)), sin(deg_to_rad(head))) * band_r, affine)
	canvas.draw_circle(hp, 9.0 * s, _hud_tint(Color(1, 1, 1, 0.16), op))
	canvas.draw_circle(hp, 4.0 * s, _hud_tint(Color(1, 1, 1, 0.95), op))
	if accuracy >= 0.0:
		var acc_ratio := clampf(accuracy / 100.0, 0.0, 1.0)
		_hud_arc(canvas, affine, 90.0, 90.0 + 360.0 * acc_ratio, _max_design_radius * 1.045,
			_hud_tint(Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.55), op), 2.0 * s)


## 难度胶囊：细边框 + 半透明底，比裸文字更像街机标签。
func _draw_chip(canvas: Control, pos: Vector2, text: String, s: float, op: float, color: Color, align: int = 0) -> void:
	var font := UITheme.mono_font()
	var size := maxi(10, int(round(11.0 * s)))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0 * s
	var h := 19.0 * s
	var at := pos
	if align == 1:
		at.x -= w
	canvas.draw_rect(Rect2(at.x, at.y, w, h), _hud_tint(color, 0.14 * op))
	canvas.draw_rect(Rect2(at.x, at.y, w, h), _hud_tint(color, 0.55 * op), false, 1.0)
	_draw_hud_text(canvas, "p_chip", font, at + Vector2(7.0 * s, 2.0 * s), text, size, _hud_tint(UITheme.INK, op))


func _draw_rank_chip(canvas: Control, right_x: float, top_y: float, rank: String, s: float, op: float) -> void:
	var color := _rank_color(rank)
	var font := UITheme.mono_font()
	var size := maxi(11, int(round(13.0 * s)))
	var w := font.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0 * s
	var h := 22.0 * s
	canvas.draw_rect(Rect2(right_x - w, top_y, w, h), _hud_tint(color, 0.16 * op))
	canvas.draw_rect(Rect2(right_x - w, top_y, w, h), _hud_tint(color, 0.75 * op), false, 1.0)
	_draw_hud_text(canvas, "p_rank", font, Vector2(right_x - w * 0.5, top_y + 4.0 * s), rank, size, _hud_tint(color, op), 2)


## 连击：≥2 才出现；命中轻微放大，断连变红、下沉、淡出。
func _draw_combo(canvas: Control, font: Font, anchor: Vector2, s: float, base_px: float, align: int, op: float) -> void:
	var now := Time.get_ticks_msec()
	if hud_combo > _hud_combo_prev:
		_hud_combo_pop_at = now
	elif hud_combo < _hud_combo_prev and _hud_combo_prev >= 2:
		_hud_combo_break_at = now
		_hud_combo_broken = _hud_combo_prev
	_hud_combo_prev = hud_combo
	var break_age := float(now - _hud_combo_break_at) / 1000.0
	var flashing := break_age < 0.45
	if hud_combo < 2 and not flashing:
		return
	var pop_age := float(now - _hud_combo_pop_at) / 1000.0
	var pop := 1.0 + 0.08 * maxf(0.0, 1.0 - pop_age / 0.12)
	var color := _hud_tint(UITheme.INK, op)
	var sink := 0.0
	if flashing:
		color = Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, (1.0 - break_age / 0.45) * op)
		pop = 1.04
		sink = 8.0 * s * clampf(break_age / 0.45, 0.0, 1.0)
	var shown := _hud_combo_broken if flashing else hud_combo
	var number_size := int(round(base_px * pop))
	var number_top := anchor.y - number_size * 0.52 + sink
	var label_size := maxi(10, int(round(11.0 * s)))
	var key := "p_combo" if align == 2 else "p_combo_corner"
	_draw_hud_text(canvas, key + "_label", font, Vector2(anchor.x, number_top - label_size - 5.0 * s), "COMBO", label_size, _hud_tint(UITheme.MUTED, 0.9 * op), align)
	_draw_hud_text(canvas, key, font, Vector2(anchor.x, number_top), str(shown), number_size, color, align)


func _hud_tint(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)


func _hud_time(ms: float) -> String:
	var total := int(maxf(0.0, ms) / 1000.0)
	return "%d:%02d" % [total / 60, total % 60]


## HUD 文字：缓存 TextLine（CJK 每帧排版很贵），align 0=左 1=右 2=中。
func _draw_hud_text(canvas: Control, key: String, font: Font, pos: Vector2, text: String, font_size: int, color: Color, align: int = 0) -> void:
	var entry: Dictionary = _hud_text.get(key, {})
	if entry.is_empty() or String(entry["text"]) != text or int(entry["size"]) != font_size:
		var line := TextLine.new()
		line.add_string(text, font, font_size)
		entry = {"text": text, "size": font_size, "line": line, "width": line.get_size().x}
		_hud_text[key] = entry
	var at := pos
	var width := float(entry["width"])
	if align == 1:
		at.x -= width
	elif align == 2:
		at.x -= width * 0.5
	(entry["line"] as TextLine).draw(canvas.get_canvas_item(), at, color)


## 环外仪表弧：按屏幕弧长取点，画满 360° 也不会堆出几千个点。
func _hud_arc(canvas: Control, affine: Array, from_deg: float, to_deg: float, radius: float, color: Color, width: float) -> void:
	var span := deg_to_rad(absf(to_deg - from_deg))
	if span < 0.01:
		return
	var scale := (affine[1] as Vector2).length()
	var steps := clampi(int(span * radius * scale / 3.0), 6, 240)
	var points := PackedVector2Array()
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(steps)))
		points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
	canvas.draw_polyline(points, color, width, true)


func _rank_color(rank: String) -> Color:
	match rank:
		"AAA":
			return UITheme.GOLD
		"AA":
			return UITheme.CYAN
		"A":
			return UITheme.MINT
		"B":
			return UITheme.AMBER
		"C":
			return UITheme.CORAL
	return UITheme.MUTED


func _tier_color(tier: String) -> Color:
	match tier:
		"PERFECT":
			return UITheme.GOLD
		"GREAT":
			return UITheme.CYAN
		"GOOD":
			return UITheme.MINT
		"BAD":
			return UITheme.AMBER
	return UITheme.CORAL


func _draw_debug(canvas: Control, chart: Chart, t: float) -> void:
	var rect := Rect2(10, 10, 238, 82)
	canvas.draw_rect(rect, Color(0, 0, 0, 0.58))
	canvas.draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.35), false, 1.0)
	var mono := UITheme.mono_font()
	canvas.draw_string(mono, Vector2(18, 28), "u %.2f°  |  beat %.2f" % [cursor_u * 360.0, t], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.INK)
	canvas.draw_string(mono, Vector2(18, 44), "time %.0f ms  |  %s" % [chart.timing.beat_to_chart_ms(t), "有效" if cursor_valid else "无位置"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	canvas.draw_string(mono, Vector2(18, 60), "shape %s  |  zoom %.2f" % [chart.default_shape_id, float(current_view().get("zoom", 1.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	canvas.draw_string(mono, Vector2(18, 76), "branch 0  |  D %.0f ms ×%.2f  |  %d fps" % [chart.pre_read_ms, flow_scale, Engine.get_frames_per_second()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	for i in 12:
		var u := float(i) / 12.0
		var p := project_u(u, t)
		if _valid_point(p):
			canvas.draw_string(mono, p + Vector2(4, -4), "%d°" % (i * 30), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.42))


func _polyline_sample(points: PackedVector2Array, fraction: float) -> Dictionary:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target := clampf(fraction, 0.0, 1.0) * total
	var cursor := 0.0
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if cursor + segment >= target and segment > 0.01:
			var p := (target - cursor) / segment
			return {"point": points[i].lerp(points[i + 1], p), "direction": points[i + 1] - points[i]}
		cursor += segment
	return {"point": points[-1], "direction": points[-1] - points[-2] if points.size() > 1 else Vector2.ZERO}


func _draw_arrowhead(canvas: Control, point: Vector2, direction: Vector2, color: Color) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		point + dir * 7.0,
		point - dir * 5.0 + normal * 5.0,
		point - dir * 5.0 - normal * 5.0,
	])
	canvas.draw_colored_polygon(points, color)


func _draw_chevron(canvas: Control, point: Vector2, direction: Vector2, color: Color, size: float) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var tip := point + dir * size * 0.12
	var left := point - dir * size + normal * size * 0.80
	var right := point - dir * size - normal * size * 0.80
	# 一条粗 V 形 polyline：比三层描边少 2/3 draw call，也不产生多边形三角化失败。
	canvas.draw_polyline(PackedVector2Array([left, tip, right]), color, maxf(2.0, size * 0.52), false)


func _draw_star(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(point + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	canvas.draw_polyline(points, color, 2.0, false)
	canvas.draw_circle(point, 2.0, color)


func _draw_ring(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	canvas.draw_arc(point, radius, 0.0, TAU, 28, color, 2.0, false)
	canvas.draw_circle(point, 1.8, color)


func _draw_hexagon(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 6:
		var angle := -PI * 0.5 + TAU * float(i) / 6.0
		points.append(point + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_circle(point, radius + 3.0, Color(0, 0, 0, 0.62))
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, Color(1, 1, 1, 0.96), 2.6, false)
	canvas.draw_circle(point, radius * 0.34, UITheme.BG)
	canvas.draw_circle(point, radius * 0.20, Color(1, 1, 1, 0.9))


func _draw_badge(canvas: Control, text: String, position: Vector2, color: Color) -> void:
	var font := UITheme.bold_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var rect := Rect2(position + Vector2(-text_size.x * 0.5 - 5, -12), Vector2(text_size.x + 10, 16))
	canvas.draw_rect(rect, Color(0, 0, 0, 0.72))
	canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.85), false, 1.0)
	canvas.draw_string(font, position + Vector2(-text_size.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_label(canvas: Control, text: String, position: Vector2, color: Color) -> void:
	var font := UITheme.mono_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
	var rect := Rect2(position + Vector2(-3, -9), Vector2(text_size.x + 6, 12))
	canvas.draw_rect(rect, Color(0, 0, 0, 0.38))
	canvas.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(color.r, color.g, color.b, 0.95))


func _draw_target_arc(canvas: Control, angle: float, width: float, beat: float, color: Color, thickness: float, alpha: float = 1.0) -> void:
	thickness *= _note_scale()
	var points := _arc_points(angle, width, beat, 36)
	if points.size() < 2:
		return
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.22 * alpha), thickness, false)
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.88 * alpha), 2.0, false)


func _arc_points(angle: float, width: float, beat: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_width := clampf(width, 0.1, 360.0)
	var count := maxi(steps, 4)
	for i in count + 1:
		var a := angle - safe_width * 0.5 + safe_width * float(i) / float(count)
		var p := project_u(fposmod(a, 360.0) / 360.0, beat)
		if _valid_point(p):
			points.append(p)
	return points


func _draw_marker(canvas: Control, point: Vector2, color: Color, radius: float) -> void:
	if not _valid_point(point):
		return
	var center := project_design(Vector2.ZERO)
	canvas.draw_line(center, point, Color(color.r, color.g, color.b, 0.16), 2.0, false)
	canvas.draw_circle(point, radius, color)
	canvas.draw_circle(point, maxf(2.0, radius * 0.35), UITheme.INK)


func _draw_diamond(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	if not _valid_point(point):
		return
	var points := PackedVector2Array([
		point + Vector2(0, -radius),
		point + Vector2(radius, 0),
		point + Vector2(0, radius),
		point + Vector2(-radius, 0),
	])
	points.append(points[0])
	canvas.draw_polyline(points, Color(0, 0, 0, 0.66), 5.0, false)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.94), 3.0, false)
	canvas.draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], points[3]]), Color(color.r, color.g, color.b, 0.32))
	canvas.draw_polyline(points, color, 1.7, false)
	canvas.draw_circle(point, maxf(2.0, radius * 0.26), Color(0, 0, 0, 0.68))
	canvas.draw_circle(point, maxf(1.2, radius * 0.14), Color(1, 1, 1, 0.92))


## 金键：环上一段白描边金键（圆头 + 金色核心）。所有 Bell 都在判定环上。
## 长度走 Note.bell_width()，和 Tap 到环时的 31° 同级；不再是一条长 45° 的金板。
func _draw_bell(canvas: Control, chart: Chart, note: Note, t: float) -> void:
	var q := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, _approach(chart, note.beat, t))
	var half := BELL_BAND_HALF * _note_scale() * float(_skin()["scale"])
	var breathe := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * 2.4)
	# 和 Tap / Hold 同一套语言：白色外壳 + 彩色核心，两端圆头。
	_bell_capsule(canvas, note, t, q, -half - 5.0, half + 5.0,
		Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.07 + 0.05 * breathe))
	_bell_capsule(canvas, note, t, q, -half - 2.0, half + 2.0, Color(0, 0, 0, 0.55))
	_bell_capsule(canvas, note, t, q, -half, half, Color(1, 1, 1, 0.94))
	_bell_capsule(canvas, note, t, q, -half * 0.62, half * 0.62, UITheme.KEY_YELLOW)
	# 扫键串的铃判定放宽到 75px，就把这个范围画出来：看到多大 = 能打多大。
	if bool(path_judgement_states.get(note.id, {}).get("sweep_chain", false)):
		var halo := _bell_ring_point(chart, note.center_u * 360.0, t, q)
		if halo.is_finite():
			canvas.draw_arc(halo, BELL_CHAIN_TOLERANCE * _note_scale(), 0.0, TAU, 64,
				Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.2), 1.6, true)


## 弧带 + 两端圆头：画成一根沿环的胶囊。
func _bell_capsule(canvas: Control, note: Note, beat: float, q: float, lo: float, hi: float, color: Color) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var poly := _bell_shape(note, beat, q, lo, hi)
	if poly.size() >= 3:
		canvas.draw_colored_polygon(poly, color)
	var ring := maxf(_ring_radius_px(beat), 1.0)
	var mid := maxf(0.0, (1.0 + (lo + hi) * 0.5 / ring) * q)
	var width := note.bell_width()
	var cap := absf(hi - lo) * 0.5
	for a in [note.center_u * 360.0 - width * 0.5, note.center_u * 360.0 + width * 0.5]:
		var p := _bell_ring_point(chart, a, beat, mid)
		if p.is_finite():
			canvas.draw_circle(p, cap, color)


## 金键的形状：两条同心弧。lo/hi 是相对判定环的像素偏移，圆头由 _bell_capsule 补。
func _bell_shape(note: Note, beat: float, q: float, lo: float, hi: float) -> PackedVector2Array:
	var chart := get_chart()
	var out := PackedVector2Array()
	if chart == null:
		return out
	var ring := maxf(_ring_radius_px(beat), 1.0)
	var width := note.bell_width()
	var steps := clampi(int(width / 4.0), 10, 96)
	var a0 := note.center_u * 360.0 - width * 0.5
	var a1 := note.center_u * 360.0 + width * 0.5
	var hi_scale := maxf(0.0, (1.0 + hi / ring) * q)
	var lo_scale := maxf(0.0, (1.0 + lo / ring) * q)
	for i in steps + 1:
		var p := _bell_ring_point(chart, a0 + width * float(i) / float(steps), beat, hi_scale)
		if p.is_finite():
			out.append(p)
	for i in steps + 1:
		var p := _bell_ring_point(chart, a1 - width * float(i) / float(steps), beat, lo_scale)
		if p.is_finite():
			out.append(p)
	return out


func _bell_ring_point(chart: Chart, angle_deg: float, beat: float, scale: float) -> Vector2:
	var data := _boundary_point(chart, fposmod(angle_deg, 360.0) / 360.0, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * clampf(scale, 0.0, 4.0))


func _ring_radius_px(beat: float) -> float:
	var center := project_design(Vector2.ZERO)
	var ring := 0.0
	for u in [0.0, 0.25, 0.5, 0.75]:
		var edge := project_u(u, beat)
		if _valid_point(edge):
			ring = maxf(ring, center.distance_to(edge))
	return ring


## 金色弧带的屏幕折线（radius_scale 用于从圆心长出来的接近动画）。
func bell_band_points(note: Note, beat: float, radius_scale: float = 1.0) -> Array[Vector2]:
	var chart := get_chart()
	var points: Array[Vector2] = []
	if chart == null:
		return points
	var width := note.bell_width()
	var steps := clampi(int(width / 4.0), 10, 96)
	var radius := clampf(radius_scale, 0.0, 1.0)
	for i in steps + 1:
		var angle := note.center_u * 360.0 - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, beat)
		if bool(data.get("gap", false)):
			continue
		var p := project_design((data.point as Vector2) * radius)
		if _valid_point(p):
			points.append(p)
	return points


## 在场判定：贴住画出来的位置算（Bell 到达前从圆心飞向环）；提前站在判定环上也算。
func bell_contains(note: Note, beat: float, point: Vector2, tolerance := BELL_RADIAL_TOLERANCE) -> bool:
	var live := bell_live_band(note, beat)
	if live.size() >= 2 and JudgeMath.trace_distance(point, live) <= tolerance:
		return true
	var ring := bell_band_points(note, beat)
	return ring.size() >= 2 and JudgeMath.trace_distance(point, ring) <= tolerance


## 扫过判定：这一帧光标走过的线段碰到金键带（或判定环）就算在场。
## 快速扫过时采样点可能整帧跨过金键，只看点会漏判整条路线上的铃。
func bell_swept_contains(note: Note, beat: float, from: Vector2, to: Vector2, tolerance := BELL_RADIAL_TOLERANCE) -> bool:
	if from.distance_to(to) < 0.5:
		return bell_contains(note, beat, to, tolerance)
	if _segment_near_band(bell_live_band(note, beat), from, to, tolerance):
		return true
	return _segment_near_band(bell_band_points(note, beat), from, to, tolerance)


func _segment_near_band(band: Array[Vector2], from: Vector2, to: Vector2, tolerance := BELL_RADIAL_TOLERANCE) -> bool:
	for i in band.size() - 1:
		var a := band[i]
		var b := band[i + 1]
		if not a.is_finite() or not b.is_finite():
			continue
		var pair := Geometry2D.get_closest_points_between_segments(a, b, from, to)
		if pair.size() >= 2 and pair[0].distance_to(pair[1]) <= tolerance:
			return true
	return false


## 金键的屏幕形态：外圈取弧带中点，圆心取圆心金点。
func bell_screen(note: Note, beat: float) -> Dictionary:
	var points := bell_live_band(note, beat)
	if points.size() < 2:
		return {}
	return {"center": points[points.size() / 2], "radius": BELL_BAND_HALF}


## 和 _draw_bell 同一套飞入几何：判定与特效都跟着可见位置走。
func bell_live_band(note: Note, beat: float) -> Array[Vector2]:
	var chart := get_chart()
	var empty: Array[Vector2] = []
	if chart == null:
		return empty
	var grow := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, _approach(chart, note.beat, beat))
	return bell_band_points(note, beat, grow)


## 判定用：判定时刻（beat）环上条带的屏幕折线，宽度为角度 width。
func note_band_points(angle_deg: float, width_deg: float, beat: float, scale: float = 1.0) -> PackedVector2Array:
	var chart := get_chart()
	var points := PackedVector2Array()
	if chart == null:
		return points
	var width := maxf(0.0, width_deg)
	if width <= 0.05:
		var data := _boundary_point(chart, fposmod(angle_deg, 360.0) / 360.0, beat)
		if not bool(data.get("gap", false)):
			var p := project_design((data.point as Vector2) * scale)
			if _valid_point(p):
				points.append(p)
		return points
	var steps := clampi(int(width / 3.0), 6, 48)
	for i in steps + 1:
		var a := angle_deg - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(a, 360.0) / 360.0, beat)
		if bool(data.get("gap", false)):
			continue
		var p := project_design((data.point as Vector2) * scale)
		if _valid_point(p):
			points.append(p)
	return points


## 判定用：音符此刻画在屏幕上的条带（含飞入半径），和绘制走同一套几何。
func note_live_band(note: Note, beat: float, pad: float = 0.0) -> PackedVector2Array:
	var chart := get_chart()
	if chart == null:
		return PackedVector2Array()
	var pre := _pre_read_beats(chart, beat)
	var progress := _approach(chart, note.beat, beat)
	var grow := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress)
	return note_band_points(note.angle, note.arc_width() + pad, beat, grow)


## 鼠标在环平面上的角度（度），用于密集流的扇区判定。
func screen_angle_deg(screen: Vector2) -> float:
	var design := _screen_to_ring_plane(screen)
	if not design.is_finite() or design.x > 1.0e9:
		return NAN
	return fposmod(rad_to_deg(atan2(design.y, design.x)), 360.0)


## 音符头部此刻的屏幕位置（和绘制一样从环心飞入）：Anchor 与 Path 头共用。
func note_head_screen(note: Note, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	return _flying_position(chart, note.angle, note.beat, beat, _star_fall_beats(chart, beat))


## 音符图形自身的屏幕半径（位置判定容差用）。
func note_graphic_radius(kind: String) -> float:
	var ns := _note_scale() * float(_skin()["scale"])
	if kind == "anchor":
		return 16.0 * ns
	return 9.0 * ns


func _design_radius_to_screen(point: Vector2, radius: float) -> float:
	var p1 := project_design(point)
	var p2 := project_design(Vector2(point.x + radius, point.y))
	if not _valid_point(p1) or not _valid_point(p2):
		return radius
	return p1.distance_to(p2)


## 以“毫秒预读”为准的取音符窗口。
## 变 BPM 时同一个预读在拍号上会变宽/变窄，按拍号取窗口会让音符提前进/提前出；
## 这里先把 t±pre_ms 换成拍号，窗口在时间上永远是同一个长度。
func _notes_around(chart: Chart, t: float, back: float = 0.0, ahead: float = 0.0) -> Array[Note]:
	var pre_ms := _pre_read_ms(chart)
	var t_ms := chart.timing.beat_to_chart_ms(t)
	var from_beat := chart.timing.chart_ms_to_beat(t_ms - pre_ms) - back
	var to_beat := chart.timing.chart_ms_to_beat(t_ms + pre_ms) + ahead
	return _notes_in_range(chart, from_beat, to_beat)


func _notes_in_range(chart: Chart, from_beat: float, to_beat: float) -> Array[Note]:
	if _sorted_notes_chart != chart or _sorted_notes_cache.size() != chart.notes.size():
		_sorted_notes_chart = chart
		_sorted_notes_cache = chart.notes.duplicate()
		_sorted_notes_cache.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	var low := 0
	var high := _sorted_notes_cache.size()
	while low < high:
		var mid := (low + high) / 2
		if _sorted_notes_cache[mid].beat < from_beat:
			low = mid + 1
		else:
			high = mid
	var result: Array[Note] = []
	for i in range(low, _sorted_notes_cache.size()):
		if _sorted_notes_cache[i].beat > to_beat:
			break
		result.append(_sorted_notes_cache[i])
	return result


func _note_scale() -> float:
	# 以 330px 设计半径为 1.0；编辑器小预览和试玩大环保持相同相对大小。
	var base := _avg_radius_cache
	if base < 40.0:
		base = 300.0
	return clampf(base / 330.0, 0.55, 1.7)


func _valid_point(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x < 1.0e9 and point.y < 1.0e9
