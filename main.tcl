# main.tcl - main game loop, not safe to die from this without cleanups

refresh_map

while 1 {
    leftmovers
    update_map
    napms 100
}
