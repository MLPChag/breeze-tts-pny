extends SceneTree
## Uses the game's unmodified official mod builder on a temporary overlay project.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Expected official builder path and output .pck"); quit(1); return
	var builder: GDScript = load(args[0])
	var result: String = builder.build("breeze_tts_pny", args[1])
	if result.begins_with("ERROR"):
		printerr(result); quit(1); return
	print("MOD_BUILT ", result)
	quit()
