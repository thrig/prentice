# init.tcl - initialization that happens prior to terminal being placed
# into raw mode so it is okay to die without cleanups
#
# TODO it's a bit messy and needs some cleanup

package require Tcl 8.5
package require sqlite3 3.23.0
sqlite3 ecs :memory: -create true -nomutex true

proc warn {msg} {puts stderr $msg}

# xmin,ymin,xmax,ymax dimensions of the "level map" (there is actually
# no such thing)
variable boundary

# ASCII (and maybe some numbers invented by ncurses) to a proc to call
set commands [dict create \
   46 move_pass \
  104 move_bykey 106 move_bykey 107 move_bykey 108 move_bykey \
  121 move_bykey 117 move_bykey 98 move_bykey 110 move_bykey \
  118 pr_version \
  113 do_quit \
]
# 410 sig_winch \

# rogue direction keys to x,y,cost values (yes diagonal moves cost more
# damnit this is a (more) Euclidean game than some roguelikes)
set keymoves [dict create \
  104 {-1 0 10} 106 {0 1 10} 107 {0 -1 10} 108 {1 0 10} \
  121 {-1 -1 14} 117 {1 -1 14} 98 {-1 1 14} 110 {1 1 14} \
]

# http://invisible-island.net/xterm/
# TODO these are not (yet?) used
array set colors {
    black   0
    red     1
    green   2
    yellow  3
    blue    4
    magenta 5
    cyan    6
    white   7
}
# move the cursor somewhere
proc at {x y} {
    append ret \033 \[ $y \; $x H
    return $ret
}
# move the cursor somewhere in the map (which may be at an offset to
# the origin)
proc at_map {x y} {
    append ret \033 \[ [expr 2 + $y] \; [expr 2 + $x] H
    return $ret
}

# so the Hero can be drawn on top of anything else in the cell, or that
# items are not drawn under floor tiles, etc
array set zlevel {
    floor 1
    item  10
    monst 100
    hero  1000
}

# entity -- something that can be displayed and has a position and maybe
# has some number of systems associated with it
# "habits" got stuck on to try to wire things up to an energy system
proc make_ent {name x y ch fg bg zlevel args} {
    global ecs
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_pos $entid $x $y
        set_disp $entid $ch $fg $bg $zlevel
        foreach sys $args {set_system $entid $sys}
    }
    return $entid
}

# something that can exist at multiple points such as floor or
# wall tiles
proc make_massent {name ch fg bg zlevel args} {
    global ecs
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_disp $entid $ch $fg $bg $zlevel
        foreach sys $args {set_system $entid $sys}
    }
    return $entid
}

# serialization support is pretty easy
proc load_db {{file game.db}} {global ecs; ecs restore $file}
proc save_db {{file game.db}} {global ecs; ecs backup $file}

# build new database from scratch -- this here is the database schema
# TODO need CREATE INDEX on various things
proc make_db {} {
    global ecs
    ecs cache size 0
    ecs transaction {
        ecs eval {PRAGMA foreign_keys = ON}
        # entity - a name for easy ID plus some metadata
        ecs eval {
            CREATE TABLE ents (
              entid INTEGER PRIMARY KEY NOT NULL,
              name TEXT,
              energy INTEGER DEFAULT 10,
              alive BOOLEAN DEFAULT TRUE
            )
        };
        # what an entity that can be displayed looks like
        ecs eval {
            CREATE TABLE disp (
              entid INTEGER NOT NULL,
              ch TEXT,
              fg INTEGER,
              bg INTEGER,
              zlevel INTEGER,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        };
        # where the entity is on the level map
        ecs eval {
            CREATE TABLE pos (
              entid INTEGER NOT NULL,
              x INTEGER,
              y INTEGER,
              dirty BOOLEAN DEFAULT FALSE,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        };
        # what systems an entity belongs to
        ecs eval {
            CREATE TABLE systems (
              entid INTEGER NOT NULL,
              system TEXT NOT NULL,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
    }
}
proc load_or_make_db {{file}} {
    if {[string length $file]} {
        warn "load from $file"
        load_db $file
        ecs eval {UPDATE pos SET dirty=TRUE}
        ecs cache size 100
    } else {
        global colors zlevel
        make_db
        ecs cache size 100

        # create two entities, "Hero" and "Man Afraid of His Horse"
        #
        # NOTE that the leftmover could also be hooked up to keyboard
        # input...
        make_ent "la vudvri" 0 0 @ \
          $colors(white) $colors(black) $zlevel(hero) energy keyboard
        make_ent "la nanmu poi terpa lo ke'a xirma" 1 1 & \
          $colors(white) $colors(black) $zlevel(hero) energy leftmover

        # this is what makes the "world map" such as it is
        set floor \
          [make_massent "floor" . $colors(white) $colors(black) $zlevel(floor)]
        for {set y 0} {$y<10} {incr y} {
            for {set x 0} {$x<10} {incr x} {
                set_pos $floor $x $y
            }
        }
    }
    set_boundaries
}

proc set_boundaries {} {
    global ecs boundary
    ecs eval {SELECT min(x) as x1,min(y) as y1,max(x) as x2,max(y) as y2 FROM pos} pos {
        set boundary [list $pos(x1) $pos(y1) $pos(x2) $pos(y2)]
    }
}

proc set_disp {ent ch fg bg {zlevel 0}} {
    global ecs
    # KLUGE convert internally to what need for terminal display
    # TODO not (yet?) actually used yet
    # http://invisible-island.net/xterm/
    incr fg 30
    incr bg 40
    ecs eval {INSERT INTO disp VALUES($ent, $ch, $fg, $bg, $zlevel)}
}
proc set_system {ent sname} {
    global ecs
    ecs eval {INSERT INTO systems VALUES($ent, $sname)}
}
proc set_pos {ent x y} {
    global ecs
    ecs eval {INSERT INTO pos(entid,x,y,dirty) VALUES($ent,$x,$y,TRUE)}
}
proc unset_system {ent sname} {
    global ecs
    ecs eval {DELETE FROM systems WHERE entid=$ent AND system=$sname}
}

proc update_map {} {
    global ecs
    set s {}
    ecs transaction {
        ecs eval {SELECT x, y, ch, fg, bg, max(zlevel) FROM pos INNER JOIN disp USING (entid) WHERE dirty=TRUE GROUP BY x,y ORDER BY y,x} ent {
            append s [at_map $ent(x) $ent(y)] $ent(ch)
        }
        ecs eval {UPDATE pos SET dirty=FALSE WHERE dirty=TRUE}
    }
    if {[string length $s]} {puts -nonewline stdout $s}
}

load_or_make_db $dbfile
# offline copy so I can poke around with `sqlite3 game.db`
if {![string length $dbfile]} {save_db}

fconfigure stdout -buffering none

# simple integer-based energy system: entity with the lowest value
# moves, and that value is whacked off of the energy value of every
# other entity. depending on their action, a new energy value is
# assigned. no ordering is attempted when two things move at the
# same time
proc energy {} {
    global ecs
    set min [ecs eval {SELECT min(energy) FROM ents LIMIT 1}]
    ecs eval {SELECT * FROM systems INNER JOIN ents USING (entid) WHERE system='energy'} ent {
        ecs transaction {
            set new_energy [expr $ent(energy) - $min]
            if {$new_energy <= 0} {update_animate ent 1}
            if {$new_energy <= 0} {error "energy must be positive integer"}
            ecs eval {UPDATE ents SET energy=$new_energy WHERE entid=$ent(entid)}
        }
        update_map
    }
}

#proc sig_winch {entv depth ch} {
#    ecs eval {UPDATE pos SET dirty=TRUE}
#    # TODO complain if screen is too small... also this blanks out the
#    # screen; probably need a refresh() over on the C side of things.
#    # let's just disable WINCH for now
#    update_map
#    return -code continue
#}

proc update_animate {entv depth} {
    global commands ecs
    upvar $depth $entv ent
    ecs eval {SELECT system FROM systems WHERE entid=$ent(entid)} sys {
        # NOTE "keyboard" habit requires that they have a position
        # (maybe also display) but there's no actual constraint
        # enforcing that
        switch $sys(system) {
            keyboard { keyboard $entv [expr $depth + 1] $commands }
            leftmover { leftmover $entv [expr $depth + 1] }
        }
    }
}

proc do_quit {entv depth ch} {error success}

# a "do nothing" command that consumes no energy; use this for "look
# around level map" or "look at inventory" if those are free moves for
# the player
proc pr_version {entv depth ch} {
    warn "version 42"
    return -code continue
}

proc move_bykey {entv depth ch} {
    global boundary ecs keymoves
    upvar $depth $entv ent
    set xycost [dict get $keymoves $ch]
    warn "move_bykey $ent(entid) ch=$ch $xycost"
    ecs eval {SELECT x,y FROM pos WHERE entid=$ent(entid)} pos {
        set newx [expr $pos(x) + [lindex $xycost 0]]
        set newy [expr $pos(y) + [lindex $xycost 1]]
        if {[::tcl::mathop::<= [lindex $boundary 0] $newx [lindex $boundary 2]] && [::tcl::mathop::<= [lindex $boundary 1] $newy [lindex $boundary 3]]} {
            ecs eval {UPDATE pos SET x=$newx,y=$newy,dirty=TRUE WHERE entid=$ent(entid)}
            ecs eval {UPDATE pos SET dirty=TRUE WHERE x=$pos(x) AND y=$pos(y)}
        } else {
            return -code continue
        }
    }
    set cost [lindex $xycost 2]
    uplevel $depth "if {\$new_energy < $cost} {set new_energy $cost}"
    return -code break
}

proc move_pass {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    uplevel $depth {if {$new_energy < 10} {set new_energy 10}}
    return -code break
}

# get a key from somewhere and so something with it
proc keyboard {entv depth commands} {
    global ecs
    upvar $depth $entv ent
    while 1 {
        while 1 {
            set ch [getch]
            if {[dict exists $commands $ch]} {break}
            warn "$ent(entid) unhandled key $ch"
        }
        [dict get $commands $ch] $entv [expr $depth + 1] $ch
    }
}

# Marxist tendencies
proc leftmover {entv depth} {
    global boundary ecs
    upvar $depth $entv ent
    ecs eval {SELECT x,y FROM pos WHERE entid=$ent(entid)} pos {
        set newx [expr $pos(x) <= [lindex $boundary 0] ? [lindex $boundary 2] : $pos(x) - 1]
        ecs eval {UPDATE pos SET x=$newx,dirty=TRUE WHERE entid=$ent(entid)}
        ecs eval {UPDATE pos SET dirty=TRUE WHERE x=$pos(x) AND y=$pos(y)}
    }
    uplevel $depth {if {$new_energy < 10} {set new_energy 10}}
}

# then see main.tcl for the main game loop (not much to see)
