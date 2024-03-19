class_name EditorUI extends HBoxContainer
## Editor UI
## 
## Layouts get added with a name in this form: 
## 'layout_name-random number', the random number is between
## 10000,99999 to make certain that no layout of the same type gets the
## same name.
##
## Layout names can not contain '-' as this is used to split the name.
##
## Config:
## [general]
## - layouts_order: [layout_id, layout_id, ...]
## [custom_icons]
## - layout_id: icon path


# TODO: Add option menu to sidebar to add layout, move up/down,
#       add custom icon and delete layout (Right menu click)


static var instance: EditorUI

var sidebar_button_menu: PopupMenu

var config := ConfigFile.new()
var config_path: String = ProjectSettings.get_setting("globals/path/editor_ui")


func _ready() -> void:
	if instance != null:
		Printer.error("No 2 'EditorUI' screens are allowed!")
		self.queue_free()
		return
	instance = self
	
	if FileAccess.file_exists(config_path):
		config.load(config_path)
		var layout_order: PackedStringArray = config.get_value("general", "layouts_order", [])
		for id: String in layout_order:
			add_layout(id.split("-")[0], id)
	else:
		# Creating default layouts
		add_layout("file_manager")
		add_layout("default")
		add_layout("render_menu")
	
	# TODO: Save last used tab in project file or have option in settings to set default
	if %LayoutContainer.get_child_count() > 0:
		%LayoutContainer.current_tab = 1


func _input(event) -> void:
	## Shortcuts for changing the editor layout.
	# TODO: Make it possible to change these shortcuts
	for layout_id in range(1,10):
		if event.is_action_pressed("editor_layout_%s" % layout_id):
			change_layout(layout_id)
	if event.is_action_pressed("editor_layout_prev"):
		change_layout(clamp(%LayoutContainer.current_tab - 1, 1,9))
	if event.is_action_pressed("editor_layout_prev"):
		change_layout(clamp(%LayoutContainer.current_tab + 1, 1,9))


func change_layout(id: int) -> void:
	if id <= (%LayoutContainer.get_child_count() - 1):
		%LayoutContainer.current_tab = id


func add_layout(layout_name: String, id: String = "") -> void:
	# Check if single use only or if a layout can be used in multiple instances
	var layout_data: LayoutModule = load("res://_layout_modules/layout_%s/info.tres" % layout_name)
	if layout_data.single_only:
		if check_single_existing(layout_name):
			Printer.error("Module is single only, already in sidebar present!")
			return
	# Setting name for button and layout
	var button := Button.new()
	button.gui_input.connect(_on_sidebar_button_gui_event.bind(button))
	var layout: Node = layout_data.scene.instantiate()
	if id == "":
		var layout_id := "%s-%s" % [layout_name, randi_range(10000,99999)]
		var layout_order: PackedStringArray = config.get_value("general", "layouts_order", [])
		layout.name = layout_id
		button.name = layout_id
		button.icon = layout_data.default_icon
		
		# Updating the config file
		layout_order.append(layout_id)
		config.set_value("general", "layouts_order", layout_order)
		config.save(config_path)
	else:
		layout.name = id
		button.name = id
		if config.has_section_key("custom_icons", id):
			button.icon = config.get_value("custom_icons", id)
	
	# Setting button data
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2i(40,40)
	
	# Setting button function
	var tab_nr := %SidebarVBox.get_child_count()
	button.pressed.connect(func() -> void: 
		%LayoutContainer.current_tab = tab_nr)
	
	# Setting the button icon
	var icon_path: String = config.get_value("custom_icons", id, "")
	button.icon = layout_data.default_icon if icon_path == "" else load(icon_path)
	
	# Adding the nodes to the sidebar + tab container
	%SidebarVBox.add_child(button)
	%LayoutContainer.add_child(layout)


func check_single_existing(layout_name: String) -> bool:
	for child: Node in %SidebarVBox.get_children():
		if child.name.split("-")[0] == layout_name:
			return true
	return false


func _on_sidebar_gui_event(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.is_pressed():
			var menu := PopupMenu.new()
			menu.position = get_local_mouse_position()
			menu.add_item("Add new layout", 4)
			menu.id_pressed.connect(_on_sidebar_button_menu_pressed.bind(null))
			add_child(menu)
			menu.popup()
			menu.visibility_changed.connect(func():
				if !menu.visible:
					menu.queue_free())


func _on_sidebar_button_gui_event(event: InputEvent, button: Button) -> void:
	if not event is InputEventMouseButton or event.button_index == MOUSE_BUTTON_RIGHT:
		return
	if !event.is_pressed():
		return
	var menu := PopupMenu.new()
	menu.position = get_local_mouse_position() as Vector2i + menu.size / 2
	
	menu.add_item("Move up", 0)
	menu.add_item("Move down", 1)
	menu.add_separator()
	menu.add_item("Change icon", 2)
	menu.add_separator()
	menu.add_item("Remove layout", 3)
	menu.add_item("Add new layout", 4)
	
	menu.id_pressed.connect(_on_sidebar_button_menu_pressed.bind(button))
	menu.mouse_exited.connect(func(): menu.queue_free())
	
	add_child(menu)
	menu.popup()


func _on_sidebar_button_menu_pressed(id: int, button: Button) -> void:
	match id:
		0: # Move up
			_move_up(button.name)
		1: # Move down
			_move_down(button.name)
		2: # Change icon
			# TODO: Open popup to select new icon file
			# DialogManager
			#_set_custom_icon(button.name, icon_path)
			pass
		3: # Remove layout
			_remove_layout(button.name)
		4: # Add new layout
			add_child(preload("res://ui/popups/add_editor_layout/add_editor_layout.tscn").instantiate())


func _move_up(layout_id: String) -> void:
	## Moving the layout one up in the order of the sidebar and layout container.
	var button: Node = %SidebarVBox.get_node(layout_id)
	var container: Node = %LayoutContainer.get_node(layout_id)
	var button_pos := button.get_index()
	%SidebarVBox.move_child(
		button, 
		clampi(button_pos-1, 0, %SidebarVBox.get_child_count()))
	%LayoutContainer.move_child(
		container, 
		clampi(button_pos-1, 0, %SidebarVBox.get_child_count()))
	# Saving new order of layouts
	var new_order: PackedStringArray = []
	for child: Node in %SidebarVBox.get_children():
		new_order.append(child.name)
	config.set_value("general", "layouts_order", new_order)
	remove_custom_icon(layout_id)
	config.save(config_path)


func _move_down(layout_id: String) -> void:
	## Moving the layout one down in the order of the sidebar and layout container.
	var button: Node = %SidebarVBox.get_node(layout_id)
	var container: Node = %LayoutContainer.get_node(layout_id)
	var button_pos := button.get_index()
	%SidebarVBox.move_child(
		button, 
		clampi(button_pos+1, 0, %SidebarVBox.get_child_count()))
	%LayoutContainer.move_child(
		container, 
		clampi(button_pos+1, 0, %SidebarVBox.get_child_count()))
	# Saving new order of layouts
	var new_order: PackedStringArray = []
	for child: Node in %SidebarVBox.get_children():
		new_order.append(child.name)
	config.set_value("general", "layouts_order", new_order)
	remove_custom_icon(layout_id)
	config.save(config_path)


func _remove_layout(layout_id: String) -> void:
	## Removing a layout and related stuff.
	%SidebarVBox.get_node(layout_id).queue_free()
	%LayoutContainer.get_node(layout_id).queue_free()
	ModuleManager.remove_config_layout("layout_modules", layout_id)
	var new_order: PackedStringArray = config.get_value("general", "layouts_order")
	new_order.remove_at(new_order.find(layout_id))
	config.set_value("general", "layouts_order", new_order)
	remove_custom_icon(layout_id)
	# TODO: Find a way to delete all custom layout files of the layout modules
	# (have a remove config files callable function in the resource?)
	config.save(config_path)


func _set_custom_icon(layout_id: String, new_icon_path: String) -> void:
	## Setting a custom icon for a sidebar button.
	config.set_value("custom_icons", layout_id, new_icon_path)
	var button: Button = %SidebarVBox.get_node(layout_id)
	button.icon = load(new_icon_path)
	config.save(config_path)


func remove_custom_icon(layout_id: String) -> void:
	## Removes the custom icon from sidebar and from config file.
	if config.has_section_key("custom_icons", layout_id):
		if %SidebarVBox.has_node(layout_id): # Checking if button isn't deleted yet
			%SidebarVBox.get_node(layout_id).icon = null
		config.erase_section_key("custom_icons", layout_id)
		config.save(config_path)
