# init.tcl - initialization that happens prior to terminal being placed
# into raw mode so it is okay to die without cleanups

package require Tcl 8.5
package require sqlite3 3.23.0
sqlite3 ecs :memory: -create true -nomutex true

proc warn {msg} {puts stderr $msg}

# http://invisible-island.net/xterm/
# TODO these are not used
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
        set_habit $entid keyboard
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
        # systems that must be called when the entity moves
        ecs eval {
            CREATE TABLE habits (
              entid INTEGER NOT NULL,
              system TEXT NOT NULL,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
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
        puts stderr "load from $file"
        load_db $file
        ecs cache size 100
    } else {
        global colors zlevel
        make_db
        ecs cache size 100

        # create two entities, "Hero" and "Man Afraid of His Horse"
        make_ent "la vudvri" 0 0 @ \
          $colors(white) $colors(black) $zlevel(hero) energy
        make_ent "la nanmu poi terpa lo ke'a xirma" 1 1 & \
          $colors(white) $colors(black) $zlevel(hero) energy

        # this is what makes the "world map" such as it is
        set floor \
          [make_massent "floor" . $colors(white) $colors(black) $zlevel(floor)]
        for {set y 0} {$y<10} {incr y} {
            for {set x 0} {$x<10} {incr x} {
                set_pos $floor $x $y
            }
        }
    }
}

proc set_disp {ent ch fg bg {zlevel 0}} {
    global ecs
    # KLUGE convert internally to what need for terminal display
    # TODO not actually used yet
    # http://invisible-island.net/xterm/
    incr fg 30
    incr bg 40
    ecs eval {INSERT INTO disp VALUES($ent, $ch, $fg, $bg, $zlevel)}
}
proc set_habit {ent sname} {
    global ecs
    ecs eval {INSERT INTO habits VALUES($ent, $sname)}
}
proc set_system {ent sname} {
    global ecs
    ecs eval {INSERT INTO systems VALUES($ent, $sname)}
}
# TODO probably should set the dirty flag
proc set_pos {ent x y} {
    global ecs
    ecs eval {INSERT INTO pos(entid, x, y) VALUES($ent, $x, $y)}
}
proc unset_habit {ent sname} {
    global ecs
    ecs eval {DELETE FROM habits WHERE entid=$ent AND system=$sname}
}
proc unset_system {ent sname} {
    global ecs
    ecs eval {DELETE FROM systems WHERE entid=$ent AND system=$sname}
}

# redraw the entire map from scratch NOTE this assumes that the "map" is
# contiguous in the database table so that a string can be built up then
# thrown to be displayed by the terminal by just printing it
proc refresh_map {} {
    global ecs
    set s [at_map 0 0]
    set rowy 0
    ecs transaction {
        ecs eval {SELECT x, y, ch, fg, bg, max(zlevel) FROM pos INNER JOIN disp USING (entid) GROUP BY x,y ORDER BY y,x} ent {
            if {$ent(y) > $rowy} {
                incr rowy
                append s [at_map 0 $rowy]
            }
            append s $ent(ch)
        }
    }
    puts -nonewline stdout $s
}

# update only dirty portions of the map
proc update_map {} {
    global ecs
    set s {}
    ecs transaction {
        ecs eval {SELECT x, y, ch, fg, bg, max(zlevel) FROM pos INNER JOIN disp USING (entid) WHERE dirty=TRUE GROUP BY x,y} ent {
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

# simple integer-based energy system, entity with the lowest value
# moves, and that value is whacked off of the energy value of every
# other entity. depending on their action, a new energy value is
# assigned TODO status effects "slow" may need to modify the new_energy
# returned by some other habit so may need list to act on, or slow gets
# applied somewhere else?
proc energy {} {
    global ecs
    ecs transaction {
        set min [ecs eval {SELECT min(energy) FROM ents LIMIT 1}]
        ecs eval {SELECT * FROM systems INNER JOIN ents USING (entid) WHERE system='energy'} ent {
            set new_energy [expr $ent(energy) - $min]
            if {$new_energy <= 0} {
                set new_energy [update_animate ent]
            }
            if {$new_energy <= 0} {error "energy must be positive integer"}
            ecs eval {UPDATE ents SET energy=$new_energy WHERE entid=$ent(entid)}
        }
    }
}

proc update_animate {entv} {
    global ecs
    set new_energy 10
    upvar 1 $entv ent
    ecs eval {SELECT system FROM habits WHERE entid=$ent(entid)} habit {
        # a downside is you can't just pass around a function pointer to
        # call so with lots of "habits" (TODO better name) will end up
        # with a huge switch list
        switch $habit(system) {
            keyboard {
                set ch [getch]
                warn "$ent(entid) $ent(name) - key $ch"
                # TODO translate keys into directions, handle
                # interactions with the destination cell (or disallow at
                # edge of map), update position of ent
                # return different energy cost for sq vs diagonal moves
                # to at least try to be Euclidean
            }
        }
    }
    return $new_energy
}

# find things with the "leftmover" system associated and move them left
# (and mark both them and where they came from as dirty)
proc leftmovers {} {
    ecs transaction {
        ecs eval {SELECT * FROM systems INNER JOIN pos USING (entid) WHERE system='leftmover' ORDER BY x ASC} ent {
            set newx [expr $ent(x) <= 0 ? 9 : $ent(x) - 1]
            ecs eval {UPDATE pos SET x=$newx,dirty=TRUE WHERE entid=$ent(entid)}
            ecs eval {UPDATE pos SET dirty=TRUE WHERE x=$ent(x) AND y=$ent(y)}
        }
    }
}

# then see main.tcl for the main game loop (such as it is)
