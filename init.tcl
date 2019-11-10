# init.tcl - initialization that is loaded prior to the terminal being
# placed into raw mode. the terminal is written to using escape
# sequences from http://invisible-island.net/xterm/

package require Tcl 8.6
package require sqlite3 3.23.0
namespace path ::tcl::mathop
sqlite3 ecs :memory: -create true -nomutex true

set movenumber 0

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

array set colors {
    black   0 red     1 green   2 yellow  3
    blue    4 magenta 5 cyan    6 white   7
}
# move the cursor somewhere
proc at {x y} { return \033\[$y\;${x}H }
# move the cursor somewhere in the map (which may be at an offset to
# the origin)
proc at_map {x y} { return \033\[[+ 2 $y]\;[+ 2 $x]H }

# so the Hero can be drawn on top of anything else in the cell, or that
# items are not drawn under floor tiles, etc
array set zlevel { floor 0 feature 1 item 10 monst 100 hero 1000 }

# entity -- something that can be displayed and has a position and
# probably has some number of systems associated with it. other folks
# might call these actors?
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
        }
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
        }
        # where the entity is on the level map
        ecs eval {
            CREATE TABLE pos (
              entid INTEGER NOT NULL,
              x INTEGER,
              y INTEGER,
              dirty BOOLEAN DEFAULT TRUE,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        ecs eval {CREATE INDEX pos2dirty ON pos(dirty)}
        ecs eval {CREATE INDEX pos2x ON pos(x)}
        ecs eval {CREATE INDEX pos2y ON pos(y)}
        # what systems an entity belongs to
        ecs eval {
            CREATE TABLE systems (
              entid INTEGER NOT NULL,
              system TEXT NOT NULL,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        ecs eval {CREATE INDEX systems2system ON systems(system)}
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
        make_ent "la vudvri" 0 1 @ \
          $colors(yellow) $colors(black) $zlevel(hero) energy keyboard solid

        make_ent "la nanmu poi terpa lo ke'a xirma" 1 1 & \
          $colors(yellow) $colors(black) $zlevel(monst) energy leftmover solid

        make_ent "a wild vorme" 3 4 + $colors(white) $colors(magenta) $zlevel(feature) solid

        set wall [make_massent "bitmu" # \
          $colors(white) $colors(black) $zlevel(feature) solid]
        set_pos $wall 2 4
        set_pos $wall 4 4
        set_pos $wall 2 5
        set_pos $wall 4 5
        set_pos $wall 2 6
        set_pos $wall 3 6
        set_pos $wall 4 6

        # this is what makes the "level map", such as it is
        set floor [make_massent "floor" . \
          $colors(white) $colors(black) $zlevel(floor)]
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
    ecs eval {
        SELECT min(x) as x1,min(y) as y1,max(x) as x2,max(y) as y2 FROM pos
    } pos {
        set boundary [list $pos(x1) $pos(y1) $pos(x2) $pos(y2)]
    }
}

proc set_disp {ent ch fg bg {zlevel 0}} {
    global ecs
    # KLUGE convert internally to what need for terminal display
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
    ecs eval {INSERT INTO pos(entid,x,y) VALUES($ent,$x,$y)}
}
proc unset_system {ent sname} {
    global ecs
    ecs eval {DELETE FROM systems WHERE entid=$ent AND system=$sname}
}

proc update_map {} {
    global ecs
    set s {}
    ecs transaction {
        ecs eval {
            SELECT entid, x, y, ch, fg, bg, max(zlevel) as zlevel
            FROM pos INNER JOIN disp USING (entid)
            WHERE dirty=TRUE GROUP BY x,y ORDER BY y,x
        } ent {
            append s [at_map $ent(x) $ent(y)] \
              \033\[1\; $ent(fg) \; $ent(bg) m$ent(ch) \033\[m
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
proc use_energy {} {
    global ecs
    set min [ecs eval {SELECT min(energy) FROM ents}]
    ecs eval {
        SELECT * FROM systems INNER JOIN ents USING (entid)
        WHERE system='energy'
    } ent {
        ecs transaction {
            set new_energy [- $ent(energy) $min]
            if {$new_energy <= 0} {
                update_animate ent 1
                # TODO probably here apply any in-cell status effects
            }
            if {$new_energy <= 0} {error "energy must be positive integer"}
            ecs eval {
                UPDATE ents SET energy=$new_energy WHERE entid=$ent(entid)
            }
        }
    }
    tailcall use_energy
}

proc update_animate {entv depth} {
    global commands ecs
    upvar $depth $entv ent
    show_movenumber $entv [+ $depth 1]
    # NOTE may need a more specific ordering than alphabetic sort on
    # system name such that environmental effects (wind blowing things
    # left) happens at a specific time in the sequence of systems
    ecs eval {
        SELECT system FROM systems WHERE entid=$ent(entid) ORDER BY system
    } sys {
        # NOTE "keyboard" system requires that they have a position
        # (maybe also display) but there's no actual constraint
        # enforcing that
        switch $sys(system) {
            keyboard { keyboard $entv [+ $depth 1] $commands }
            leftmover { leftmover $entv [+ $depth 1] }
        }
    }
}

proc do_quit {entv depth ch} {exit 0}

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
    ecs eval {SELECT x,y FROM pos WHERE entid=$ent(entid)} pos {
        set newx [+ $pos(x) [lindex $xycost 0]]
        set newy [+ $pos(y) [lindex $xycost 1]]

        if {![<= [lindex $boundary 0] $newx [lindex $boundary 2]] ||
            ![<= [lindex $boundary 1] $newy [lindex $boundary 3]]} {
            return -code continue
        }

        if {[move_blocked $entv [+ $depth 1] $newx $newy]} {
            tailcall \
              resolve_move $entv [+ $depth 1] $newx $newy [lindex $xycost 2]
        } else {
            ecs eval {UPDATE pos SET x=$newx,y=$newy WHERE entid=$ent(entid)}
            ecs eval {
                UPDATE pos SET dirty=TRUE
                WHERE (x=$pos(x) AND y=$pos(y)) OR (x=$newx AND y=$newy)
            }
            update_map
            set cost [lindex $xycost 2]
            uplevel $depth "if {\$new_energy < $cost} {set new_energy $cost}"
            return -code break
        }
    }
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
        [dict get $commands $ch] $entv [+ $depth 1] $ch
    }
}

# Marxist tendencies
proc leftmover {entv depth} {
    global boundary ecs
    upvar $depth $entv ent
    set ret 0
    ecs eval {SELECT x,y FROM pos WHERE entid=$ent(entid)} pos {
        set newx [expr $pos(x) <= [lindex $boundary 0] \
                     ? [lindex $boundary 2] \
                     : $pos(x) - 1]
        if {![move_blocked $entv [+ $depth 1] $newx $pos(y)]} {
            ecs eval {UPDATE pos SET x=$newx WHERE entid=$ent(entid)}
            ecs eval {
                UPDATE pos SET dirty=TRUE
                WHERE (x=$pos(x) AND y=$pos(y)) OR (x=$newx AND y=$pos(y))
            }
            update_map
            set ret 1
        }
    }
    # always costs energy as it tried (and maybe failed) to move
    uplevel $depth {if {$new_energy < 10} {set new_energy 10}}
    return $ret
}

# yes/no on whether the move is possible
proc move_blocked {entv depth newx newy} {
    global ecs
    upvar $depth $entv ent
    set this [ecs eval {
        SELECT COUNT(*) FROM systems WHERE entid=$ent(entid) AND system='solid'
    }]
    set that [ecs eval {
        SELECT COUNT(*) FROM systems INNER JOIN pos USING (entid)
        WHERE system='solid' AND x=$newx AND y=$newy
    }]
    return [expr {$this + $that > 1}]
}

proc resolve_move {entv depth newx newy cost} {
    global ecs
    upvar $depth $entv ent
    ecs eval {
        SELECT entid FROM pos INNER JOIN disp USING (entid)
        WHERE x=$newx AND y=$newy ORDER BY zlevel DESC LIMIT 1
    } ent {
        warn "bonk $ent(entid)"
        # TODO interaction between things...
    }
    # TODO must set new_energy (see move_bykey) and return continue or
    # break depending on whether interaction was soft fail or done with
    return -code continue
}

proc show_movenumber {entv depth} {
    global movenumber
    upvar $depth $entv ent
    puts -nonewline stdout \
      "[at 1 1]\033\[Kmove $movenumber entity - $ent(name)"
    incr movenumber
}

# then see main.tcl for the main game loop (not much to see)
