extends RefCounted
## Grid/cell math helpers (shared; avoid rewriting per module).

## Chebyshev (king-move) distance between two cells.
static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Chebyshev distance between two cells given as raw coordinates.
static func chebyshev_cells(ax: int, ay: int, bx: int, by: int) -> int:
	return maxi(absi(ax - bx), absi(ay - by))


## Manhattan distance between two cells.
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Whether two cells are orthogonally/diagonally adjacent (Chebyshev <= 1, not equal).
static func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return a != b and chebyshev(a, b) <= 1
