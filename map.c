/* map related operations (showing it on the screen) */

#include "digital-fov.h"
#include "prentice.h"

char ***Map_Chars;
int **Map_Fov, ***Map_Seen, ***Map_Walls, Map_Size_W, Map_Size_X, Map_Size_Y;
WINDOW *Map_View;

static int distance(int x1, int y1, int x2, int y2);
static void drawmap(int lvl, int entx, int enty, int radius);
static char **make_charmap(int x, int y);
static int **make_intmap(int x, int y);

// also borrowed from the digital-fov code repo (Chebyshev distance)
inline static int distance(int ax, int ay, int bx, int by) {
    int dx = abs(bx - ax);
    int dy = abs(by - ay);
    return dx > dy ? dx : dy;
}

#define MAP_PRINT(i, j, ch) mvwaddch(Map_View, j, i, ch)

inline static void drawmap(int lvl, int entx, int enty, int radius) {
    werase(Map_View);
    int startx = entx - VIEW_OFFSET_X;
    int starty = enty - VIEW_OFFSET_Y;
    int basex, viewx, widthx;
    int basey, viewy, widthy;
    if (startx < 0) {
        basex  = 0;
        viewx  = abs(startx);
        widthx = VIEW_SIZE_X - viewx;
    } else {
        basex  = startx;
        viewx  = 0;
        widthx = Map_Size_X - basex;
        if (VIEW_SIZE_X < widthx) widthx = VIEW_SIZE_X;
    }
    if (starty < 0) {
        basey  = 0;
        viewy  = abs(starty);
        widthy = VIEW_SIZE_Y - viewy;
    } else {
        basey  = starty;
        viewy  = 0;
        widthy = Map_Size_Y - basey;
        if (VIEW_SIZE_Y < widthy) widthy = VIEW_SIZE_Y;
    }
    for (int i = 0; i < widthx; i++) {
        int mapx = basex + i;
        for (int j = 0; j < widthy; j++) {
            int mapy = basey + j;
            if (distance(entx, enty, mapx, mapy) < radius &&
                Map_Fov[mapx - entx + radius][mapy - enty + radius]) {
                int ch = Map_Chars[lvl][mapx][mapy];
                switch (ch) {
                case '&': ch = ACS_DIAMOND;
                case '#':
                case '.':
                    wattron(Map_View, PAINT_WHITE);
                    MAP_PRINT(viewx + i, viewy + j, ch);
                    wattroff(Map_View, PAINT_WHITE);
                    break;
                case ',':
                    wattron(Map_View, A_BOLD);
                    wattron(Map_View, PAINT_YELLOW);
                    MAP_PRINT(viewx + i, viewy + j, ',');
                    wattroff(Map_View, PAINT_YELLOW);
                    wattroff(Map_View, A_BOLD);
                    break;
                default:
                    wattron(Map_View, A_BOLD);
                    wattron(Map_View, PAINT_WHITE);
                    MAP_PRINT(viewx + i, viewy + j, ch);
                    wattroff(Map_View, PAINT_WHITE);
                    wattroff(Map_View, A_BOLD);
                }
                Map_Seen[lvl][i][j] = 1;
            } else {
                if (Map_Seen[lvl][i][j]) {
                    int ch = Map_Chars[lvl][mapx][mapy];
                    wattron(Map_View, A_DIM);
                    switch (ch) {
                    case '&': ch = ACS_DIAMOND;
                    case '#':
                    case '+':
                    case '>':
                    case '<':
                    case ' ': MAP_PRINT(viewx + i, viewy + j, ch); break;
                    default: MAP_PRINT(viewx + i, viewy + j, '.');
                    }
                    wattroff(Map_View, A_DIM);
                }
            }
        }
    }
    wnoutrefresh(Map_View);
}

#undef MAP_PRINT

static char **make_charmap(int x, int y) {
    assert(x > 0);
    assert(y > 0);
    assert(x < 0xFF);
    assert(y < 0xFF);
    char **map;
    if ((map = malloc(sizeof(char *) * x)) == NULL) oom();
    size_t len = x * y;
    if ((map[0] = malloc(sizeof(char) * len)) == NULL) oom();
    memset(map[0], ' ', len);
    for (int i = 1; i < x; i++)
        map[i] = map[0] + i * y;
    return map;
}

static int **make_intmap(int x, int y) {
    assert(x > 0);
    assert(y > 0);
    assert(x < 0xFF);
    assert(y < 0xFF);
    int **map;
    if ((map = malloc(sizeof(int *) * x)) == NULL) oom();
    if ((map[0] = calloc((size_t) x * y, sizeof(int))) == NULL) oom();
    for (int i = 1; i < x; i++)
        map[i] = map[0] + i * y;
    return map;
}

static int pr_initmap(ClientData clientData, Tcl_Interp *interp, int objc,
                      Tcl_Obj *CONST objv[]) {
    assert(objc > 1);
    assert(Map_Chars == NULL);
    assert(Map_Seen == NULL);
    assert(Map_Walls == NULL);

    int count, a, b;
    Tcl_Obj **list;

    // boundary as x1, y1, x2, y2, lvl-min, lvl-max
    Tcl_ListObjGetElements(interp, objv[1], &count, &list);
    assert(count == 6);
    Tcl_GetIntFromObj(interp, list[0], &a);
    Tcl_GetIntFromObj(interp, list[2], &b);
    Map_Size_X = b - a + 1;
    Tcl_GetIntFromObj(interp, list[1], &a);
    Tcl_GetIntFromObj(interp, list[3], &b);
    Map_Size_Y = b - a + 1;
    Tcl_GetIntFromObj(interp, list[4], &a);
    Tcl_GetIntFromObj(interp, list[5], &b);
    Map_Size_W = b - a + 1;
    assert(Map_Size_W > 0);
    assert(Map_Size_X > 0);
    assert(Map_Size_Y > 0);

    if ((Map_Chars = malloc(sizeof(char *) * Map_Size_W)) == NULL) oom();
    if ((Map_Seen = malloc(sizeof(int *) * Map_Size_W)) == NULL) oom();
    if ((Map_Walls = malloc(sizeof(int *) * Map_Size_W)) == NULL) oom();

    for (int w = 0; w < Map_Size_W; w++) {
        Map_Chars[w] = make_charmap(Map_Size_X, Map_Size_Y);
        Map_Seen[w]  = make_intmap(Map_Size_X, Map_Size_Y);
        Map_Walls[w] = make_intmap(Map_Size_X, Map_Size_Y);

        // topmost character as x,y,ch,zlevel (zlevel is unused here)
        Tcl_ListObjGetElements(interp, objv[w * 2 + 2], &count, &list);
        assert(count % 4 == 0);
        for (int i = 0; i < count; i += 4) {
            Tcl_GetIntFromObj(interp, list[i], &a);
            Tcl_GetIntFromObj(interp, list[i + 1], &b);
            assert(a >= 0 && a < Map_Size_X);
            assert(b >= 0 && b < Map_Size_Y);
            int ch;
            Tcl_GetIntFromObj(interp, list[i + 2], &ch);
            assert(isprint(ch));
            Map_Chars[w][a][b] = ch;
        }

        // is-wall?
        Tcl_ListObjGetElements(interp, objv[w * 2 + 3], &count, &list);
        assert((count & 1) == 0);
        for (int i = 0; i < count; i += 2) {
            Tcl_GetIntFromObj(interp, list[i], &a);
            Tcl_GetIntFromObj(interp, list[i + 1], &b);
            Map_Seen[w][a][b]  = 0;
            Map_Walls[w][a][b] = 1;
        }
    }

    return TCL_OK;
}

static int pr_refreshmap(ClientData clientData, Tcl_Interp *interp, int objc,
                         Tcl_Obj *CONST objv[]) {
    int count, lvl, entx, enty, radius;
    Tcl_Obj **list;
    assert(objc == 4);

    // w,x,y location of entity to draw FOV relative to
    Tcl_ListObjGetElements(interp, objv[1], &count, &list);
    assert(count == 3);
    Tcl_GetIntFromObj(interp, list[0], &lvl);
    Tcl_GetIntFromObj(interp, list[1], &entx);
    Tcl_GetIntFromObj(interp, list[2], &enty);
    assert(lvl >= 0 && lvl < Map_Size_W);
    assert(entx >= 0 && entx < Map_Size_X);
    assert(enty >= 0 && enty < Map_Size_Y);

    // dirty cells to update - entid,x,y,ch,is-wall?
    Tcl_ListObjGetElements(interp, objv[2], &count, &list);
    assert(count % 5 == 0);
    for (int i = 0; i < count; i += 5) {
        int a, b, ch, wall;
        Tcl_GetIntFromObj(interp, list[i + 1], &a);
        Tcl_GetIntFromObj(interp, list[i + 2], &b);
        Tcl_GetIntFromObj(interp, list[i + 3], &ch);
        Tcl_GetIntFromObj(interp, list[i + 4], &wall);
        assert(a >= 0 && a < Map_Size_X);
        assert(b >= 0 && b < Map_Size_Y);
        assert(isprint(ch));
        Map_Chars[lvl][a][b] = ch;
        Map_Walls[lvl][a][b] = wall;
    }

    Tcl_GetIntFromObj(interp, objv[3], &radius);
    assert(radius > 0 && radius <= MAX_FOV_RADIUS);

    digital_fov(Map_Walls[lvl], Map_Size_X, Map_Size_Y, Map_Fov, entx, enty,
                radius);
    drawmap(lvl, entx, enty, radius);
    doupdate();
    return TCL_OK;
}

void setup_map(void) {
    Map_Fov = make_intmap(2 * MAX_FOV_RADIUS + 1, 2 * MAX_FOV_RADIUS + 1);
    LINK_COMMAND("initmap", pr_initmap);
    LINK_COMMAND("refreshmap", pr_refreshmap);
    Map_View = subwin(stdscr, VIEW_SIZE_Y, VIEW_SIZE_X, 0, 0);
    leaveok(Map_View, TRUE);
}
