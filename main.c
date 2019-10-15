/* prentice - apprentice wizard roguelike (or at this point just an ECS
 * that uses sqlite demo) */

#include "prentice.h"

#include <tcl.h>

Tcl_Interp *Interp;

static void emit_help(void);
static void setup_tcl(void);
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
        default:
            emit_help();
            /* NOTREACHED */
        }
    }
    argc -= optind;
    argv += optind;

    //setvbuf(stdout, (char *) NULL, _IONBF, (size_t) 0);

    setup_tcl();

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

    if (Tcl_EvalFile(Interp, "main.tcl") != TCL_OK) {
        cleanup();
        errx(1, "main.tcl failed: %s", Tcl_GetStringResult(Interp));
    }

    return 0;
}

inline void cleanup(void)
{
    curs_set(TRUE);
    endwin();
}

inline static void emit_help(void)
{
    fputs("Usage: ./prentice", stderr);
    exit(EX_USAGE);
}

// expose napms(3) to TCL
static int pr_napms(ClientData clientData, Tcl_Interp * interp, int objc,
                    Tcl_Obj * CONST objv[])
{
    int delay;
    assert(objc == 2);
    assert(Tcl_GetIntFromObj(interp, objv[1], &delay) == TCL_OK);
    napms(delay);
    return TCL_OK;
}

inline static void setup_tcl(void)
{
    if ((Interp = Tcl_CreateInterp()) == NULL)
        errx(EX_OSERR, "Tcl_CreateInterp failed");
    if (Tcl_Init(Interp) == TCL_ERROR)
        errx(EX_OSERR, "Tcl_Init failed");
    if (Tcl_EvalFile(Interp, "init.tcl") != TCL_OK)
        errx(1, "init.tcl failed: %s", Tcl_GetStringResult(Interp));
    if (Tcl_CreateObjCommand(Interp, "napms", pr_napms, (ClientData) NULL,
                             (Tcl_CmdDeleteProc *) NULL) == NULL)
        errx(1, "Tcl_CreateObjCommand failed");
}
