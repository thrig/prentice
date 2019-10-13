PRENTICE ?= prentice

# for OpenBSD ports; Mac OS X with MacPorts will instead need
#   make rdcomm TCL=tcl
TCL    ?= tcl85
PRLIBS ?= -lncurses `pkg-config --libs $(TCL)`
CFLAGS += -std=c99 -O2 -Wall -pedantic -pipe
OBJS    = main.o

$(PRENTICE): $(OBJS)
	$(CC) $(CFLAGS) $(PRLIBS) $(OBJS) -o $(PRENTICE)

main.o: main.c prentice.h
	$(CC) $(CFLAGS) `pkg-config --cflags $(TCL)` -c main.c -o main.o

clean:
	-rm *.o *.core $(PRENTICE)

depend:
	pkg-config --exists $(TCL)

.PHONY: clean depend
