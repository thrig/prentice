# init.tcl - this runs before ncurses is setup and sets up most of
# the game

package require Tcl 8.6
package require sqlite3 3.23.0
namespace path ::tcl::mathop
sqlite3 ecs :memory: -create true -nomutex true

# keymap cmd_movekey input (decimal, from ascii(7)) to deltax/deltay
# values to move the entity around (there used to be a cost to make
# diagonals more expensive, but that in turn makes moves more difficult
# to reason about and too different from other roguelikes)
set keymoves [dict create \
  104 {-1 0} 106 {0 1} 107 {0 -1} 108 {1 0} \
  121 {-1 -1} 117 {1 -1} 98 {-1 1} 110 {1 1}]

set movenumber 0

# so the Apprentice (who doubtless self-styles the Hero) can be drawn
# on top of everything else, or that items are not drawn under the
# floor, etc
array set zlevel {floor 0 feature 1 item 10 monst 100 hero 1000}

# xmin,ymin,xmax,ymax dimensions of the "level map" (there is no such
# thing (over here in the database or TCL))
variable boundary

# interaction with a door
proc act_door {entv depth oldx oldy newx newy cost destid} {
    global ecs
    set ch [ecs eval {SELECT ch FROM disp WHERE entid=$destid}]
    if {$ch eq "+"} {
        set ch '
        ecs eval {UPDATE disp SET ch=$ch WHERE entid=$destid}
        ecs eval {UPDATE pos SET dirty=TRUE WHERE entid=$destid}
        unset_system $destid opaque
        uplevel $depth "if {\$new_energy < $cost} {set new_energy $cost}"
    } else {
        upvar $depth $entv ent
        move_ent $ent(entid) [+ $depth 1] $oldx $oldy $newx $newy $cost
    }
    return -code break
}

# interaction with another entity (hey it's a roguelike)
proc act_fight {entv depth oldx oldy newx newy cost destid} {
    # where is HP getting put--prolly table?
    warn "TODO fight with $destid"
    return -code continue
}

proc act_nope {entv depth oldx oldy newx newy cost destid} {
    return -code continue
}

proc act_okay {entv depth oldx oldy newx newy cost destid} {
    upvar $depth $entv ent
    move_ent $ent(entid) [+ $depth 1] $oldx $oldy $newx $newy $cost
    return -code break
}

# move the cursor somewhere
proc at {x y} {return \033\[$y\;${x}H}

# move the cursor somewhere in the map (at an offset to the origin)
proc at_map {x y} {return \033\[[+ 2 $y]\;[+ 2 $x]H}

# TODO or instead control+dir to interact without moving?
# or instead brogue doors (rogue don't have door interact)
proc cmd_close {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    set xy [get_direction]
    # ...
}

proc cmd_commands {entv depth ch} {
    global ecs
    # TODO instead post message or bring up a reader screen
    ecs eval {SELECT key,desc FROM keymap ORDER BY key} kmap {
        warn "[format %c $kmap(key)] - $kmap(desc)"
    }
}

# move something in response to keyboard input
proc cmd_movekey {entv depth ch} {
    global boundary ecs keymoves
    upvar $depth $entv ent
    set xy [dict get $keymoves $ch]
    ecs eval {SELECT x,y FROM pos WHERE entid=$ent(entid)} pos {
        set newx [+ $pos(x) [lindex $xy 0]]
        set newy [+ $pos(y) [lindex $xy 1]]

        if {![<= [lindex $boundary 0] $newx [lindex $boundary 2]] ||
            ![<= [lindex $boundary 1] $newy [lindex $boundary 3]]} {
            return -code continue
        }

        if {[move_blocked $entv [+ $depth 1] $newx $newy]} {
            ecs eval {
              SELECT entid,interact FROM pos INNER JOIN disp USING (entid)
              WHERE x=$newx AND y=$newy ORDER BY zlevel DESC LIMIT 1
            } dest {
                tailcall $dest(interact) $entv $depth \
                  $pos(x) $pos(y) $newx $newy 10 $dest(entid)
            }
            warn "blocked but did not interact with anything at $newx $newy"
            return -code continue
        } else {
            move_ent $ent(entid) [+ $depth 1] $pos(x) $pos(y) $newx $newy 10
            return -code break
        }
    }
}

# TODO or instead control+dir to interact without moving?
proc cmd_open {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    set xy [get_direction]
    # ...
}

proc cmd_pass {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    uplevel $depth {if {$new_energy < 10} {set new_energy 10}}
    return -code break
}

proc cmd_quit {entv depth ch} {exit 1}

# a "do nothing" command that consumes no energy
proc cmd_version {entv depth ch} {
    warn "version 42"
    return -code continue
}

proc get_direction {} {
    global keymoves
    while 1 {
        set ch [getch]
        if {$ch == 27} {return -code return}
        if {[dict exists $keymoves $ch]} {break}
    }
    return [dict get $keymoves $ch]
}

proc init_map {} {
    global ecs boundary
    initmap $boundary \
      [ecs eval {
          SELECT x,y,ch,max(zlevel) FROM pos
          INNER JOIN disp USING (entid) GROUP BY x,y
      }] \
      [ecs eval {
          SELECT DISTINCT x,y FROM POS WHERE entid IN
          (SELECT entid FROM systems WHERE system='opaque')
      }]
}

# get a key and do something with it (for any random entity that
# needs that)
proc keyboard {entv depth} {
    global ecs
    upvar $depth $entv ent
    update_map $entv [+ $depth 1]
    while 1 {
        while 1 {
            set ch [getch]
            set cmd [ecs onecolumn {SELECT cmd FROM keymap WHERE key=$ch}]
            if {$cmd ne ""} {break}
            warn "$ent(entid) unmapped key $ch"
        }
        $cmd $entv [+ $depth 1] $ch
    }
}

# Marxist tendencies
proc leftmover {entv depth} {
    global boundary ecs
    upvar $depth $entv ent
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
        }
    }
    # always costs energy as it tried (and maybe failed) to move
    uplevel $depth {if {$new_energy < 10} {set new_energy 10}}
}

proc load_db {{file game.db}} {global ecs; ecs restore $file}

proc load_or_make_db {file} {
    if {[string length $file]} {
        warn "load from $file"
        load_db $file
        ecs eval {UPDATE pos SET dirty=TRUE}
        ecs cache size 100
    } else {
        global zlevel
        make_db
        ecs cache size 100

        make_ent "la vudvri" 0 1 @ $zlevel(hero) act_fight \
          energy keyboard solid

        make_ent "la nanmu poi terpa lo ke'a xirma" 1 1 & \
          $zlevel(monst) act_fight energy leftmover solid

        make_ent "a wild vorme" 3 4 + \
          $zlevel(feature) act_door solid opaque

        set wall [make_massent "bitmu" # $zlevel(feature) solid opaque]
        set_pos $wall 2 4 act_nope
        set_pos $wall 4 4 act_nope
        set_pos $wall 2 5 act_nope
        set_pos $wall 4 5 act_nope
        set_pos $wall 2 6 act_nope
        set_pos $wall 3 6 act_nope
        set_pos $wall 4 6 act_nope

        # this is what makes the "level map", such as it is
        set floor [make_massent "floor" . $zlevel(floor)]
        for {set y 0} {$y<10} {incr y} {
            for {set x 0} {$x<10} {incr x} {
                set_pos $floor $x $y act_okay
            }
        }
    }
    set_boundaries
    init_map
}

# this here is the database schema
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
              ch INTEGER,
              zlevel INTEGER,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        # where the entity is on the level map (and what happens when it
        # is interacted with)
        ecs eval {
            CREATE TABLE pos (
              entid INTEGER NOT NULL,
              x INTEGER,
              y INTEGER,
              interact TEXT,
              dirty BOOLEAN DEFAULT TRUE,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        ecs eval {CREATE INDEX pos2dirty ON pos(dirty)}
        ecs eval {CREATE INDEX pos2x ON pos(x)}
        ecs eval {CREATE INDEX pos2y ON pos(y)}
        # systems an entity has (probably should be called component)
        ecs eval {
            CREATE TABLE systems (
              entid INTEGER NOT NULL,
              system TEXT NOT NULL,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        ecs eval {CREATE INDEX systems2system ON systems(system)}
        ecs eval {
            CREATE TABLE keymap (
              key INTEGER NOT NULL,
              cmd TEXT NOT NULL,
              desc TEXT
            )
        }
        # ascii(7) decimal values (and maybe some numbers invented by
        # ncurses) plus a proc to call for the given key
        ecs eval {INSERT INTO keymap VALUES(46,'cmd_pass','skip a turn')}
        ecs eval {INSERT INTO keymap VALUES(63,'cmd_commands','show commands')}
        ecs eval {INSERT INTO keymap VALUES(67,'cmd_close','close something')}
        ecs eval {INSERT INTO keymap VALUES(79,'cmd_open','open something')}
        ecs eval {INSERT INTO keymap VALUES(104,'cmd_movekey','move west')}
        ecs eval {INSERT INTO keymap VALUES(106,'cmd_movekey','move south')}
        ecs eval {INSERT INTO keymap VALUES(107,'cmd_movekey','move north')}
        ecs eval {INSERT INTO keymap VALUES(108,'cmd_movekey','move east')}
        ecs eval {INSERT INTO keymap VALUES(121,'cmd_movekey','move north-west')}
        ecs eval {INSERT INTO keymap VALUES(117,'cmd_movekey','move north-east')}
        ecs eval {INSERT INTO keymap VALUES(98,'cmd_movekey','move south-west')}
        ecs eval {INSERT INTO keymap VALUES(110,'cmd_movekey','move south-east')}
        ecs eval {INSERT INTO keymap VALUES(118,'cmd_version','show version')}
        ecs eval {INSERT INTO keymap VALUES(113,'cmd_quit','quit the game')}
        #ecs eval {INSERT INTO keymap VALUES(410,'sig_winch','SIGWINCH')}
    }
}

# entity -- something that can be displayed and has a position and
# probably has some number of systems (that, again, probably should be
# called components)
proc make_ent {name x y ch zlevel interact args} {
    global ecs
    set ch [scan $ch %c]
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_pos $entid $x $y $interact
        set_disp $entid $ch $zlevel
        foreach sys $args {set_system $entid $sys}
    }
    return $entid
}

# something that can exist at multiple points such as floor or
# wall tiles
proc make_massent {name ch zlevel args} {
    global ecs
    set ch [scan $ch %c]
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_disp $entid $ch $zlevel
        foreach sys $args {set_system $entid $sys}
    }
    return $entid
}

# solid things cannot be in the same square
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

proc move_ent {id depth oldx oldy newx newy cost} {
    global ecs
    ecs eval {UPDATE pos SET x=$newx,y=$newy WHERE entid=$id}
    ecs eval {
        UPDATE pos SET dirty=TRUE
        WHERE (x=$oldx AND y=$oldy) OR (x=$newx AND y=$newy)
    }
    uplevel $depth "if {\$new_energy < $cost} {set new_energy $cost}"
}

proc save_db {{file game.db}} {global ecs; ecs backup $file}

proc set_boundaries {} {
    global boundary ecs
    ecs eval {
        SELECT min(x) as x1,min(y) as y1,max(x) as x2,max(y) as y2 FROM pos
    } pos {
        set boundary [list $pos(x1) $pos(y1) $pos(x2) $pos(y2)]
    }
}

proc set_disp {ent ch zlevel} {
    global ecs
    ecs eval {INSERT INTO disp VALUES($ent, $ch, $zlevel)}
}

proc set_pos {ent x y act} {
    global ecs
    ecs eval {INSERT INTO pos(entid,x,y,interact) VALUES($ent,$x,$y,$act)}
}

proc set_system {ent sname} {
    global ecs
    ecs eval {INSERT INTO systems VALUES($ent, $sname)}
}

# TODO instead needs to be over in C
#proc show_movenumber {entv depth} {
#    global movenumber
#    upvar $depth $entv ent
#    puts -nonewline stdout \
#      "[at 1 1]\033\[Kmove $movenumber entity - $ent(name)"
#    incr movenumber
#}

proc unset_system {ent sname} {
    global ecs
    ecs eval {DELETE FROM systems WHERE entid=$ent AND system=$sname}
}

proc update_ent {entv depth} {
    global ecs
    upvar $depth $entv ent
    #show_movenumber $entv [+ $depth 1]
    # NOTE may need a more specific ordering than alphabetic sort on
    # system name such that environmental effects (wind blowing things
    # left) happens at a specific time in the sequence of systems
    ecs eval {
        SELECT system FROM systems WHERE entid=$ent(entid) ORDER BY system
    } sys {
        # NOTE "keyboard" system requires that they have a position
        # (and maybe also display) but there's no actual constraint
        # enforcing that in the database
        switch $sys(system) {
            keyboard -
            leftmover {$sys(system) $entv [+ $depth 1]}
        }
    }
}

proc update_map {entv depth} {
    global ecs
    upvar $depth $entv ent
    ecs transaction {
        # index    0     1 2 3  4
        set dirty [ecs eval {
            SELECT entid,x,y,ch,max(zlevel)
            FROM pos INNER JOIN disp USING (entid)
            WHERE dirty=TRUE GROUP BY x,y ORDER BY y,x
        }]
        set len [llength $dirty]
        for {set i 0} {$i < $len} {incr i 5} {
            set x [lindex $dirty [+ $i 1]]
            set y [lindex $dirty [+ $i 2]]
            # max(zlevel) unused so insert the is-opaque? value there
            lset dirty [+ $i 4] [ecs eval {
                SELECT COUNT(*) FROM systems
                WHERE system='opaque' AND entid
                IN (SELECT entid FROM pos WHERE x=$x AND y=$y)
            }]
        }
        set position [ecs eval {SELECT x,y FROM pos WHERE entid=$ent(entid)}]
        refreshmap $position $dirty 5
        ecs eval {UPDATE pos SET dirty=FALSE WHERE dirty=TRUE}
    }
}

# the main game loop - a simple integer-based energy system: entity with
# the lowest value moves, and that value is whacked off of the energy
# value of every other entity. depending on their action, a new energy
# value is assigned. no ordering is attempted when two things move at
# the same time
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
                update_ent ent 1
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

proc warn {msg} {puts stderr $msg}

load_or_make_db $dbfile

# offline copy so I can poke around with `sqlite3 game.db`
if {![string length $dbfile]} {save_db}
