extends Resource
class_name RutLook

# A floor's own look for its ruts (FloorData.rut_look) in place of the
# region's - Ground's Ruts exports, each of the same name: RegionField
# pushes these onto Ground with the floor's rut_path (_apply_rut_look()),
# and again on any edit here, so they are live. Data only: nothing here
# names Ground, so FloorData's scripts load without the field's. Without
# one (FloorData.rut_look null) a floor's ruts look as the region's do:
# floor 3's cart.
#
# rut_gauge 0 draws one line instead of a wheel pair; rut_wave_amplitude
# above 0 swings it side to side, rut_wave_length metres from one swing
# to the next - floor 4's snake trail, from the pup's hollow to the
# Adder's den.

@export var rut_gauge: float = 1.4:
	set(value):
		rut_gauge = value
		emit_changed()
@export var rut_width: float = 0.12:
	set(value):
		rut_width = value
		emit_changed()
@export_range(0.0, 1.0) var rut_darken: float = 0.08:
	set(value):
		rut_darken = value
		emit_changed()
@export var rut_fade_in: float = 4.0:
	set(value):
		rut_fade_in = value
		emit_changed()
@export var rut_fade_out: float = 1.5:
	set(value):
		rut_fade_out = value
		emit_changed()
@export var rut_break_length: float = 4.0:
	set(value):
		rut_break_length = value
		emit_changed()
@export_range(0.0, 1.0) var rut_break_threshold: float = 0.3:
	set(value):
		rut_break_threshold = value
		emit_changed()
@export var rut_waver: float = 0.04:
	set(value):
		rut_waver = value
		emit_changed()
@export var rut_wave_amplitude: float = 0.0:
	set(value):
		rut_wave_amplitude = value
		emit_changed()
@export var rut_wave_length: float = 0.8:
	set(value):
		rut_wave_length = value
		emit_changed()

