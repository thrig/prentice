PRENTICE ?= prentice

# for OpenBSD 6.5 ports; Mac OS X with MacPorts should instead run
#   make prentice TCL=tcl
# and other systems may need `pkg-config --libs ncurses` or such
TCL    ?= tcl86
PRLIBS ?= -lncurses `pkg-config --libs $(TCL)`
CFLAGS += -std=c99 -O2 -Wall -pedantic -pipe `pkg-config --cflags $(TCL)`
OBJS    = main.o

$(PRENTICE): $(OBJS)
	@$(CC) $(CFLAGS) $(PRLIBS) $(OBJS) -o $(PRENTICE)

main.o: main.c prentice.h
	@$(CC) $(CFLAGS) -c main.c -o main.o

clean:
	@-rm *.o *.core $(PRENTICE)

depend:
	@pkg-config --exists $(TCL)

.PHONY: clean depend
