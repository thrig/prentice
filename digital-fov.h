#ifndef __DIGITAL_FOV_H__
#define __DIGITAL_FOV_H__

/* the digital FOV (Field Of Vision)
 * (http://roguebasin.roguelikedevelopment.org/index.php?title=Digital_field_of_view)
 *
 * definition:
 * A line L(a, b, s) is a set of grids (x, y) such that
 * y = (b * x) / a + s, rounded down.
 * A grid (X, Y) in the first octant (that is, 0 <= Y <= X) can be seen
 * from the grid (0, 0) if and only if (X, Y) is (0, 0) or there are
 * real numbers a, b and s such that:
 * * 0 <= b / a <= 1
 * * L(a, b, s) passes (0, 0) and (X, Y)
 * * a grid (x, y) on L(a, b, s) is not a wall as long as 1 <= x <= X - 1
 */

/* map must be a 2-dimension array of size (map_size_x, map_size_y).
 * map[x][y] must be non-zero if the grid (x, y) is a wall, 0 otherwise.
 */

/* Line Of Sight
 * runs at O(N)
 * return non-zero if the grid (bx, by) can be seen from the grid (ax, ay),
 * 0 otherwise
 */
int digital_los(int **map, int map_size_x, int map_size_y,
                int ax, int ay, int bx, int by);

/* map_fov must be a 2-dimension array of size
 * (2 * radius + 1, 2 * radius + 1).
 * The caller of the function must allocate enough memory to map_fov
 * before calling.
 * The result is written to map_fov; the grid (x, y) can be seen from
 * the grid (center_x, center_y) if and only if
 * map_fov[x - center_x + radius][y - center_y + radius] is non-zero.
 */

/* Field Of Vision
 * uses shadowcasting
 * runs at O(N^2) in the sense that each grid in an octant is visited
 * at most once
 * return 0 on success, 1 on error
 */
int digital_fov(int **map, int map_size_x, int map_size_y,
                int **map_fov,
                int center_x, int center_y, int radius);

#endif /* not __DIGITAL_FOV_H__ */
