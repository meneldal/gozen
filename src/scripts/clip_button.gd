extends Button

const WAVE_RECT_PATH: String = "res://objects/audio_wave_texture_rect.tscn"

@onready var parent: Control = get_parent()

var is_dragging: bool = false
var is_resizing_left: bool = false
var is_resizing_right: bool = false

var max_left_resize: int = 0 # Minimum frame
var max_right_resize: int = 0 # Maximum frame
var start_frame: int = 0
var duration: int = 0

var wave_texture_rect: TextureRect = null



func _ready() -> void:
	var l_data: ClipData = get_clip_data()

	_add_resize_button(PRESET_LEFT_WIDE, true)
	_add_resize_button(PRESET_RIGHT_WIDE, false)

	@warning_ignore("standalone_expression") [
		button_down.connect(_on_button_down),
		gui_input.connect(_on_gui_input),
		Timeline.instance._on_zoom_changed.connect(_update_wave)]

	if l_data.type in View.AUDIO_TYPES:
		clip_children = CLIP_CHILDREN_AND_DRAW

		wave_texture_rect = preload(WAVE_RECT_PATH).instantiate()
		wave_texture_rect.position.x = -(Timeline.get_frame_pos(l_data.begin))
		wave_texture_rect.texture = get_file_data().wave

		add_child(wave_texture_rect)
		await RenderingServer.frame_pre_draw
		_update_wave()


func _process(_delta: float) -> void:
	if is_resizing_left or is_resizing_right:
		var l_new_frame: int = Timeline.get_frame_id(
				parent.get_local_mouse_position().x)

		# Making certain we stay in bounds
		l_new_frame = max(l_new_frame, max_left_resize)
		if max_right_resize != -1:
			l_new_frame = min(l_new_frame, max_right_resize)

		# Updating the clip
		if is_resizing_right:
			size.x = Timeline.get_frame_pos(l_new_frame - start_frame)
			_update_wave()
		elif is_resizing_left:
			position.x = Timeline.get_frame_pos(l_new_frame)
			size.x = Timeline.get_frame_pos(duration - (l_new_frame - start_frame))
			_update_wave(get_clip_data().begin + (l_new_frame - start_frame))


func _on_button_down() -> void:
	is_dragging = true
	get_viewport().set_input_as_handled()	


func _input(a_event: InputEvent) -> void:
	# TODO: Make it so only selected clips can be cut
	# Timeline.selected_clips
	if a_event.is_action_pressed("clip_split"):
		var l_data: ClipData = get_clip_data()
		# Check if playhead is inside of clip, else we skip creating undo and
		# redo entries.
		if View.frame_nr <= l_data.start_frame or View.frame_nr >= l_data.end_frame:
			return # Playhead is left/right of the clip

		Project.undo_redo.create_action("Deleting clip on timeline")

		Project.undo_redo.add_do_method(_cut_clip.bind(View.frame_nr, l_data))
		Project.undo_redo.add_do_method(View._update_frame)
		Project.undo_redo.add_do_method(_update_wave)

		Project.undo_redo.add_undo_method(_uncut_clip.bind(View.frame_nr, l_data))
		Project.undo_redo.add_undo_method(View._update_frame)
		Project.undo_redo.add_undo_method(_update_wave)

		Project.undo_redo.commit_action()


func _on_gui_input(a_event: InputEvent) -> void:
	# We need mouse passthrough to allow for clip dragging without issues
	# But when clicking on clips we do not want the playhead to keep jumping.
	# Maybe later on we can allow for clip clicking and playhead moving by
	# holding alt or something.
	if a_event is InputEventMouseButton:
		var l_event: InputEventMouseButton = a_event

		if l_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		if !(l_event as InputEventWithModifiers).alt_pressed and l_event.is_pressed():
			EffectsPanel.instance.open_clip_effects(name.to_int())
			get_viewport().set_input_as_handled()

	if a_event.is_action_pressed("delete_clip"):
		Project.undo_redo.create_action("Deleting clip on timeline")

		Project.undo_redo.add_do_method(Timeline.instance.delete_clip.bind(
				get_clip_data().start_frame))

		Project.undo_redo.add_undo_method(Timeline.instance.undelete_clip.bind(
				get_clip_data()))

		Project.undo_redo.add_do_method(View._update_frame)
		Project.undo_redo.add_undo_method(View._update_frame)
		Project.undo_redo.commit_action()


func _get_drag_data(_pos: Vector2) -> Draggable:
	if is_resizing_left or is_resizing_right:
		return null

	var l_draggable: Draggable = Draggable.new()
	var l_data: ClipData = get_clip_data()

	# Add clip id to array
	if l_draggable.ids.append(name.to_int()):
		printerr("Something went wrong appending to draggable ids!")

	l_draggable.files = false
	l_draggable.duration = get_clip_data().duration
	l_draggable.offset = int(get_local_mouse_position().x / Timeline.get_zoom())

	l_draggable.ignores.append(Vector2i(l_data.track, l_data.start_frame))
	l_draggable.clip_buttons.append(self)

	modulate = Color(1, 1, 1, 0.1)
	return l_draggable


func _notification(a_notification_type: int) -> void:
	match a_notification_type:
		NOTIFICATION_DRAG_END:
			is_dragging = false
			modulate = Color(1, 1, 1, 1)


func _add_resize_button(a_preset: LayoutPreset, a_left: bool) -> void:
	var l_button: Button = Button.new()
	add_child(l_button)

	l_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	l_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	l_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	l_button.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	l_button.set_anchors_and_offsets_preset(a_preset)
	l_button.custom_minimum_size.x = 3
	if !a_left:
		l_button.position.x -= 3
	l_button.mouse_filter = Control.MOUSE_FILTER_PASS

	if l_button.button_down.connect(_on_resize_engaged.bind(a_left)):
		printerr("Couldn't connect button_down to _on_resize_engaged!")
	if l_button.button_up.connect(_on_commit_resize):
		printerr("Couldn't connect button_down to _on_resize_engaged!")


func _on_resize_engaged(a_left: bool) -> void:
	var l_data: ClipData = get_clip_data()
	var l_previous: int = -1

	start_frame = l_data.start_frame
	duration = l_data.duration
	max_left_resize = 0

	# First calculate spacing left of handle to other clips
	if a_left:
		for i: int in Project.tracks[l_data.track]:
			if i >= l_data.start_frame:
				break
			l_previous = max(0, i - 1)

		if l_previous != -1:
			max_left_resize = l_data.duration + l_previous
		max_right_resize = l_data.end_frame
	else:
		for i: int in Project.tracks[l_data.track]:
			if i > l_data.start_frame:
				l_previous = i
				break

		max_left_resize = l_data.start_frame + 1
		max_right_resize = maxi(l_previous, -1)

	# Check if audio/video how much space is left to extend, take minimum
	if get_clip_data().type in [File.TYPE.VIDEO, File.TYPE.AUDIO]:
		if a_left:
			max_left_resize = max(max_left_resize,
					get_clip_data().start_frame - get_clip_data().begin)
		else:
			var l_duration_left: int = get_file().duration

			l_duration_left -= get_clip_data().begin
			l_duration_left += get_clip_data().start_frame

			if max_right_resize == -1:
				max_right_resize = l_duration_left
			else:
				max_right_resize = min(max_right_resize, l_duration_left)
				
	is_resizing_left = a_left
	is_resizing_right = !a_left
	get_viewport().set_input_as_handled()


func _on_commit_resize() -> void:
	is_resizing_left = false
	is_resizing_right = false

	Project.undo_redo.create_action("Resizing clip on timeline")

	Project.undo_redo.add_do_method(_set_resize_data.bind(
			Timeline.get_frame_id(position.x),
			Timeline.get_frame_id(size.x)))
	Project.undo_redo.add_do_method(View._update_frame)
	Project.undo_redo.add_do_method(_update_wave)

	Project.undo_redo.add_undo_method(_set_resize_data.bind(
			get_clip_data().start_frame, get_clip_data().duration))
	Project.undo_redo.add_undo_method(View._update_frame)
	Project.undo_redo.add_undo_method(_update_wave)

	Project.undo_redo.commit_action()


func _set_resize_data(a_new_start: int, a_new_duration: int) -> void:
	var l_data: ClipData = get_clip_data()

	if l_data.start_frame != a_new_start:
		l_data.begin += a_new_start - l_data.start_frame

	position.x = a_new_start * Timeline.get_zoom()
	size.x = a_new_duration * Timeline.get_zoom()

	if !Project.tracks[l_data.track].erase(l_data.start_frame):
		printerr("Could not erase from tracks!")
	Project.tracks[l_data.track][a_new_start] = name.to_int()

	l_data.start_frame = a_new_start
	l_data.duration = a_new_duration
	l_data.update_audio_data()

	Timeline.instance.update_end()


func _cut_clip(a_playhead: int, a_clip_data: ClipData) -> void:
	var l_new_clip: ClipData = ClipData.new()
	var l_frame: int = a_playhead - a_clip_data.start_frame

	l_new_clip.id = Utils.get_unique_id(Project.clips.keys())
	l_new_clip.file_id = a_clip_data.file_id
	l_new_clip.type = a_clip_data.type

	l_new_clip.start_frame = a_playhead
	l_new_clip.duration = abs(a_clip_data.duration - l_frame)
	l_new_clip.begin = a_clip_data.begin + l_frame
	l_new_clip.track = a_clip_data.track

	a_clip_data.duration -= l_new_clip.duration - 1
	size.x = a_clip_data.duration * Timeline.get_zoom()

	Project.clips[l_new_clip.id] = l_new_clip
	Project.tracks[l_new_clip.track][l_new_clip.start_frame] = l_new_clip.id

	a_clip_data.update_audio_data()
	l_new_clip.update_audio_data()
	Timeline.instance.add_clip(l_new_clip)


func _uncut_clip(a_playhead: int, a_current_clip: ClipData) -> void:
	var l_track: int = Timeline.get_track_id(position.y)
	var l_split_clip: ClipData = Project.clips[Project.tracks[l_track][a_playhead]]

	a_current_clip.duration += l_split_clip.duration
	size.x = Timeline.get_frame_pos(a_current_clip.duration)

	Timeline.instance.delete_clip(l_track, a_playhead)
	a_current_clip.update_audio_data()


func get_clip_data() -> ClipData:
	return Project.clips[name.to_int()]


func get_file() -> File:
	return Project.files[get_clip_data().file_id]


func get_file_data() -> FileData:
	return Project._files_data[get_clip_data().file_id]


func _update_wave(a_begin: int = get_clip_data().begin) -> void:
	if wave_texture_rect != null:
		wave_texture_rect.position.x = -(a_begin * Timeline.get_zoom())
		wave_texture_rect.size.x = wave_texture_rect.texture.\
				get_image().get_size().x * Timeline.get_zoom()

