PRENTICE ?= prentice

# for OpenBSD 6.6 ports; Mac OS X with MacPorts should instead run
#   make prentice TCL=tcl
# and other systems may need `pkg-config --libs ncurses` or such
TCL    ?= tcl86
PRLIBS ?= -lncurses `pkg-config --libs $(TCL)`
CFLAGS += -std=c99 -O2 -Wall -pedantic -pipe `pkg-config --cflags $(TCL)`
OBJS    = digital-fov.o jsf.o main.o map.o message.o

$(PRENTICE): $(OBJS)
	$(CC) $(CFLAGS) $(PRLIBS) $(OBJS) -o $(PRENTICE)

digital-fov.o: digital-fov.c digital-fov.h
jsf.o: jsf.c jsf.h
	$(CC) $(CFLAGS) -mrdrnd -c jsf.c -o jsf.o
main.o: main.c prentice.h
map.o: map.c prentice.h
message.o: message.c prentice.h

clean:
	@-rm *.o *.core $(PRENTICE) 2>/dev/null

depend:
	@pkg-config --exists $(TCL)

.PHONY: clean depend
