extends Resource
class_name OneWayLedgeData

# One one-way ledge on a floor (FloorData.one_way_ledges): a wall walked
# down through but never up - floor 3's rim trail ending in its bank.
# RegionField builds a OneWayLedge from it (_spawn_floor_ledges()).

# The wall's line, world XZ from the floor's spawn (x = X, y = Z), across
# the way down - as a LedgeBarrier's points, in order along it.
@export var line: PackedVector2Array = PackedVector2Array()
# Any point on the down side - the ground he lands on - world XZ from the
# spawn. It says which side of the line is "down"; it needn't be near.
@export var down_point: Vector2 = Vector2.ZERO
