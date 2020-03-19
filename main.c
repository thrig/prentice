/* prentice - apprentice wizard roguelike (or at this point just an
 * Entity Component System (ECS) that uses SQLite demo) */

#include "prentice.h"

Tcl_Interp *Interp;

static void cleanup(void);
static void emit_help(void);
static void include_tcl(char *file);
static int pr_getch(ClientData clientData, Tcl_Interp *interp, int objc,
                    Tcl_Obj *CONST objv[]);
static void setup_curses(void);
static void setup_tcl(int argc, char *argv[]);
static void stacktrace(int code);

int main(int argc, char *argv[]) {
#ifdef __OpenBSD__
    if (pledge("cpath flock getpw prot_exec rpath stdio tty unix unveil wpath",
               NULL) == -1)
        err(1, "pledge failed");
    if (unveil("/", "r") == -1) err(1, "unveil failed");
    if (unveil(getwd(NULL), "crw") == -1) err(1, "unveil failed");
    if (unveil(NULL, NULL) == -1) err(1, "unveil failed");
#endif

    setlocale(LC_ALL, "");

    int ch;
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

    setup_tcl(argc, argv);
    setup_curses();
    setup_map();
    setup_messages();

    freopen("log", "w", stderr); // DBG
    setvbuf(stderr, (char *) NULL, _IONBF, (size_t) 0);

    include_tcl("init.tcl");
    int ret;
    if ((ret = Tcl_EvalEx(Interp, "use_energy", -1, TCL_EVAL_GLOBAL)) !=
        TCL_OK) {
        if (ret == TCL_ERROR) stacktrace(ret);
        errx(1, "TCL failed: %s", Tcl_GetStringResult(Interp));
    }

    exit(1); // NOTREACHED
}

static void cleanup(void) {
    curs_set(TRUE);
    nocbreak();
    echo();
    nl();
    endwin();
}

inline static void emit_help(void) {
    fputs("Usage: ./prentice [dbfile]", stderr);
    exit(EX_USAGE);
}

// post-ncurses setup bailouts
void fatal(const char *const fmt, ...) {
    assert(fmt);
    clear();
    attrset(A_NORMAL);
    move(LINES - 2, 0);
    va_list ap;
    va_start(ap, fmt);
    printw(fmt, ap);
    va_end(ap);
    wrefresh(stdscr);
    cleanup();
    exit(1);
}

inline static void include_tcl(char *file) {
    int ret;
    if ((ret = Tcl_EvalFile(Interp, file)) != TCL_OK) {
        if (ret == TCL_ERROR) stacktrace(ret);
        errx(1, "%s failed: %s", file, Tcl_GetStringResult(Interp));
    }
}

static int pr_getch(ClientData clientData, Tcl_Interp *interp, int objc,
                    Tcl_Obj *CONST objv[]) {
    int ch;
    ch = getch();
    if (ch == ERR) ch = 27; // ESC
    Tcl_SetObjResult(interp, Tcl_NewIntObj(ch));
    return TCL_OK;
}

inline static void setup_curses(void) {
    initscr();
    if (LINES < NEED_ROWS || COLS < NEED_COLS) {
        endwin();
        warnx("terminal must be at least %dx%d", NEED_COLS, NEED_ROWS);
        exit(EX_UNAVAILABLE);
    }
    atexit(cleanup);
    if (has_colors()) start_color();
    init_pair(1, COLOR_WHITE, COLOR_BLACK);
    init_pair(2, COLOR_RED, COLOR_BLACK);
    init_pair(3, COLOR_YELLOW, COLOR_BLACK);
    init_pair(4, COLOR_BLACK, COLOR_WHITE);
    init_pair(5, COLOR_GREEN, COLOR_BLACK);
    curs_set(FALSE);
    cbreak();
    noecho();
    nonl();
    signal(SIGWINCH, SIG_IGN);
}

inline static void setup_tcl(int argc, char *argv[]) {
    if ((Interp = Tcl_CreateInterp()) == NULL)
        errx(EX_OSERR, "Tcl_CreateInterp failed");
    if (Tcl_Init(Interp) == TCL_ERROR) errx(EX_OSERR, "Tcl_Init failed");
    LINK_COMMAND("getch", pr_getch);
    Tcl_SetVar2(Interp, "dbfile", NULL, argc == 1 ? argv[0] : NULL, 0);
}

static void stacktrace(int code) {
    Tcl_Obj *options = Tcl_GetReturnOptions(Interp, code);
    Tcl_Obj *key     = Tcl_NewStringObj("-errorinfo", -1);
    Tcl_Obj *stacktrace;
    Tcl_IncrRefCount(key);
    Tcl_DictObjGet(NULL, options, key, &stacktrace);
    Tcl_DecrRefCount(key);
    cleanup();
    fputs(Tcl_GetStringFromObj(stacktrace, NULL), stderr);
    fputs("\n", stderr);
}
