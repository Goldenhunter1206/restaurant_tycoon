class_name MetricDef
extends RefCounted
## Definition + number formatting for one analytics metric. Metrics are
## code-defined (each is coupled to the system that produces it), so this is a
## lightweight value type plus a static registry the report UI reads for
## labels, units, and consistent number formatting. It is NOT a generic
## metric-evaluation engine — the buckets carry raw floats and this only
## describes/formats them.

enum Unit { MONEY, COUNT, PERCENT, RATING, MINUTES, RAW }
enum Agg { SUM, AVG, LAST, MAX }

var id: StringName
var label: String
var unit: int = Unit.RAW
var agg: int = Agg.SUM
## &"company" | &"restaurant" | &"recipe".
var scope: StringName = &"company"
## Optional capability id required to see this metric; &"" = always visible.
var gate: StringName = &""


func _init(p_id: StringName, p_label: String, p_unit: int, p_agg: int, p_scope: StringName, p_gate: StringName = &"") -> void:
	id = p_id
	label = p_label
	unit = p_unit
	agg = p_agg
	scope = p_scope
	gate = p_gate


## Render a value in this metric's unit ("$1,240", "612", "42%", "4.2", "12m").
func format(value: float) -> String:
	match unit:
		Unit.MONEY:
			return money(value)
		Unit.PERCENT:
			return "%d%%" % roundi(value * 100.0) if value <= 1.0 else "%d%%" % roundi(value)
		Unit.RATING:
			return "%.1f" % value
		Unit.MINUTES:
			return "%dm" % roundi(value)
		Unit.COUNT:
			return thousands(roundi(value))
		_:
			return str(value)


## Signed delta ("+$42", "-3%", "+0.1"), coloured by the caller.
func format_delta(value: float) -> String:
	var sign_str: String = "+" if value >= 0.0 else "−"
	match unit:
		Unit.MONEY:
			return "%s%s" % [sign_str, money(absf(value)).lstrip("−")]
		Unit.PERCENT:
			return "%s%d%%" % [sign_str, roundi(absf(value) * (100.0 if absf(value) <= 1.0 else 1.0))]
		Unit.RATING:
			return "%s%.1f" % [sign_str, absf(value)]
		Unit.MINUTES:
			return "%s%dm" % [sign_str, roundi(absf(value))]
		_:
			return "%s%s" % [sign_str, thousands(roundi(absf(value)))]


# --- Static number formatting (shared by every report screen) ----------------


## "$18,240" (rounded, grouped thousands, leading − for negatives).
static func money(value: float) -> String:
	var neg: bool = value < 0.0
	var body: String = thousands(roundi(absf(value)))
	return "%s$%s" % ["−" if neg else "", body]


## Compact currency for tight chips: "$1.2k", "$18.2k", "$1.4M".
static func money_compact(value: float) -> String:
	var neg: bool = value < 0.0
	var v: float = absf(value)
	var body: String
	if v >= 1_000_000.0:
		body = "%.1fM" % (v / 1_000_000.0)
	elif v >= 1_000.0:
		body = "%.1fk" % (v / 1_000.0)
	else:
		body = "%d" % roundi(v)
	return "%s$%s" % ["−" if neg else "", body]


## Integer with grouped thousands: 18240 -> "18,240".
static func thousands(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out


# --- Registry (display metadata the report UI reads) -------------------------

static var _registry: Dictionary = {}


static func by_id(metric_id: StringName) -> MetricDef:
	if _registry.is_empty():
		_build_registry()
	return _registry.get(metric_id)


static func all() -> Dictionary:
	if _registry.is_empty():
		_build_registry()
	return _registry


static func _add(def: MetricDef) -> void:
	_registry[def.id] = def


static func _build_registry() -> void:
	# Company scope.
	_add(MetricDef.new(&"revenue", "Revenue", Unit.MONEY, Agg.SUM, &"company"))
	_add(MetricDef.new(&"expenses", "Expenses", Unit.MONEY, Agg.SUM, &"company"))
	_add(MetricDef.new(&"profit", "Profit", Unit.MONEY, Agg.SUM, &"company"))
	_add(MetricDef.new(&"cash", "Cash", Unit.MONEY, Agg.LAST, &"company"))
	_add(MetricDef.new(&"loan", "Loan", Unit.MONEY, Agg.LAST, &"company"))
	_add(MetricDef.new(&"inventory_value", "Inventory value", Unit.MONEY, Agg.LAST, &"company"))
	_add(MetricDef.new(&"reputation", "Reputation", Unit.RATING, Agg.LAST, &"company"))
	_add(MetricDef.new(&"restaurant_count", "Restaurants", Unit.COUNT, Agg.LAST, &"company"))
	_add(MetricDef.new(&"market_share", "Market share", Unit.PERCENT, Agg.LAST, &"company"))
	_add(MetricDef.new(&"share_of_voice", "Share of voice", Unit.PERCENT, Agg.LAST, &"company"))
	_add(MetricDef.new(&"payroll", "Payroll", Unit.MONEY, Agg.SUM, &"company"))
	# Restaurant scope.
	_add(MetricDef.new(&"sales", "Sales", Unit.MONEY, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"branch_expenses", "Expenses", Unit.MONEY, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"branch_profit", "Profit", Unit.MONEY, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"guests", "Guests", Unit.COUNT, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"orders", "Orders", Unit.COUNT, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"lost_demand", "Lost demand", Unit.COUNT, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"cancelled", "Cancelled", Unit.COUNT, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"stockouts", "Stockouts", Unit.COUNT, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"staffing_cost", "Staffing", Unit.MONEY, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"rent", "Rent", Unit.MONEY, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"deliveries", "Deliveries", Unit.COUNT, Agg.SUM, &"restaurant"))
	_add(MetricDef.new(&"delivery_fail_rate", "Late/failed", Unit.PERCENT, Agg.AVG, &"restaurant"))
	_add(MetricDef.new(&"avg_delivery_time", "Avg delivery", Unit.MINUTES, Agg.AVG, &"restaurant"))
	_add(MetricDef.new(&"rating", "Rating", Unit.RATING, Agg.LAST, &"restaurant"))
