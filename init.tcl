# init.tcl - initialization that happens prior to terminal being placed
# into raw mode so it is okay to die without cleanups

package require Tcl 8.5
package require sqlite3 3.23.0
sqlite3 ecs :memory: -create true -nomutex true

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
        ecs eval {
            CREATE TABLE ents (
              entid INTEGER PRIMARY KEY NOT NULL,
              name TEXT,
              alive BOOLEAN DEFAULT TRUE
            )
        };
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
        load_db $file
        ecs cache size 100
    } else {
        global colors zlevel
        make_db
        ecs cache size 100

        # create two entities, "Hero" and "Man Afraid of His Horse"
        make_ent "la vudvri" 0 0 @ \
          $colors(white) $colors(black) $zlevel(hero) leftmover
        make_ent "la nanmu poi terpa lo ke'a xirma" 1 1 & \
          $colors(white) $colors(black) $zlevel(hero) leftmover

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
proc set_system {ent sname} {
    global ecs
    ecs eval {INSERT INTO systems VALUES($ent, $sname)}
}
proc set_pos {ent x y} {
    global ecs
    ecs eval {INSERT INTO pos(entid, x, y) VALUES($ent, $x, $y)}
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
    variable s
    ecs transaction {
        ecs eval {SELECT x, y, ch, fg, bg, max(zlevel) FROM pos INNER JOIN disp USING (entid) WHERE dirty=TRUE GROUP BY x,y} ent {
            append s [at_map $ent(x) $ent(y)] $ent(ch)
        }
        ecs eval {UPDATE pos SET dirty=FALSE WHERE dirty=TRUE}
    }
    puts -nonewline stdout $s
}

load_or_make_db {} ;#[lindex $argv 0] TODO regain option for this
save_db         ;# so I can poke around with `sqlite3 game.db`

fconfigure stdout -buffering none

# find things with the "leftmover" system associated and move them left
# (and mark both them and where they came from as dirty)
proc leftmovers {} {
    ecs transaction {
        ecs eval {SELECT * FROM systems INNER JOIN pos USING (entid) WHERE system='leftmover' ORDER BY x ASC} ent {
            set newx [expr $ent(x) == 0 ? 9 : $ent(x) - 1]
            ecs eval {UPDATE pos SET x=$newx,dirty=TRUE WHERE entid=$ent(entid)}
            ecs eval {UPDATE pos SET dirty=TRUE WHERE x=$ent(x) AND y=$ent(y)}
        }
    }
}

# then see main.tcl for the main game loop (such as it is)
