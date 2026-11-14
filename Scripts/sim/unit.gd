extends RefCounted
class_name Unit

## A character on the map. The leader is a Unit with is_leader set.

var id: int
var owner: int
var pos: Vector2i
var prev_pos: Vector2i      # position before this day's move, for smooth drawing
var strength: float
var is_leader := false
var order := "auto"          # auto, standby, ordered
var line := -2               # auto: playbook line it's following, -1 "otherwise", -2 none
var line_text := ""          # that line, described when chosen
var ordered := false         # true when the player gave this unit an order
var dead := false

var path: Array[Vector2i] = []
var job := ""                # auto: clear, build, attack, march, rally, home
                             # ordered: any action id, or move (leader)
var job_target := Vector2i(-1, -1)
var work := 0                # days of work left at the target
var queue: Array = []        # player's queued orders, [target: Vector2i, action: String] pairs
var watching := false        # continuous order waiting, not actually working
var wait := 0                # days before the next step
var idle := 0                # days until auto rethinks
var decay := 0
var waited := 0              # days spent waiting at the rally point
var facing := Vector2i(0, 1)


func size_class() -> String:
	if strength >= Rules.SIZE_L:
		return "L"
	if strength >= Rules.SIZE_M:
		return "M"
	return "S"


func clear_job() -> void:
	path.clear()
	job = ""
	job_target = Vector2i(-1, -1)
	work = 0
