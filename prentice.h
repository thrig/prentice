#ifndef _H_PRENTICE_H_
#define _H_PRENTICE_H_

#include <assert.h>
#include <ctype.h>
#include <err.h>
#include <errno.h>
#include <getopt.h>
#include <locale.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <termios.h>
#include <unistd.h>

#include <ncurses.h>
#include <tcl.h>

#include "jsf.h"

#define NEED_ROWS 24
#define NEED_COLS 80

#define PAINT_WHITE COLOR_PAIR(1)
#define PAINT_RED COLOR_PAIR(2)
#define PAINT_YELLOW COLOR_PAIR(3)
#define PAINT_BLACK COLOR_PAIR(4)
#define PAINT_GREEN COLOR_PAIR(5)

#define MAX_FOV_RADIUS 7 // for digital FOV alloc
// size of the map view
#define VIEW_SIZE_X 11
#define VIEW_SIZE_Y 11
#define VIEW_OFFSET_X VIEW_SIZE_X / 2
#define VIEW_OFFSET_Y VIEW_SIZE_Y / 2

#ifndef oom
#define oom() fatal("out of memory: %s\n", strerror(errno))
#endif

extern Tcl_Interp *Interp;

// bind a TCL command name to a C fn
#define LINK_COMMAND(name, fn)                                                 \
    if (Tcl_CreateObjCommand(Interp, name, fn, (ClientData) NULL,              \
                             (Tcl_CmdDeleteProc *) NULL) == NULL)              \
    errx(1, "Tcl_CreateObjCommand failed")

// jsf.c
void setup_jsf(void);

// main.c
void fatal(const char *const fmt, ...);

// map.c
void setup_map(void);

// messages.c
void setup_messages(void);

#endif
