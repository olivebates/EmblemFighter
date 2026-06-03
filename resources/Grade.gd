class_name Grade extends RefCounted

# Item grade ladder. Grades are 1-based and UNBOUNDED: 1..19 are named below,
# anything above 19 is "Infinite +N". Stat bonuses scale by grade^2, upgrade
# cost is grade^3 tokens, dismantle yields ceil(grade^3 / 5) tokens.

const NAMES: Array[String] = [
	"Junk",        # 1
	"Crude",       # 2
	"Standard",    # 3
	"Improved",    # 4
	"Superior",    # 5
	"Elite",       # 6
	"Flawless",    # 7
	"Supreme",     # 8
	"Masterwork",  # 9
	"Divine",      # 10
	"Mythical",    # 11
	"Cosmic",      # 12
	"Immortal",    # 13
	"Omniscient",  # 14
	"God-like",    # 15
	"Void",        # 16
	"Void +2",     # 17
	"Void +3",     # 18
	"Infinite",    # 19
]

# Outline color per grade (background is this darkened 40%).
const COLORS: Array[Color] = [
	Color(0.50, 0.50, 0.50),  # Junk        — gray
	Color(0.72, 0.72, 0.72),  # Crude       — light gray
	Color(0.95, 0.95, 0.95),  # Standard    — white
	Color(0.60, 0.90, 0.55),  # Improved    — light green
	Color(0.16, 0.78, 0.42),  # Superior    — emerald green
	Color(0.25, 0.85, 0.92),  # Elite       — cyan
	Color(0.26, 0.45, 0.95),  # Flawless    — sapphire blue
	Color(0.60, 0.32, 0.92),  # Supreme     — violet
	Color(0.86, 0.14, 0.26),  # Masterwork  — crimson
	Color(1.00, 0.55, 0.12),  # Divine      — orange
	Color(1.00, 0.78, 0.20),  # Mythical    — bright yellow→golden orange
	Color(0.32, 0.22, 0.70),  # Cosmic      — deep indigo→purple-blue
	Color(1.00, 0.24, 0.72),  # Immortal    — vibrant pink→magenta
	Color(0.10, 0.85, 0.78),  # Omniscient  — teal→electric cyan
	Color(1.00, 0.86, 0.35),  # God-like    — gold→white-hot (animated)
	Color(0.18, 0.06, 0.50),  # Void        — deep indigo (animated)
	Color(0.22, 0.06, 0.55),  # Void +2     — deep indigo (animated)
	Color(0.26, 0.06, 0.60),  # Void +3     — deep indigo (animated)
	Color(0.80, 0.50, 1.00),  # Infinite    — rainbow (animated)
]

static func _index(grade: int) -> int:
	return clampi(grade - 1, 0, COLORS.size() - 1)

static func name_for(grade: int) -> String:
	if grade <= NAMES.size():
		return NAMES[_index(grade)]
	return "Infinite +%d" % (grade - NAMES.size())

static func outline_color(grade: int) -> Color:
	return COLORS[_index(grade)]

static func bg_color(grade: int) -> Color:
	var c := outline_color(grade)
	return Color(c.r * 0.3, c.g * 0.3, c.b * 0.3, 1.0)

# God-like (15) and Infinite (19) and beyond get an animated treatment.
static func is_animated(grade: int) -> bool:
	return grade >= 10

static func upgrade_cost(grade: int) -> int:
	return grade * grade * grade

# Total tokens invested = sum of upgrade costs from grade 1 → current grade.
# upgrade_cost(g) = g³, so sum(1³+2³+...+(grade-1)³) = ((grade-1)*grade/2)²
static func dismantle_yield(grade: int) -> int:
	var n = (grade - 1) * grade / 2
	return n * n

static func stat_mult(grade: int) -> int:
	return grade * grade
