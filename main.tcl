package require Tcl 8.5
package require sqlite3 3.23.0
sqlite3 ecs :memory: -create true -nomutex true

# http://invisible-island.net/xterm/
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
proc at {x y} {
    append ret \033 \[ $y \; $x H
    return $ret
}
proc at_map {x y} {
    append ret \033 \[ [expr 2 + $y] \; [expr 2 + $x] H
    return $ret
}
# TODO these probably faster with inline code over in C
set alt_screen \033\[1049h
set clear_screen \033\[1\;1H\033\[2J
set clear_right \033\[K
set hide_cursor \033\[?25l
set hide_pointer \033\[>3p
set show_cursor \033\[?25h
set term_norm \033\[m
set unalt_screen \033\[?1049l

array set zlevel {
    floor 1
    item  10
    monst 100
    hero  1000
}

# entity -- something that can be displayed and has a position
# TODO will probably also need to tie into energy system
# TODO may need something similar for invisible things that are
# at a point but not displayed...
proc make_ent {name x y ch fg bg zlevel} {
    global ecs
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_pos $entid $x $y
        set_disp $entid $ch $fg $bg $zlevel
        # TODO then maybe list systems they get added to via "args"
    }
    return $entid
}

# something that can exist at multiple points, like floor or walls
proc make_massent {name ch fg bg zlevel} {
    global ecs
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_disp $entid $ch $fg $bg $zlevel
        # TODO then maybe list systems they get added to via "args"
        # (less likely than for other things, unless walls get a
        # "blocking" system?)
    }
    return $entid
}

proc load_db {{file game.db}} {global ecs; ecs restore $file}
proc save_db {{file game.db}} {global ecs; ecs backup $file}
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
        # TODO may need global hero as I suspect a bunch of systems will
        # want to get at that
        ecs cache size 10
    } else {
        global colors zlevel
        make_db
        # TODO tune this to a little above the number of queries end up
        # with as TCL appears to do automatic query caching (default 10
        # max 100)
        ecs cache size 10
        make_ent "la vudvri" 0 0 @ $colors(white) $colors(black) $zlevel(hero)
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
    ecs eval {INSERT INTO pos VALUES($ent, $x, $y)}
}
proc unset_system {ent sname} {
    global ecs
    ecs eval {DELETE FROM systems WHERE entid=$ent AND system=$sname}
}

proc refresh_map {} {
    global ecs
    set s [at_map 0 0]
    set rowy 0
    ecs eval {SELECT x, y, ch, fg, bg, max(zlevel) FROM pos INNER JOIN disp USING (entid) GROUP BY x,y ORDER BY y,x} ent {
        if {$ent(y) > $rowy} {
            incr rowy
            append s [at_map 0 $rowy]
        }
        append s $ent(ch)
    }
    puts -nonewline stdout $s
}
# TODO may instead have "dirty" flag so update system can figure out
# what needs drawing, in addition to the whole board thing...maybe mtime
# field in tables and then select pos where mtime > last, if can make
# that a sub-second resolution field. or a global turn counter or current
# level of the energy system?
proc update_pos {x y} {
    global ecs
    ecs eval {SELECT x, y, ch, fg, bg, max(zlevel) FROM pos INNER JOIN disp USING (entid) WHERE x=$x AND y=$y GROUP BY x,y} ent {
        # TODO instead draw ch/fg/bg at x/y
        #parray ent
    }
}

load_or_make_db {} ;#[lindex $argv 0] TODO regain option for this
save_db         ;# so I can poke around with `sqlite3`

fconfigure stdout -buffering none
puts -nonewline stdout "$alt_screen$clear_screen$hide_cursor"

refresh_map

puts -nonewline stdout "$unalt_screen$show_cursor"
