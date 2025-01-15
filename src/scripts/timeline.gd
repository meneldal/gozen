class_name Timeline extends PanelContainer

signal _on_zoom_changed


const TRACK_HEIGHT: int = 30
const LINE_HEIGHT: int = 4

const STYLE_BOXES: Dictionary = {
    File.TYPE.IMAGE: preload("res://styles/style_box_image.tres"),
    File.TYPE.AUDIO: preload("res://styles/style_box_audio.tres"),
    File.TYPE.VIDEO: preload("res://styles/style_box_video.tres")
}


static var instance: Timeline
static var playhead_moving: bool = false
static var selected_clips: Array[int] = [] # An array of all selected clip id's

@export var scroll: ScrollContainer
@export var main: Control
@export var clips: Control
@export var preview: Control
@export var playhead: Panel


var playback_before_moving: bool = false
var zoom: float = 1.0 : set = _set_zoom # How many pixels 1 frame takes

var _offset: int = 0 # Offset for moving/placing clips



func _ready() -> void:
	instance = self

	@warning_ignore("standalone_expression")[
		View._on_frame_nr_changed.connect(move_playhead),
		mouse_exited.connect(func() -> void: preview.visible = false)]


func _process(_delta: float) -> void:
	if playhead_moving:
		var l_new_frame: int = clampi(
				floori(main.get_local_mouse_position().x / zoom),
				0, Project.timeline_end)
		if l_new_frame != View.frame_nr:
			View._set_frame(l_new_frame, true)


func _input(a_event: InputEvent) -> void:
	if a_event.is_action_pressed("timeline_zoom_in"):
		zoom += 0.06 if zoom < 1 else 0.2
		get_viewport().set_input_as_handled()
	elif a_event.is_action_pressed("timeline_zoom_out"):
		zoom -= 0.06 if zoom < 1 else 0.2
		get_viewport().set_input_as_handled()


func _on_main_gui_input(a_event: InputEvent) -> void:
	if a_event is not InputEventMouseButton:
		return

	if (a_event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if a_event.is_pressed():
			playhead_moving = true
			playback_before_moving = View.is_playing

			if playback_before_moving:
				View._on_play_button_pressed()
		elif a_event.is_released():
			playhead_moving = false

			if playback_before_moving:
				View._on_play_button_pressed()


func _set_zoom(a_new_zoom: float) -> void:
	var l_prev_mouse: int = round(main.get_local_mouse_position().x / zoom)

	zoom = clampf(a_new_zoom, 0.2, 10.0)
	move_playhead()

	# Get all clips, update their size and position
	for l_clip_button: Button in clips.get_children():
		var l_data: ClipData = Project.clips[l_clip_button.name.to_int()]

		l_clip_button.position.x = l_data.start_frame * zoom
		l_clip_button.size.x = l_data.duration * zoom
		l_clip_button.call("_update_wave")

	update_end()
	var l_now_mouse: int = round(main.get_local_mouse_position().x / zoom)

	scroll.scroll_horizontal += round((l_prev_mouse - l_now_mouse) * zoom)
	_on_zoom_changed.emit()


func move_playhead() -> void:
	playhead.position.x = zoom * View.frame_nr


func _can_drop_data(_pos: Vector2, a_data: Variant) -> bool:
	var l_data: Draggable = a_data
	var l_pos: Vector2 = main.get_local_mouse_position()

	# Clear previous preview just in case
	for l_child: Node in preview.get_children():
		l_child.queue_free()

	if l_data.files:
		preview.visible = _can_drop_new_clips(l_pos, l_data)
	else:
		preview.visible = _can_move_clips(l_pos, l_data)

	# Set previews for new clip positions
	return preview.visible


func _can_drop_new_clips(a_pos: Vector2, a_draggable: Draggable) -> bool:
	var l_track: int = clampi(get_track_id(a_pos.y), 0, Project.tracks.size() - 1)
	var l_frame: int = maxi(int(a_pos.x / zoom) - a_draggable.offset, 0)
	var l_region: Vector2i = get_drop_region(l_track, l_frame, a_draggable.ignores)

	var l_end: int = l_frame
	var l_duration: int = 0
	_offset = 0

	# Calculate total duration of all clips together
	for l_file_id: int in a_draggable.ids:
		l_duration += Project.files[l_file_id].duration
	l_end = l_frame + l_duration

	# Create a preview
	var l_panel: PanelContainer = PanelContainer.new()

	l_panel.size = Vector2(get_frame_pos(l_duration), TRACK_HEIGHT)
	l_panel.position = Vector2(get_frame_pos(l_frame), get_track_pos(l_track))
	l_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_panel.add_theme_stylebox_override("panel",
			preload("res://styles/style_box_new_clip.tres") )

	preview.add_child(l_panel)

	# Check if highest
	if l_region.x < l_frame and l_region.y == -1:
		return true

	# Check if clips fits
	if l_region.x < l_frame and l_end < l_region.y:
		return true
	if l_duration > l_region.y - l_region.x:
		if l_region.x != -1 and l_region.y != -1:
			return false

	# Check if overlapping works
	if l_frame <= l_region.x:
		_offset = l_region.x - l_frame

		if l_frame + _offset < l_region.y or l_region.y == -1:
			l_panel.position.x += _offset
			return true
	elif l_end >= l_region.y:
		_offset = l_region.y - l_end

		if l_frame - _offset > l_region.x and l_frame + _offset >= 0:
			l_panel.position.x += _offset
			return true

	preview.remove_child(l_panel)
	return false


func _can_move_clips(a_pos: Vector2, a_draggable: Draggable) -> bool:
	var l_first_clip: ClipData = a_draggable.get_clip_data(0)
	var l_track: int = clampi(get_track_id(a_pos.y), 0, Project.tracks.size() - 1)
	var l_frame: int = maxi(int(a_pos.x / zoom) - a_draggable.offset, 0)

	# Calculate differences of track + frame based on first clip
	a_draggable.differences.y = l_track - l_first_clip.track
	a_draggable.differences.x = l_frame - l_first_clip.start_frame

	# Initial boundary check (Track only)
	for l_id: int in a_draggable.ids:
		if !Utils.in_range(
				Project.clips[l_id].track + a_draggable.differences.y as int,
				0, Project.tracks.size()):
			return false

	# Initial region for first clip
	var l_first_new_track: int = l_first_clip.track + a_draggable.differences.y
	var l_first_new_frame: int = l_first_clip.start_frame + a_draggable.differences.x
	var l_region: Vector2i = get_drop_region(
			l_first_new_track, l_first_new_frame, a_draggable.ignores)

	# Calculate possible offsets
	var l_offset_range: Vector2i = Vector2i.ZERO

	if l_region.x != -1 and l_first_new_frame <= l_region.x:
		l_offset_range.x = l_region.x - l_first_new_frame
	if l_region.y != -1 and l_first_new_frame + l_first_clip.duration >= l_region.y:
		l_offset_range.y = l_region.y - (l_first_new_frame + l_first_clip.duration)

	# Check all other clips
	for i: int in range(1, a_draggable.ids.size()):
		var l_clip: ClipData = a_draggable.get_clip_data(i)
		var l_new_track: int = l_clip.track + a_draggable.differences.y
		var l_new_frame: int = l_clip.start_frame + a_draggable.differences.x
		var l_clip_offsets: Vector2i = Vector2i.ZERO
		var l_clip_region: Vector2i = get_drop_region(
				l_new_track, l_new_frame, a_draggable.ignores)

		# Calculate possible offsets for clip
		if l_clip_region.x != -1 and l_new_frame <= l_clip_region.x:
			l_clip_offsets.x = l_clip_region.x - l_new_frame
		if l_clip_region.y != -1 and l_new_frame + l_clip.duration >= l_clip_region.y:
			l_clip_offsets.y = l_clip_region.y - (l_new_frame + l_clip.duration)

		# Update offset range based on clip offsets
		l_offset_range.x = maxi(l_offset_range.x, l_clip_offsets.x)
		l_offset_range.y = mini(l_offset_range.y, l_clip_offsets.y)

		if l_offset_range.x > l_offset_range.y:
			return false

	# Set final offset
	if l_offset_range.x > 0:
		_offset = l_offset_range.x
	elif l_offset_range.y < 0:
		_offset = l_offset_range.y
	else:
		_offset = 0

	# 0 frame check
	if l_first_new_frame + _offset < 0:
		return false

	# Create preview
	for l_node: Node in preview.get_children():
		preview.remove_child(l_node)

	var l_main_control: Control = Control.new()

	l_main_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_main_control.position.x = get_frame_pos(a_draggable.differences.x + _offset)
	l_main_control.position.y = get_track_pos(a_draggable.differences.y)
	preview.add_child(l_main_control)

	for l_button: Button in a_draggable.clip_buttons:
		var l_new_button: Button = Button.new()

		l_new_button.size = l_button.size
		l_new_button.position = l_button.position
		l_new_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l_new_button.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		l_new_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# NOTE: Modulate alpha does not work when texture has alpha layers :/
		#		l_new_button.modulate = Color(255,255,255,130)
		l_new_button.modulate = Color(240,240,240)

		if l_button.get_child_count() >= 3:
			l_new_button.add_child(l_button.get_child(2).duplicate()) # Wave Texture rect
			@warning_ignore("unsafe_property_access")

		l_main_control.add_child(l_new_button)

	return true


func _drop_data(_pos: Vector2, a_data: Variant) -> void:
	var l_draggable: Draggable = a_data
	preview.visible = false

	if l_draggable.files:
		_handle_drop_new_clips(l_draggable)
	else:
		_handle_drop_existing_clips(l_draggable)

	Project.undo_redo.add_do_method(View._update_frame)
	Project.undo_redo.add_do_method(update_end)

	Project.undo_redo.add_undo_method(View._update_frame)
	Project.undo_redo.add_undo_method(update_end)

	Project.undo_redo.commit_action()


func _handle_drop_new_clips(l_draggable: Draggable) -> void:
	Project.undo_redo.create_action("Adding new clips to timeline")

	var l_pos: Vector2 = main.get_local_mouse_position()
	var l_ids: Array = []
	var l_track: int = get_track_id(l_pos.y)
	var l_start_frame: int = maxi(
			get_frame_id(l_pos.x) - l_draggable.offset + _offset, 0)

	for l_id: int in l_draggable.ids:
		var l_new_clip_data: ClipData = ClipData.new()

		l_new_clip_data.id = Utils.get_unique_id(Project.clips.keys())
		l_new_clip_data.file_id = l_id
		l_new_clip_data.type = Project.files[l_id].type
		l_new_clip_data.start_frame = l_start_frame
		l_new_clip_data.track = l_track
		l_new_clip_data.duration = Project.files[l_id].duration
		l_new_clip_data.update_audio_data()

		l_ids.append(l_new_clip_data.id)
		l_draggable.new_clips.append(l_new_clip_data)
		l_start_frame += l_new_clip_data.duration

	l_draggable.ids = l_ids

	Project.undo_redo.add_do_method(_add_new_clips.bind(l_draggable))
	Project.undo_redo.add_undo_method(_remove_new_clips.bind(l_draggable))


func _handle_drop_existing_clips(l_draggable: Draggable) -> void:
	Project.undo_redo.create_action("Moving clips on timeline")

	Project.undo_redo.add_do_method(_move_clips.bind(
			l_draggable,
			l_draggable.differences.y,
			l_draggable.differences.x + _offset))
	Project.undo_redo.add_undo_method(_move_clips.bind(
			l_draggable,
			-l_draggable.differences.y,
			-(l_draggable.differences.x + _offset)))


func _move_clips(a_data: Draggable, a_track_diff: int, a_frame_diff: int) -> void:
	# Go over each clip to update its data
	for i: int in a_data.ids.size():
		var l_data: ClipData = Project.clips[a_data.ids[i]]
		var l_track: int = l_data.track + a_track_diff
		var l_frame: int = l_data.start_frame + a_frame_diff

		# Change data in tracks
		if !Project.tracks[l_data.track].erase(l_data.start_frame):
			printerr("Could not erase ", a_data.ids[i], " from tracks!")

		# Change clip data
		l_data.track = l_track
		l_data.start_frame = l_frame
		Project.tracks[l_track][l_frame] = a_data.ids[i]

		# Change clip button position
		a_data.clip_buttons[i].position = Vector2(
				get_frame_pos(l_frame), get_track_pos(l_track))


func _add_new_clips(a_draggable: Draggable) -> void:
	for l_clip_data: ClipData in a_draggable.new_clips:
		Project.clips[l_clip_data.id] = l_clip_data
		Project.tracks[l_clip_data.track][l_clip_data.start_frame] = l_clip_data.id

		add_clip(l_clip_data)


func _remove_new_clips(a_draggable: Draggable) -> void:
	for l_clip_data: ClipData in a_draggable.new_clips:
		if !Project.clips.erase(l_clip_data.id):
			printerr("Couldn't erase new clips from clips!")
		if !Project.tracks[l_clip_data.track].erase(l_clip_data.start_frame):
			printerr("Couldn't erase new clips from tracks!")

		remove_clip(l_clip_data.id)


func add_clip(a_clip_data: ClipData) -> void:
	var l_button: Button = Button.new()
	var l_style_box: StyleBoxFlat = STYLE_BOXES[a_clip_data.type]

	l_button.clip_text = true
	l_button.name = str(a_clip_data.id)
	l_button.text = " " + Project.files[a_clip_data.file_id].nickname
	l_button.size.x = zoom * a_clip_data.duration
	l_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	l_button.position.x = zoom * a_clip_data.start_frame
	l_button.position.y = a_clip_data.track * (LINE_HEIGHT + TRACK_HEIGHT)
	l_button.mouse_filter = Control.MOUSE_FILTER_PASS

	l_button.add_theme_stylebox_override("normal", l_style_box)
	l_button.add_theme_stylebox_override("focus", l_style_box)
	l_button.add_theme_stylebox_override("hover", l_style_box)
	l_button.add_theme_stylebox_override("pressed", l_style_box)

	l_button.set_script(preload("res://scripts/clip_button.gd"))

	clips.add_child(l_button)


func remove_clip(a_clip_id: int) -> void:
	clips.get_node(str(a_clip_id)).queue_free()


func show_preview(a_track_id: int, a_frame_nr: int, a_duration: int) -> bool:
	preview.position.y = a_track_id * (TRACK_HEIGHT + LINE_HEIGHT)
	preview.position.x = zoom * a_frame_nr
	preview.size.x = zoom * a_duration
	preview.visible = true

	return true


func get_drop_region(a_track: int, a_frame: int, a_ignores: Array[Vector2i]) -> Vector2i:
	# X = lowest, Y = highest
	var l_region: Vector2i = Vector2i(-1, -1)
	var l_keys: PackedInt64Array = Project.tracks[a_track].keys()
	l_keys.sort()

	for a_track_frame: int in l_keys:
		if a_track_frame < a_frame and Vector2i(a_track, a_track_frame) not in a_ignores:
			l_region.x = a_track_frame
		elif a_track_frame > a_frame and Vector2i(a_track, a_track_frame) not in a_ignores:
			l_region.y = a_track_frame
			break

	# Getting the correct end frame
	if l_region.x != -1:
		l_region.x = Project.clips[Project.tracks[a_track][l_region.x]].end_frame

	return l_region


func get_lowest_frame(a_track_id: int, a_frame_nr: int, a_ignore: Array[Vector2i]) -> int:
	var l_lowest: int = -1

	if a_track_id > Project.tracks.size() - 1:
		return -1

	for i: int in Project.tracks[a_track_id].keys():
		if i < a_frame_nr:
			if a_ignore.size() >= 1:
				if i == a_ignore[0].y and a_track_id == a_ignore[0].x:
					continue
			l_lowest = i
		elif i >= a_frame_nr:
			break

	if l_lowest == -1:
		return -1

	var l_clip: ClipData = Project.clips[Project.tracks[a_track_id][l_lowest]]
	return l_clip.duration + l_lowest


func get_highest_frame(a_track_id: int, a_frame_nr: int, a_ignore: Array[Vector2i]) -> int:
	for i: int in Project.tracks[a_track_id].keys():
		# TODO: Change the a_ignore when moving multiple clips
		if i > a_frame_nr:
			if a_ignore.size() >= 1:
				if i == a_ignore[0].y and a_track_id == a_ignore[0].x:
					continue
			return i

	return -1


func update_end() -> void:
	var l_new_end: int = 0

	for l_track: Dictionary in Project.tracks:
		if l_track.size() == 0:
			continue

		var l_clip: ClipData = Project.clips[l_track[l_track.keys().max()]]
		var l_value: int = l_clip.duration + l_clip.start_frame

		if l_new_end < l_value:
			l_new_end = l_value
	
	main.custom_minimum_size.x = (l_new_end + 1080) * zoom
	Project.timeline_end = l_new_end


func delete_clip(a_track_id: int, a_frame_nr: int) -> void:
	var l_id: int = Project.tracks[a_track_id][a_frame_nr]

	if !Project.clips.erase(l_id):
		printerr("Couldn't erase new clips from clips!")
	if !Project.tracks[a_track_id].erase(a_frame_nr):
		printerr("Couldn't erase new clips from tracks!")

	remove_clip(l_id)
	update_end()


func undelete_clip(a_clip_data: ClipData) -> void:
	Project.clips[a_clip_data.id] = a_clip_data
	Project.tracks[a_clip_data.track][a_clip_data.start_frame] = a_clip_data.id
	a_clip_data.update_audio_data()

	add_clip(a_clip_data)
	update_end()


static func get_zoom() -> float:
	return instance.zoom


static func get_frame_id(a_pos: float) -> int:
	return floor(a_pos / get_zoom())


static func get_track_id(a_pos: float) -> int:
	return floor(a_pos / (TRACK_HEIGHT + LINE_HEIGHT))


static func get_frame_pos(a_pos: float) -> float:
	return a_pos * get_zoom()


static func get_track_pos(a_pos: float) -> float:
	return a_pos * (TRACK_HEIGHT + LINE_HEIGHT)

