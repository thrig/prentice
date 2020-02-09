/* prentice - apprentice wizard roguelike (or at this point just an
 * Entity Component System (ECS) that uses SQLite demo) */

#include "digital-fov.h"
#include "prentice.h"

#include <tcl.h>

Tcl_Interp *Interp;

char ***Map_Chars;
int **Map_Fov, ***Map_Walls, Map_Size_W, Map_Size_X, Map_Size_Y;
#define MAP_ROW_OFFSET 1
#define MAX_FOV_RADIUS 7

static void cleanup(void);
static void emit_help(void);
static int distance(int x1, int y1, int x2, int y2);
static void drawmap(int lvl, int entx, int enty, int radius);
static void include_tcl(char *file);
static char **make_charmap(int x, int y);
static int **make_intmap(int x, int y);
static int pr_freemap(ClientData clientData, Tcl_Interp *interp, int objc,
                      Tcl_Obj *CONST objv[]);
static int pr_getch(ClientData clientData, Tcl_Interp *interp, int objc,
                    Tcl_Obj *CONST objv[]);
static int pr_initmap(ClientData clientData, Tcl_Interp *interp, int objc,
                      Tcl_Obj *CONST objv[]);
static void setup_curses(void);
static void setup_tcl(int argc, char *argv[]);
static void stacktrace(int code);

int main(int argc, char *argv[]) {
    int ch, ret;

#ifdef __OpenBSD__
    if (pledge("cpath flock getpw prot_exec rpath stdio tty unix unveil wpath",
               NULL) == -1)
        err(1, "pledge failed");
    if (unveil("/", "r") == -1) err(1, "unveil failed");
    if (unveil(getwd(NULL), "crw") == -1) err(1, "unveil failed");
    if (unveil(NULL, NULL) == -1) err(1, "unveil failed");
#endif

    setlocale(LC_ALL, "");

    while ((ch = getopt(argc, argv, "h?")) != -1) {
        switch (ch) {
        case 'h':
        case '?':
        default:
            emit_help();
            /* NOTREACHED */
        }
    }
    argc -= optind;
    argv += optind;

    freopen("log", "w", stderr);
    Map_Fov = make_intmap(2 * MAX_FOV_RADIUS + 1, 2 * MAX_FOV_RADIUS + 1);
    setup_tcl(argc, argv);
    include_tcl("init.tcl");
    setup_curses();
    if ((ret = Tcl_EvalEx(Interp, "use_energy", -1, TCL_EVAL_GLOBAL)) !=
        TCL_OK) {
        cleanup();
        if (ret == TCL_ERROR) stacktrace(ret);
        errx(1, "TCL failed: %s", Tcl_GetStringResult(Interp));
    }
    /* NOTREACHED */
    exit(1);
}

static void cleanup(void) {
    curs_set(TRUE);
    endwin();
}

inline static void drawmap(int lvl, int entx, int enty, int radius) {
    erase();
    for (int i = 0; i < Map_Size_X; i++) {
        for (int j = 0; j < Map_Size_Y; j++) {
            int ch;
            if (distance(entx, enty, i, j) < radius &&
                Map_Fov[i - entx + radius][j - enty + radius]) {
                ch = Map_Chars[lvl][i][j];
            } else {
                ch = ' ';
            }
            mvaddch(j + MAP_ROW_OFFSET, i, ch);
        }
    }
    refresh();
}

// also borrowed from the digital-fov code repo
inline static int distance(int ax, int ay, int bx, int by) {
    int dx;
    int dy;
    dx = abs(bx - ax);
    dy = abs(by - ay);
    return dx > dy ? dx : dy;
}

inline static void emit_help(void) {
    fputs("Usage: ./prentice [dbfile]", stderr);
    exit(EX_USAGE);
}

inline static void include_tcl(char *file) {
    int ret;
    if ((ret = Tcl_EvalFile(Interp, file)) != TCL_OK) {
        if (ret == TCL_ERROR) stacktrace(ret);
        errx(1, "%s failed: %s", file, Tcl_GetStringResult(Interp));
    }
}

static char **make_charmap(int x, int y) {
    assert(x > 0);
    assert(y > 0);
    assert(x < 0xFF);
    assert(y < 0xFF);
    char **map;
    if ((map = malloc(x * sizeof(char *))) == NULL) err(1, "malloc failed");
    size_t len = x * y;
    if ((map[0] = malloc(len * sizeof(char))) == NULL) err(1, "malloc failed");
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
    if ((map = malloc(x * sizeof(int *))) == NULL) err(1, "malloc failed");
    if ((map[0] = calloc(x * y, sizeof(int))) == NULL) err(1, "malloc failed");
    for (int i = 1; i < x; i++)
        map[i] = map[0] + i * y;
    return map;
}

static int pr_freemap(ClientData clientData, Tcl_Interp *interp, int objc,
                      Tcl_Obj *CONST objv[]) {
    assert(Map_Chars != NULL);
    assert(Map_Walls != NULL);
    free(Map_Chars[0]);
    free(Map_Chars);
    free(Map_Walls[0]);
    free(Map_Walls);
    return TCL_OK;
}

static int pr_getch(ClientData clientData, Tcl_Interp *interp, int objc,
                    Tcl_Obj *CONST objv[]) {
    int ch;
    ch = getch();
    if (ch == ERR) ch = 27; // ESC
    Tcl_SetObjResult(interp, Tcl_NewIntObj(ch));
    return TCL_OK;
}

static int pr_initmap(ClientData clientData, Tcl_Interp *interp, int objc,
                      Tcl_Obj *CONST objv[]) {
    assert(objc > 1);
    assert(Map_Chars == NULL);
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

    if ((Map_Chars = malloc(Map_Size_W * sizeof(char *))) == NULL)
        err(1, "malloc failed");
    if ((Map_Walls = malloc(Map_Size_W * sizeof(int *))) == NULL)
        err(1, "malloc failed");

    for (int w = 0; w < Map_Size_W; w++) {
        Map_Walls[w] = make_intmap(Map_Size_X, Map_Size_Y);
        Map_Chars[w] = make_charmap(Map_Size_X, Map_Size_Y);

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
    return TCL_OK;
}

inline static void setup_curses(void) {
    initscr();
    atexit(cleanup);
    curs_set(FALSE);
    cbreak();
    noecho();
    nonl();
    // clearok(stdscr, TRUE);
    // refresh();
    // ignore resizes for now
    signal(SIGWINCH, SIG_IGN);
}

#define LINK_COMMAND(name, fn)                                                 \
    if (Tcl_CreateObjCommand(Interp, name, fn, (ClientData) NULL,              \
                             (Tcl_CmdDeleteProc *) NULL) == NULL)              \
    errx(1, "Tcl_CreateObjCommand failed")

inline static void setup_tcl(int argc, char *argv[]) {
    if ((Interp = Tcl_CreateInterp()) == NULL)
        errx(EX_OSERR, "Tcl_CreateInterp failed");
    if (Tcl_Init(Interp) == TCL_ERROR) errx(EX_OSERR, "Tcl_Init failed");
    LINK_COMMAND("free_map", pr_freemap);
    LINK_COMMAND("getch", pr_getch);
    LINK_COMMAND("initmap", pr_initmap);
    LINK_COMMAND("refreshmap", pr_refreshmap);
    Tcl_SetVar2(Interp, "dbfile", NULL, argc == 1 ? argv[0] : NULL, 0);
}

static void stacktrace(int code) {
    Tcl_Obj *options = Tcl_GetReturnOptions(Interp, code);
    Tcl_Obj *key     = Tcl_NewStringObj("-errorinfo", -1);
    Tcl_Obj *stacktrace;
    Tcl_IncrRefCount(key);
    Tcl_DictObjGet(NULL, options, key, &stacktrace);
    Tcl_DecrRefCount(key);
    fputs(Tcl_GetStringFromObj(stacktrace, NULL), stderr);
    fputs("\n", stderr);
}
