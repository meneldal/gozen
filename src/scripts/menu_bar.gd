extends PanelContainer


func _on_project_id_pressed(a_id: int) -> void: ## Menu bar popup button
	match a_id:
		0: Project.save() # Save current project
		1: Project.save("") # Save current project to new location
		2: Project.load("") # Load project
		3: pass # TODO: Add a load recent projects dropdown


func _on_help_id_pressed(a_id: int) -> void: ## Menu bar popup button
	match a_id:
		0: Utils.open_url("https://voylin.com/projects/gozen/")
		1: Utils.open_url("https://ko-fi.com/voylin")

