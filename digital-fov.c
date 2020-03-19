/* FILE */
#include <stdio.h>
/* malloc, abs */
#include <stdlib.h>
/* memcpy */
#include <string.h>

#include "digital-fov.h"
#include "prentice.h"

struct _rays
{
  int bottom_ray_touch_top_wall_u;
  int bottom_ray_touch_top_wall_v;
  int bottom_ray_touch_bottom_wall_u;
  int bottom_ray_touch_bottom_wall_v;

  int top_ray_touch_bottom_wall_u;
  int top_ray_touch_bottom_wall_v;
  int top_ray_touch_top_wall_u;
  int top_ray_touch_top_wall_v;

  /* the bottom ray touches the top wall at
   * (top_wall_array_u[b_ray_t], top_wall_array_v[b_ray_t])
   * when it is updated
   * note that top_wall_array_u[b_ray_t] <= bottom_ray_touch_top_wall_u
   * even if those 2 numbers may not be equal
   */
  int b_ray_t;
  /* the top ray touches the bottom wall at
   * (bottom_wall_array_u[t_ray_b], bottom_wall_array_v[t_ray_b])
   * when it is updated
   * note that bottom_wall_array_u[t_ray_b] <= top_ray_touch_bottom_wall_u
   * even if those 2 numbers may not be equal
   */
  int t_ray_b;

  /* remember only relevant walls */
  int top_wall_num;
  int bottom_wall_num;
  int *top_wall_array_u;
  int *top_wall_array_v;
  int *bottom_wall_array_u;
  int *bottom_wall_array_v;
};
typedef struct _rays rays;

static rays *rays_new(int radius);
static void rays_delete(rays *rp);
static int rays_copy(rays *rp_to, rays *rp_from);
static int rays_add_bottom_wall(rays *rp, int u, int v);
static int rays_add_top_wall(rays *rp, int u, int v);

static int grid_is_illegal(int x, int y, int map_size_x, int map_size_y);
static int which_side_of_line(int ax, int ay, int bx, int by,
                              int x, int y);
static int digital_fov_recursive_body(int **map,
                                      int map_size_x, int map_size_y,
                                      int **map_fov,
                                      int center_x, int center_y, int radius,
                                      int dir,
                                      int u_start,
                                      rays *rp);

static rays *
rays_new(int radius)
{
  rays *rp = NULL;

  rp = (rays *) malloc(sizeof(rays));
  if (rp == NULL) oom();

  rp->bottom_ray_touch_top_wall_u = 0;
  rp->bottom_ray_touch_top_wall_v = 1;
  rp->bottom_ray_touch_bottom_wall_u = 1;
  rp->bottom_ray_touch_bottom_wall_v = -1;

  rp->top_ray_touch_bottom_wall_u = 0;
  rp->top_ray_touch_bottom_wall_v = 0;
  rp->top_ray_touch_top_wall_u = 1;
  rp->top_ray_touch_top_wall_v = 2;

  rp->b_ray_t = 0;
  rp->t_ray_b = 0;

  rp->top_wall_num = 0;
  rp->bottom_wall_num = 0;
  rp->top_wall_array_u = NULL;
  rp->top_wall_array_v = NULL;
  rp->bottom_wall_array_u = NULL;
  rp->bottom_wall_array_v = NULL;

  rp->top_wall_array_u = (int *) malloc(sizeof(int) * (radius + 1));
  if (rp->top_wall_array_u == NULL) oom();
  rp->top_wall_array_v = (int *) malloc(sizeof(int) * (radius + 1));
  if (rp->top_wall_array_v == NULL) oom();
  rp->bottom_wall_array_u = (int *) malloc(sizeof(int) * (radius + 1));
  if (rp->bottom_wall_array_u == NULL) oom();
  rp->bottom_wall_array_v = (int *) malloc(sizeof(int) * (radius + 1));
  if (rp->bottom_wall_array_v == NULL) oom();

  rp->top_wall_array_u[0] = 0;
  rp->top_wall_array_v[0] = 1;
  rp->top_wall_num = 1;

  rp->bottom_wall_array_u[0] = 0;
  rp->bottom_wall_array_v[0] = 0;
  rp->bottom_wall_num = 1;

  return rp;
}

static void
rays_delete(rays *rp)
{
  if (rp->top_wall_array_u != NULL)
  {
    free(rp->top_wall_array_u);
    rp->top_wall_array_u = NULL;
  }
  if (rp->top_wall_array_v != NULL)
  {
    free(rp->top_wall_array_v);
    rp->top_wall_array_v = NULL;
  }
  if (rp->bottom_wall_array_u != NULL)
  {
    free(rp->bottom_wall_array_u);
    rp->bottom_wall_array_u = NULL;
  }
  if (rp->bottom_wall_array_v != NULL)
  {
    free(rp->bottom_wall_array_v);
    rp->bottom_wall_array_v = NULL;
  }

  free(rp);
  rp = NULL;
}

/* runs at O(N) because of memcpy()
 * return 0 on success, 1 on error
 */
static int
rays_copy(rays *rp_to, rays *rp_from)
{
  if (rp_to == NULL)
    return 1;
  if (rp_from == NULL)
    return 1;
  if (rp_to == rp_from)
    return 1;

  rp_to->bottom_ray_touch_top_wall_u
    = rp_from->bottom_ray_touch_top_wall_u;
  rp_to->bottom_ray_touch_top_wall_v
    = rp_from->bottom_ray_touch_top_wall_v;
  rp_to->bottom_ray_touch_bottom_wall_u
    = rp_from->bottom_ray_touch_bottom_wall_u;
  rp_to->bottom_ray_touch_bottom_wall_v
    = rp_from->bottom_ray_touch_bottom_wall_v;

  rp_to->top_ray_touch_bottom_wall_u
    = rp_from->top_ray_touch_bottom_wall_u;
  rp_to->top_ray_touch_bottom_wall_v
    = rp_from->top_ray_touch_bottom_wall_v;
  rp_to->top_ray_touch_top_wall_u
    = rp_from->top_ray_touch_top_wall_u;
  rp_to->top_ray_touch_top_wall_v
    = rp_from->top_ray_touch_top_wall_v;

  rp_to->b_ray_t = rp_from->b_ray_t;
  rp_to->t_ray_b = rp_from->t_ray_b;

  rp_to->top_wall_num = rp_from->top_wall_num;
  rp_to->bottom_wall_num = rp_from->bottom_wall_num;

  memcpy(rp_to->top_wall_array_u, rp_from->top_wall_array_u,
         sizeof(int) *rp_from->top_wall_num);
  memcpy(rp_to->top_wall_array_v, rp_from->top_wall_array_v,
         sizeof(int) *rp_from->top_wall_num);
  memcpy(rp_to->bottom_wall_array_u, rp_from->bottom_wall_array_u,
         sizeof(int) *rp_from->bottom_wall_num);
  memcpy(rp_to->bottom_wall_array_v, rp_from->bottom_wall_array_v,
         sizeof(int) *rp_from->bottom_wall_num);

  return 0;
}

static int
rays_add_bottom_wall(rays *rp, int u, int v)
{
  if (rp == NULL)
    return 1;

  if (which_side_of_line(rp->top_ray_touch_bottom_wall_u,
                         rp->top_ray_touch_bottom_wall_v,
                         rp->top_ray_touch_top_wall_u,
                         rp->top_ray_touch_top_wall_v,
                         u, v + 1) >= 0)
  {
    /* the new bottom wall blocks all rays */
    return 1;
  }

  /* update bottom ray */
  if (which_side_of_line(rp->bottom_ray_touch_top_wall_u,
                         rp->bottom_ray_touch_top_wall_v,
                         rp->bottom_ray_touch_bottom_wall_u,
                         rp->bottom_ray_touch_bottom_wall_v,
                         u, v + 1) > 0)
  {
    rp->bottom_ray_touch_bottom_wall_u = u;
    rp->bottom_ray_touch_bottom_wall_v = v + 1;
    while (rp->b_ray_t + 1 < rp->top_wall_num)
    {
      if (rp->top_wall_array_u[rp->b_ray_t + 1] >= u)
        break;
      if (which_side_of_line(rp->bottom_ray_touch_top_wall_u,
                             rp->bottom_ray_touch_top_wall_v,
                             rp->bottom_ray_touch_bottom_wall_u,
                             rp->bottom_ray_touch_bottom_wall_v,
                             rp->top_wall_array_u[rp->b_ray_t + 1],
                             rp->top_wall_array_v[rp->b_ray_t + 1]) >= 0)
        break;
      rp->bottom_ray_touch_top_wall_u = rp->top_wall_array_u[rp->b_ray_t + 1];
      rp->bottom_ray_touch_top_wall_v = rp->top_wall_array_v[rp->b_ray_t + 1];
      (rp->b_ray_t)++;
    }
  }

  /* remember bottom wall */
  /* note that two or more bottom walls may be added to the same rp
   * for a given u */
  if ((rp->bottom_wall_num >= 1)
      && (rp->bottom_wall_array_u[rp->bottom_wall_num - 1] == u))
  {
    /* rp->bottom_wall_array[rp->bottom_wall_num - 1] is no longer relevant */
    rp->bottom_wall_array_u[rp->bottom_wall_num - 1] = u;
    rp->bottom_wall_array_v[rp->bottom_wall_num - 1] = v + 1;
  }
  else
  {    
    rp->bottom_wall_array_u[rp->bottom_wall_num] = u;
    rp->bottom_wall_array_v[rp->bottom_wall_num] = v + 1;
    rp->bottom_wall_num++;
  }

  while (rp->bottom_wall_num >= 3)
  {
    if (which_side_of_line(rp->bottom_wall_array_u[rp->bottom_wall_num - 3],
                           rp->bottom_wall_array_v[rp->bottom_wall_num - 3],
                           rp->bottom_wall_array_u[rp->bottom_wall_num - 1],
                           rp->bottom_wall_array_v[rp->bottom_wall_num - 1],
                           rp->bottom_wall_array_u[rp->bottom_wall_num - 2],
                           rp->bottom_wall_array_v[rp->bottom_wall_num - 2])
        > 0)
      break;
    /* rp->bottom_wall_array[rp->bottom_wall_num - 2] is no longer relevant */
    rp->bottom_wall_array_u[rp->bottom_wall_num - 2]
      = rp->bottom_wall_array_u[rp->bottom_wall_num - 1];
    rp->bottom_wall_array_v[rp->bottom_wall_num - 2]
      = rp->bottom_wall_array_v[rp->bottom_wall_num - 1];
    if (rp->t_ray_b == rp->bottom_wall_num - 2)
      (rp->t_ray_b)--;
    (rp->bottom_wall_num)--;
  }

  return 0;
}

static int
rays_add_top_wall(rays *rp, int u, int v)
{
  if (rp == NULL)
    return 1;

  if (which_side_of_line(rp->bottom_ray_touch_top_wall_u,
                         rp->bottom_ray_touch_top_wall_v,
                         rp->bottom_ray_touch_bottom_wall_u,
                         rp->bottom_ray_touch_bottom_wall_v,
                         u, v) <= 0)
  {
    /* the new top wall blocks all rays */
    return 1;
  }

  /* update top ray */
  if (which_side_of_line(rp->top_ray_touch_bottom_wall_u,
                         rp->top_ray_touch_bottom_wall_v,
                         rp->top_ray_touch_top_wall_u,
                         rp->top_ray_touch_top_wall_v,
                         u, v) < 0)
  {
    rp->top_ray_touch_top_wall_u = u;
    rp->top_ray_touch_top_wall_v = v;
    while (rp->t_ray_b + 1 < rp->bottom_wall_num)
    {
      if (rp->bottom_wall_array_u[rp->t_ray_b + 1] >= u)
        break;
      if (which_side_of_line(rp->top_ray_touch_bottom_wall_u,
                             rp->top_ray_touch_bottom_wall_v,
                             rp->top_ray_touch_top_wall_u,
                             rp->top_ray_touch_top_wall_v,
                             rp->bottom_wall_array_u[rp->t_ray_b + 1],
                             rp->bottom_wall_array_v[rp->t_ray_b + 1]) <= 0)
        break;
      rp->top_ray_touch_bottom_wall_u
        = rp->bottom_wall_array_u[rp->t_ray_b + 1];
      rp->top_ray_touch_bottom_wall_v
        = rp->bottom_wall_array_v[rp->t_ray_b + 1];
      (rp->t_ray_b)++;
    }
  }

  /* remember top wall */
  rp->top_wall_array_u[rp->top_wall_num] = u;
  rp->top_wall_array_v[rp->top_wall_num] = v;
  (rp->top_wall_num)++;

  while (rp->top_wall_num >= 3)
  {
    if (which_side_of_line(rp->top_wall_array_u[rp->top_wall_num - 3],
                           rp->top_wall_array_v[rp->top_wall_num - 3],
                           rp->top_wall_array_u[rp->top_wall_num - 1],
                           rp->top_wall_array_v[rp->top_wall_num - 1],
                           rp->top_wall_array_u[rp->top_wall_num - 2],
                           rp->top_wall_array_v[rp->top_wall_num - 2])
        < 0)
      break;

    /* rp->top_wall_array[rp->top_wall_num - 2] is no longer relevant */
    rp->top_wall_array_u[rp->top_wall_num - 2]
      = rp->top_wall_array_u[rp->top_wall_num - 1];
    rp->top_wall_array_v[rp->top_wall_num - 2]
      = rp->top_wall_array_v[rp->top_wall_num - 1];
    if (rp->b_ray_t == rp->top_wall_num - 2)
      (rp->b_ray_t)--;
    (rp->top_wall_num)--;
  }

  return 0;
}

/* return 1 (true) or 0 (false) */
static int
grid_is_illegal(int x, int y, int map_size_x, int map_size_y)
{
  if ((x < 0) || (x >= map_size_x))
    return 1;
  if ((y < 0) || (y >= map_size_y))
    return 1;

  return 0;
}

/* Suppose that:
 * * there are 4 points (ax, ay), (bx, by), (x, y) and (x, Y)
 * * ax < bx
 * * the 3 points (ax, ay), (bx, by) and (x, Y) are on the same line
 * The return value of this function has same sign as y - Y, that is,
 * this function returns a positive value if and only if (x, y) is
 * above the line which passes (ax, bx) and (bx, by).
 * The caller of this function must ensure that ax < bx.
 */
static int
which_side_of_line(int ax, int ay, int bx, int by,
                   int x, int y)
{
  return (y - ay) * (bx - ax)
    - (by - ay) * (x - ax);
}

int
digital_los(int **map, int map_size_x, int map_size_y,
            int ax, int ay, int bx, int by)
{
  /* summary:
   * A ray that passes (0, 0) and (X, Y) passes no grid other than
   * (x, (x * Y) / X) and (x, (x * Y) / X + 1).
   */
  int dx;
  int dy;
  int dx_abs;
  int dy_abs;
  int du_abs;
  int dv_abs;
  int dir;
  int u;
  int v;
  int temp;
  int x0;
  int y0;
  int x1;
  int y1;
  int grid0_is_illegal;
  int grid1_is_illegal;
  int r;
  int result;

  int bottom_ray_touch_top_wall_u;
  int bottom_ray_touch_top_wall_v;
  int bottom_ray_touch_bottom_wall_u;
  int bottom_ray_touch_bottom_wall_v;

  int top_ray_touch_bottom_wall_u;
  int top_ray_touch_bottom_wall_v;
  int top_ray_touch_top_wall_u;
  int top_ray_touch_top_wall_v;

  /* the bottom ray touches the top wall at
   * (top_wall_array_u[b_ray_t], top_wall_array_v[b_ray_t])
   * when it is updated
   * note that top_wall_array_u[b_ray_t] <= bottom_ray_touch_top_wall_u
   * even if those 2 numbers may not be equal
   */
  int b_ray_t;
  /* the top ray touches the bottom wall at
   * (bottom_wall_array_u[t_ray_b], bottom_wall_array_v[t_ray_b])
   * when it is updated
   * note that bottom_wall_array_u[t_ray_b] <= top_ray_touch_bottom_wall_u
   * even if those 2 numbers may not be equal
   */
  int t_ray_b;

  /* remember only relevant walls */
  int top_wall_num;
  int bottom_wall_num;
  int *top_wall_array_u = NULL;
  int *top_wall_array_v = NULL;
  int *bottom_wall_array_u = NULL;
  int *bottom_wall_array_v = NULL;

  if (map == NULL)
    return 0;
  if (grid_is_illegal(ax, ay, map_size_x, map_size_y))
    return 0;
  if (grid_is_illegal(bx, by, map_size_x, map_size_y))
    return 0;

  dx = bx - ax;
  dy = by - ay;
  dx_abs = abs(dx);
  dy_abs = abs(dy);

  if ((dx_abs <= 1) && (dy_abs <= 1))
    return 1;

  if (dx >= 0)
  {
    if (dy >= 0)
    {
      if (dx_abs >= dy_abs)
        dir = 0;
      else
        dir = 1;
    }
    else
    {
      if (dx_abs >= dy_abs)
        dir = 7;
      else
        dir = 6;
    }
  }
  else
  {
    if (dy >= 0)
    {
      if (dx_abs >= dy_abs)
        dir = 3;
      else
        dir = 2;
    }
    else
    {
      if (dx_abs >= dy_abs)
        dir = 4;
      else
        dir = 5;
    }
  }

  if (dx_abs >= dy_abs)
  {
    du_abs = dx_abs;
    dv_abs = dy_abs;
  }
  else
  {
    du_abs = dy_abs;
    dv_abs = dx_abs;
  }
  
  top_wall_array_u = (int *) malloc(sizeof(int) * (du_abs + 1));
  if (top_wall_array_u == NULL) oom();
  top_wall_array_v = (int *) malloc(sizeof(int) * (du_abs + 1));
  if (top_wall_array_v == NULL) oom();
  bottom_wall_array_u = (int *) malloc(sizeof(int) * (du_abs + 1));
  if (bottom_wall_array_u == NULL) oom();
  bottom_wall_array_v = (int *) malloc(sizeof(int) * (du_abs + 1));
  if (bottom_wall_array_v == NULL) oom();

  bottom_ray_touch_top_wall_u = 0;
  bottom_ray_touch_top_wall_v = 1;
  bottom_ray_touch_bottom_wall_u = 1;
  bottom_ray_touch_bottom_wall_v = -1;

  top_ray_touch_bottom_wall_u = 0;
  top_ray_touch_bottom_wall_v = 0;
  top_ray_touch_top_wall_u = 1;
  top_ray_touch_top_wall_v = 2;

  top_wall_array_u[0] = 0;
  top_wall_array_v[0] = 1;
  top_wall_num = 1;

  bottom_wall_array_u[0] = 0;
  bottom_wall_array_v[0] = 0;
  bottom_wall_num = 1;

  b_ray_t = 0;
  t_ray_b = 0;

  result = 1;

  v = 0;
  r = 0;
  for (u = 1; u <= du_abs; u++)
  {
    /* v = (u * dv_abs) / du_abs;
     * r = (u * dv_abs) % du_abs;
     */
    r += dv_abs;
    if (r >= du_abs)
    {
      v++;
      r -= du_abs;
    }

    x0 = u;
    y0 = v;
    x1 = u;
    y1 = v + 1;

    if ((dir & 1) == 1)
    {
      temp = x0;
      x0 = y0;
      y0 = temp;

      temp = x1;
      x1 = y1;
      y1 = temp;
    }
    if ((dir & 2) == 2)
    {
      temp = x0;
      x0 = -y0;
      y0 = temp;

      temp = x1;
      x1 = -y1;
      y1 = temp;
    }
    if ((dir & 4) == 4)
    {
      x0 = -x0;
      y0 = -y0;

      x1 = -x1;
      y1 = -y1;
    }

    x0 += ax;
    y0 += ay;
    x1 += ax;
    y1 += ay;

    grid0_is_illegal = grid_is_illegal(x0, y0, map_size_x, map_size_y);
    grid1_is_illegal = grid_is_illegal(x1, y1, map_size_x, map_size_y);

    if (r == 0)
    {
      if (!((!grid0_is_illegal)
            && (which_side_of_line(bottom_ray_touch_top_wall_u,
                                   bottom_ray_touch_top_wall_v,
                                   bottom_ray_touch_bottom_wall_u,
                                   bottom_ray_touch_bottom_wall_v,
                                   u, v + 1) > 0)
            && (which_side_of_line(top_ray_touch_bottom_wall_u,
                                   top_ray_touch_bottom_wall_v,
                                   top_ray_touch_top_wall_u,
                                   top_ray_touch_top_wall_v,
                                   u, v) < 0)))
      {
        result = 0;
        break;
      }
      if ((grid0_is_illegal)
          || (map[x0][y0] != 0))
      {
        if (u < du_abs)
          result = 0;
        break;
      }
    }
    else
    {
      /* check if some ray is still available */
      if ((!((!grid0_is_illegal)
             && (which_side_of_line(bottom_ray_touch_top_wall_u,
                                    bottom_ray_touch_top_wall_v,
                                    bottom_ray_touch_bottom_wall_u,
                                    bottom_ray_touch_bottom_wall_v,
                                    u, v + 1) > 0)
             && (which_side_of_line(top_ray_touch_bottom_wall_u,
                                    top_ray_touch_bottom_wall_v,
                                    top_ray_touch_top_wall_u,
                                    top_ray_touch_top_wall_v,
                                    u, v) < 0)))
          && (!((!grid1_is_illegal)
                && (which_side_of_line(bottom_ray_touch_top_wall_u,
                                       bottom_ray_touch_top_wall_v,
                                       bottom_ray_touch_bottom_wall_u,
                                       bottom_ray_touch_bottom_wall_v,
                                       u, v + 2) > 0)
                && (which_side_of_line(top_ray_touch_bottom_wall_u,
                                       top_ray_touch_bottom_wall_v,
                                       top_ray_touch_top_wall_u,
                                       top_ray_touch_top_wall_v,
                                       u, v + 1) < 0))))
      {
        result = 0;
        break;
      }

      /* update top and bottom ray */
      if ((grid0_is_illegal)
          || (map[x0][y0] != 0))
      {
        if (which_side_of_line(bottom_ray_touch_top_wall_u,
                               bottom_ray_touch_top_wall_v,
                               bottom_ray_touch_bottom_wall_u,
                               bottom_ray_touch_bottom_wall_v,
                               u, v + 1) > 0)
        {
          bottom_ray_touch_bottom_wall_u = u;
          bottom_ray_touch_bottom_wall_v = v + 1;
          while (b_ray_t + 1 < top_wall_num)
          {
            /* this loop is called at most du_abs times
             * because each call increase bottom_ray_touch_top_wall_u,
             * which starts at 0 and can't be greater than du_abs
             */
            if (which_side_of_line(bottom_ray_touch_top_wall_u,
                                   bottom_ray_touch_top_wall_v,
                                   bottom_ray_touch_bottom_wall_u,
                                   bottom_ray_touch_bottom_wall_v,
                                   top_wall_array_u[b_ray_t + 1],
                                   top_wall_array_v[b_ray_t + 1]) >= 0)
              break;
            bottom_ray_touch_top_wall_u = top_wall_array_u[b_ray_t + 1];
            bottom_ray_touch_top_wall_v = top_wall_array_v[b_ray_t + 1];
            b_ray_t++;
          }
        }
      }
      if ((grid1_is_illegal)
          || (map[x1][y1] != 0))
      {
        if (which_side_of_line(top_ray_touch_bottom_wall_u,
                               top_ray_touch_bottom_wall_v,
                               top_ray_touch_top_wall_u,
                               top_ray_touch_top_wall_v,
                               u, v + 1) < 0)
        {
          top_ray_touch_top_wall_u = u;
          top_ray_touch_top_wall_v = v + 1;
          while (t_ray_b + 1 < bottom_wall_num)
          {
            /* this loop is called at most du_abs times
             * because each call increase top_ray_touch_bottom_wall_u,
             * which starts at 0 and can't be greater than du_abs
             */
            if (which_side_of_line(top_ray_touch_bottom_wall_u,
                                   top_ray_touch_bottom_wall_v,
                                   top_ray_touch_top_wall_u,
                                   top_ray_touch_top_wall_v,
                                   bottom_wall_array_u[t_ray_b + 1],
                                   bottom_wall_array_v[t_ray_b + 1]) <= 0)
              break;
            top_ray_touch_bottom_wall_u = bottom_wall_array_u[t_ray_b + 1];
            top_ray_touch_bottom_wall_v = bottom_wall_array_v[t_ray_b + 1];
            t_ray_b++;
          }
        }
      }

      /* remember wall */
      if ((grid0_is_illegal)
          || (map[x0][y0] != 0))
      {
        if (which_side_of_line(top_ray_touch_bottom_wall_u,
                               top_ray_touch_bottom_wall_v,
                               top_ray_touch_top_wall_u,
                               top_ray_touch_top_wall_v,
                               u, v + 1) >= 0)
        {
          /* the new bottom wall blocks all rays */
          if (u < du_abs)
            result = 0;
          break;
        }

        bottom_wall_array_u[bottom_wall_num] = u;
        bottom_wall_array_v[bottom_wall_num] = v + 1;
        bottom_wall_num++;

        while (bottom_wall_num >= 3)
        {
          /* this loop is called at most (2 * du_abs) times
           * because for each u, each call after the first removes
           * a wall from bottom_wall_array and at most du_abs walls
           * can be added to bottom_wall_array
           */
          if (which_side_of_line(bottom_wall_array_u[bottom_wall_num - 3],
                                 bottom_wall_array_v[bottom_wall_num - 3],
                                 bottom_wall_array_u[bottom_wall_num - 1],
                                 bottom_wall_array_v[bottom_wall_num - 1],
                                 bottom_wall_array_u[bottom_wall_num - 2],
                                 bottom_wall_array_v[bottom_wall_num - 2])
              > 0)
            break;

          /* bottom_wall_array[bottom_wall_num - 2] is no longer relevant */
          bottom_wall_array_u[bottom_wall_num - 2]
            = bottom_wall_array_u[bottom_wall_num - 1];
          bottom_wall_array_v[bottom_wall_num - 2]
            = bottom_wall_array_v[bottom_wall_num - 1];
          if (t_ray_b == bottom_wall_num - 2)
            t_ray_b--;
          bottom_wall_num--;
        }
      }
      if ((grid1_is_illegal)
          || (map[x1][y1] != 0))
      {
        if (which_side_of_line(bottom_ray_touch_top_wall_u,
                               bottom_ray_touch_top_wall_v,
                               bottom_ray_touch_bottom_wall_u,
                               bottom_ray_touch_bottom_wall_v,
                               u, v + 1) <= 0)
        {
          /* the new top wall blocks all rays */
          if (u < du_abs)
            result = 0;
          break;
        }

        top_wall_array_u[top_wall_num] = u;
        top_wall_array_v[top_wall_num] = v + 1;
        top_wall_num++;

        while (top_wall_num >= 3)
        {
          /* this loop is called at most (2 * du_abs) times
           * because for each u, each call after the first removes
           * a wall from top_wall_array and at most du_abs walls
           * can be added to top_wall_array
           */
          if (which_side_of_line(top_wall_array_u[top_wall_num - 3],
                                 top_wall_array_v[top_wall_num - 3],
                                 top_wall_array_u[top_wall_num - 1],
                                 top_wall_array_v[top_wall_num - 1],
                                 top_wall_array_u[top_wall_num - 2],
                                 top_wall_array_v[top_wall_num - 2])
              < 0)
            break;

          /* top_wall_array[top_wall_num - 2] is no longer relevant */
          top_wall_array_u[top_wall_num - 2]
            = top_wall_array_u[top_wall_num - 1];
          top_wall_array_v[top_wall_num - 2]
            = top_wall_array_v[top_wall_num - 1];
          if (b_ray_t == top_wall_num - 2)
            b_ray_t--;
          top_wall_num--;
        }
      }
    }
  }

  free(top_wall_array_u);
  top_wall_array_u = NULL;
  free(top_wall_array_v);
  top_wall_array_v = NULL;
  free(bottom_wall_array_u);
  bottom_wall_array_u = NULL;
  free(bottom_wall_array_v);
  bottom_wall_array_v = NULL;

  return result;
}

/* this function deletes rp if it is not NULL
 * return 0 on success, 1 on error
 */
static int
digital_fov_recursive_body(int **map,
                           int map_size_x, int map_size_y,
                           int **map_fov,
                           int center_x, int center_y, int radius,
                           int dir,
                           int u_start,
                           rays *rp)
{
  /* summary:
   * If a wall is found, divide all rays that are not blocked
   * by it into 2 groups: rays that pass above it and rays that pass
   * below it.  Handle the "below" group with another call of
   * this function.
   */
  int u;
  int v;
  int temp;
  int x;
  int y;
  int illegal;
  int v_start;
  int v_end;
  int previous_grid_is_wall;
  int new_top_wall_found;
  int new_top_wall_v;

  rays *rp_child = NULL;

  if (rp == NULL)
    return 1;

  if (map == NULL)
  {
    rays_delete(rp);
    rp = NULL;
    return 1;
  }
  if (map_fov == NULL)
  {
    rays_delete(rp);
    rp = NULL;
    return 1;
  }
  if (radius < 0)
  {
    rays_delete(rp);
    rp = NULL;
    return 1;
  }
  if (rp->bottom_ray_touch_bottom_wall_u
      == rp->bottom_ray_touch_top_wall_u)
  {
    rays_delete(rp);
    rp = NULL;
    return 1;
  }
  if (rp->top_ray_touch_top_wall_u
      == rp->top_ray_touch_bottom_wall_u)
  {
    rays_delete(rp);
    rp = NULL;
    return 1;
  }

  for (u = u_start; u <= radius; u++)
  {
    v_start = rp->bottom_ray_touch_bottom_wall_v
      - rp->bottom_ray_touch_top_wall_v;
    v_start *= u - rp->bottom_ray_touch_top_wall_u;
    /* if v_start is non-negative, this round it down
     * if v_start is negative, we don't care because
     * v_start is set to 0 later
     */
    v_start /= rp->bottom_ray_touch_bottom_wall_u
      - rp->bottom_ray_touch_top_wall_u;
    v_start += rp->bottom_ray_touch_top_wall_v;
    if (v_start < 0)
      v_start = 0;

    v_end = rp->top_ray_touch_top_wall_v
      - rp->top_ray_touch_bottom_wall_v;
    v_end *= u - rp->top_ray_touch_bottom_wall_u;
    /* v_end must be rounded up
     * note that v_end can't be negative
     */
    v_end += rp->top_ray_touch_top_wall_u
      - rp->top_ray_touch_bottom_wall_u - 1;
    v_end /= rp->top_ray_touch_top_wall_u
      - rp->top_ray_touch_bottom_wall_u;
    v_end += rp->top_ray_touch_bottom_wall_v;
    v_end -= 1;
    if (v_end > u)
      v_end = u;

    previous_grid_is_wall = 1;
    new_top_wall_found = 0;
    new_top_wall_v = rp->top_ray_touch_top_wall_v;

    if (v_start > v_end)
      break;

    for (v = v_start; v <= v_end; v++)
    {
      x = u;
      y = v;

      if ((dir & 1) == 1)
      {
        temp = x;
        x = y;
        y = temp;
      }
      if ((dir & 2) == 2)
      {
        temp = x;
        x = -y;
        y = temp;
      }
      if ((dir & 4) == 4)
      {
        x = -x;
        y = -y;
      }

      x += center_x;
      y += center_y;

      illegal = grid_is_illegal(x, y, map_size_x, map_size_y);

      if (!illegal)
        map_fov[x - center_x + radius][y - center_y + radius] = 1;

      if ((illegal)
          || (map[x][y] != 0))
      {
        if (!previous_grid_is_wall)
        {
          new_top_wall_found = 1;
          new_top_wall_v = v;
        }

        previous_grid_is_wall = 1;
      }
      else
      {
        if (previous_grid_is_wall)
        {
          if (new_top_wall_found)
          {
            rp_child = rays_new(radius);
            if (rp_child == NULL)
            {
              rays_delete(rp);
              rp = NULL;
              return 1;
            }
            rays_copy(rp_child, rp);
            rays_add_top_wall(rp_child, u, new_top_wall_v);
            if (digital_fov_recursive_body(map,
                                           map_size_x, map_size_y,
                                           map_fov,
                                           center_x, center_y, radius,
                                           dir,
                                           u + 1,
                                           rp_child) != 0)
            {
              rays_delete(rp);
              rp = NULL;
              return 1;
            }
            rp_child = NULL;
            new_top_wall_found = 0;
          }
          rays_add_bottom_wall(rp, u, v - 1);
        }
        previous_grid_is_wall = 0;
      }
    }

    if (new_top_wall_found)
    {
      rays_add_top_wall(rp, u, new_top_wall_v);
    }
    else if (previous_grid_is_wall)
    { 
      break;
    }
  }

  rays_delete(rp);
  rp = NULL;

  return 0;
}

int
digital_fov(int **map, int map_size_x, int map_size_y,
            int **map_fov,
            int center_x, int center_y, int radius)
{
  int x;
  int y;
  int dir;
  int error_found;
  rays *rp = NULL;

  if (map == NULL)
    return 1;
  if (map_fov == NULL)
    return 1;
  if (radius < 0)
    return 1;

  for (x = center_x - radius; x <= center_x + radius; x++)
  {
    for (y = center_y - radius; y <= center_y + radius; y++)
    {
      map_fov[x - center_x + radius][y - center_y + radius] = 0;
    }
  }

  if (grid_is_illegal(center_x, center_y, map_size_x, map_size_y))
    return 1;

  map_fov[0 + radius][0 + radius] = 1;

  error_found = 0;
  for (dir = 0; dir < 8; dir++)
  {
    rp = rays_new(radius);
    if (rp == NULL)
      return 1;
    if (digital_fov_recursive_body(map,
                                   map_size_x, map_size_y,
                                   map_fov,
                                   center_x, center_y, radius,
                                   dir,
                                   1,
                                   rp) != 0)
      error_found = 1;
    rp = NULL;
  }

  return error_found;
}
