/* scrolling messages */

#include "prentice.h"

WINDOW *Messages;

// related to the terminal size and size of the map view
#define VIEW_ROWS NEED_ROWS
#define VIEW_COLS 80 - (VIEW_SIZE_X + 2)

static int pr_logmsg(ClientData clientData, Tcl_Interp *interp, int objc,
                     Tcl_Obj *CONST objv[]) {
    assert(objc == 2);
    const char *msg = Tcl_GetString(objv[1]);
    assert(msg != NULL);
    static int shown = -1;
    if (shown >= VIEW_ROWS) shown = VIEW_ROWS - 1;
    if (shown > -1) mvwaddch(Messages, shown, VIEW_COLS - 1, '\n'); // scroll
    shown++;
    waddstr(Messages, msg);
    wnoutrefresh(Messages);
    doupdate();
    return TCL_OK;
}

void setup_messages(void) {
    LINK_COMMAND("logmsg", pr_logmsg);
    Messages = subwin(stdscr, VIEW_ROWS, VIEW_COLS, 0, VIEW_SIZE_X + 1);
    leaveok(Messages, TRUE);
    scrollok(Messages, TRUE);
    wsetscrreg(Messages, 0, NEED_ROWS - 1);
}
