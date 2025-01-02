extends PanelContainer

@export var fps_output : Label
@export var logger_output : Label

func _ready() -> void:
	Logger.output_instance = logger_output


func _process(_delta: float) -> void:
	var fps : float = Performance.get_monitor(Performance.TIME_FPS)
	fps_output.text = "%.1f FPS " % fps
