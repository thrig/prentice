/* prentice - apprentice wizard roguelike */

#include "prentice.h"

#include <tcl.h>

Tcl_Interp *Interp;
Tcl_Obj *Script;

static void emit_help(void);

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

    if ((Interp = Tcl_CreateInterp()) == NULL)
        errx(EX_OSERR, "Tcl_CreateInterp failed");
    if (Tcl_Init(Interp) == TCL_ERROR)
        errx(EX_OSERR, "Tcl_Init failed");
    if (Tcl_EvalFile(Interp, "main.tcl") != TCL_OK)
        errx(1, "Tcl_EvalFile failed: %s", Tcl_GetStringResult(Interp));

    atexit(cleanup);

    initscr();
    cbreak();
    noecho();
    nonl();
#ifdef WITHKEYPAD
    keypad(stdscr, TRUE);
#endif
    clearok(stdscr, TRUE);

// TODO stderr to logfile esp during devels... just run it with 2>...
// TODO signal handling (auto-save if whacked with fatal sig)

// okay so a bit stuck here as will likely need to call into various
// tcl funcs as part of game loop but head out to C for getch() when
// the player needs to mash keys

// getting "leftmover" system working critical as that will get basic
// game loop, a system, and hash out how the update stuff will happen
// (dirty flag, or ...?)

// energy system via database, or just one-turn for each thing?

    return 0;
}

void cleanup(void)
{
    curs_set(TRUE);
    endwin();
}

inline static void emit_help(void)
{
    fputs("Usage: prentice TODO", stderr);
    exit(EX_USAGE);
}
