/* prentice - apprentice wizard roguelike (or at this point just an ECS
 * that uses sqlite demo) */

#include "prentice.h"

#include <tcl.h>

typedef void (*cleanupfn) (void);

Tcl_Interp *Interp;

static void emit_help(void);
static void include_tcl(char *file, cleanupfn clean);
static void setup_curses(void);
static void setup_tcl(int argc, char *argv[]);
static int pr_napms(ClientData clientData, Tcl_Interp * interp, int objc,
                    Tcl_Obj * CONST objv[]);

int main(int argc, char *argv[])
{
    int ch;

#ifdef __OpenBSD__
    if (pledge
        ("cpath flock getpw prot_exec rpath stdio tty unix unveil wpath",
         NULL) == -1)
        err(1, "pledge failed");
    if (unveil("/", "r") == -1)
        err(1, "unveil failed");
    if (unveil(getwd(NULL), "crw") == -1)
        err(1, "unveil failed");
    if (unveil(NULL, NULL) == -1)
        err(1, "unveil failed");
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

    setup_tcl(argc, argv);
    include_tcl("init.tcl", NULL);
    freopen("log", "w", stderr);
    setup_curses();
    include_tcl("main.tcl", cleanup);

    /* NOTREACHED */
    exit(1);
}

void cleanup(void)
{
    curs_set(TRUE);
    endwin();
}

inline static void emit_help(void)
{
    fputs("Usage: ./prentice [dbfile]", stderr);
    exit(EX_USAGE);
}

inline static void include_tcl(char *file, cleanupfn clean)
{
    int ret;
    if ((ret = Tcl_EvalFile(Interp, file)) != TCL_OK) {
        if (clean)
            clean();
        if (ret == TCL_ERROR) {
            Tcl_Obj *options = Tcl_GetReturnOptions(Interp, ret);
            Tcl_Obj *key = Tcl_NewStringObj("-errorinfo", -1);
            Tcl_Obj *stacktrace;
            Tcl_IncrRefCount(key);
            Tcl_DictObjGet(NULL, options, key, &stacktrace);
            Tcl_DecrRefCount(key);
            fputs(Tcl_GetStringFromObj(stacktrace, NULL), stderr);
            fputs("\n", stderr);
        }
        errx(1, "%s failed: %s", file, Tcl_GetStringResult(Interp));
    }
}

static int pr_getch(ClientData clientData, Tcl_Interp * interp, int objc,
                    Tcl_Obj * CONST objv[])
{
    int ch;
    // TODO WITHKEYPAD support (see io.c in rogue36 and mdport.c)
    ch = getch();
    if (ch == ERR)
        ch = 27;                // ESC
    Tcl_SetObjResult(interp, Tcl_NewIntObj(ch));
    return TCL_OK;
}

static int pr_napms(ClientData clientData, Tcl_Interp * interp, int objc,
                    Tcl_Obj * CONST objv[])
{
    int delay;
    assert(objc == 2);
    assert(Tcl_GetIntFromObj(interp, objv[1], &delay) == TCL_OK);
    napms(delay);
    return TCL_OK;
}

inline static void setup_curses(void)
{
    initscr();
    atexit(cleanup);
    curs_set(FALSE);
    cbreak();
    noecho();
    nonl();
#ifdef WITHKEYPAD
    keypad(stdscr, TRUE);
#endif
    clearok(stdscr, TRUE);
    refresh();
}

inline static void setup_tcl(int argc, char *argv[])
{
    if ((Interp = Tcl_CreateInterp()) == NULL)
        errx(EX_OSERR, "Tcl_CreateInterp failed");

    if (Tcl_Init(Interp) == TCL_ERROR)
        errx(EX_OSERR, "Tcl_Init failed");

    if (Tcl_CreateObjCommand
        (Interp, "getch", pr_getch, (ClientData) NULL,
         (Tcl_CmdDeleteProc *) NULL) == NULL)
        errx(1, "Tcl_CreateObjCommand failed");
    if (Tcl_CreateObjCommand
        (Interp, "napms", pr_napms, (ClientData) NULL,
         (Tcl_CmdDeleteProc *) NULL) == NULL)
        errx(1, "Tcl_CreateObjCommand failed");

    Tcl_SetVar2(Interp, "dbfile", NULL, argc == 1 ? argv[0] : NULL, 0);
}
