# main.tcl - main game loop, not safe to die from this without cleanups

refresh_map

# not very interesting at this point, but does show how an ECS could be
# built around sqlite
while 1 {
    energy
    #leftmovers
    update_map
    #napms 100
}
