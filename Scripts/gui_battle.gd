extends Control

@onready var money: Label = $HBoxContainer/NinePatchRect/MarginContainer/VBoxContainer/Money
@onready var days: Label = $HBoxContainer/NinePatchRect/MarginContainer/VBoxContainer/Days
@onready var tax_rate: Label = $HBoxContainer/NinePatchRect/MarginContainer/VBoxContainer/TaxRate
@onready var strength: Label = $HBoxContainer/NinePatchRect2/MarginContainer/VBoxContainer/Strength
@onready var soldiers: Label = $HBoxContainer/NinePatchRect2/MarginContainer/VBoxContainer/Soldiers
@onready var empty: Label = $HBoxContainer/NinePatchRect3/MarginContainer/VBoxContainer/Empty
@onready var farms: Label = $HBoxContainer/NinePatchRect3/MarginContainer/VBoxContainer/Farms
@onready var towns: Label = $HBoxContainer/NinePatchRect3/MarginContainer/VBoxContainer/Towns



func updateTilesTowns(t) -> void:
	towns.text = "Towns: " + str(t)
	
func updateTilesEmpty(t) -> void:
	empty.text = "Empty: " + str(t)
	
func updateTilesFarms(t) -> void:
	farms.text = "Farms: " + str(t)
	
func updateMoney(m) -> void:
	money.text = "Money: $" + str(m)

func updateDays(d) -> void:
	days.text = "Days: " + str(d)

func updateTax(t) -> void:
	tax_rate.text = "Tax Rate: " + str(t) + "%"

func updateStrength(s) -> void:
	strength.text = "Strength: " + str(s)

func updateSoldiers(s) -> void:
	soldiers.text = "Soldiers: " + str(s)
