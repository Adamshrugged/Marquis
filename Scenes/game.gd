extends Node2D

# Scenes
@onready var map: Node2D = $Map
@onready var gui_battle: Control = $GuiBattle

# Time tracking
var elapsed_time = 0
@export var ticksPerDay = 1



func grow() -> void:
	GameManager.money += map.grow()
	map.rulersGrow()
	
func moveSoldiers() -> void:
	GameManager.soldiers = map.getSoldierCount()
	map.moveSoldiers()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	map.initialize_map()
	map.spawn_ruler()
	# Initialize variables
	GameManager.money = 5000
	GameManager.days = 1
	GameManager.tax_rate = 50
	GameManager.strength = 1
	GameManager.soldiers = 0
	GameManager.status = ""
	GameManager.tilesEmpty = map.getCount("empty")
	GameManager.tilesFarm = map.getCount("farm")
	GameManager.tilesFarm = map.getCount("town")
	updateLabels()

func updateLabels() -> void:
	gui_battle.updateMoney(GameManager.money)
	gui_battle.updateDays(GameManager.days)
	gui_battle.updateTax(GameManager.tax_rate)
	gui_battle.updateStrength(GameManager.strength)
	gui_battle.updateSoldiers(GameManager.soldiers)
	gui_battle.updateTilesEmpty(GameManager.tilesEmpty)
	gui_battle.updateTilesFarms(GameManager.tilesFarm)
	gui_battle.updateTilesTowns(GameManager.tilesTown)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	elapsed_time += _delta
	if elapsed_time > ticksPerDay:
		GameManager.days += 1
		elapsed_time = 0
		# Grow tiles
		grow() 
		updateLabels()
		# Get tile count information
		GameManager.tilesEmpty = map.getCount("empty")
		GameManager.tilesFarm = map.getCount("farm")
		GameManager.tilesTown = map.getCount("town")
		GameManager.strength = map.getRulerStrength()
		moveSoldiers()
