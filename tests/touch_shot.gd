extends Node
func _ready():
	GameState.checkpoint = "talked_mum"
	GameState.flags = {"talked_mum": true}
	call_deferred("_go")
func _go():
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.change_scene_to_file("res://levels/ch1_beginning/ch1_beginning.tscn")
	await tree.create_timer(4.0).timeout
	var lv = tree.current_scene
	lv.player.teleport(Vector3(-1.6, 0.05, -3.3), PI)
	await tree.create_timer(2.0).timeout
	tree.root.get_viewport().get_texture().get_image().save_png("/tmp/touch_play.png")
	tree.quit()
