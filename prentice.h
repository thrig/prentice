#ifndef _H_PRENTICE_H_
#define _H_PRENTICE_H_

#include <err.h>
#include <curses.h>
#include <getopt.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <termios.h>
#include <unistd.h>

struct termios Original_Termios;

void cleanup(void);

#endif // _H_PRENTICE_H_
