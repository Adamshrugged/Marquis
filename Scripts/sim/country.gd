extends RefCounted
class_name Country

var id: int
var color: String
var control: String          # player or ai
var funds: float
var tax: int
var leader: Unit
var alive := true
var conqueror := -1          # once beaten [E]: who takes its villages and units, one at a time
                             # (Simulation.MONSTER: they're wiped out instead)
var default_order := "auto"
var style := "balanced"      # AI personality, see Rules.STYLES
var population := 0.0        # village population plus units but the leader, as the leader follows it [E]
var connected := {}          # village idx -> true, villages that pay tax
var auto_tax := false
var target := -1             # enemy country the army is aimed at
var rally := Vector2i(-1, -1) # own village where the army gathers
var reserve := 0.0           # funds held back (for a bridge the army needs)
var upkeep := 0.0            # funds paid in upkeep today
var decay := 0.0             # strength units lost away from base today
var threat := false          # enemies near the castle
var plans := {}              # job board: cell idx -> [kind, priority], see Simulation.add_plans
var playbook: Array = []     # unit playbook lines, see Playbook
var tax_book := {}           # tax playbook {lines, otherwise}, used while auto_tax is on
