# init.tcl - most of the game logic, with calls to C (ncurses display,
# RNG, etc) or SQLite as need be

package require Tcl 8.6
package require sqlite3 3.23.0
namespace path ::tcl::mathop
sqlite3 ecs :memory: -create true -nomutex true

# xmin,ymin,xmax,ymax,wmin,wmax dimensions of the "level map"
variable boundary

# higher values drawn in favor of lower ones in any given cell
array set zlevel {floor 0 feature 1 item 10 monst 100 ekileugor 1000}

# escape hatch, and unlike DCSS these only go down
proc act_chute {entv depth lvl oldx oldy newx newy cost destid} {
    global ecs
    upvar $depth $entv ent
    # TODO but need to see if the move is legal as something may be
    # blocking the stair
    tailcall move_ent $ent(entid) $depth \
      $lvl $oldx $oldy [+ $lvl 1] $newx $newy [* 2 $cost]
}

# should this pass in a dict? this is getting crazy long
proc act_fight {entv depth lvl oldx oldy newx newy cost destid} {
    # where is HP getting put--prolly table?
    warn "TODO fight with $destid"
    return -code continue
}

proc act_missing {entv depth lvl oldx oldy newx newy cost destid} {
    warn "you seem to be missing something"
    return -code continue
}

proc act_nope {entv depth lvl oldx oldy newx newy cost destid} {
    return -code continue
}

# action (move, really) is allowed
proc act_okay {entv depth lvl oldx oldy newx newy cost destid} {
    upvar $depth $entv ent
    tailcall move_ent $ent(entid) $depth \
      $lvl $oldx $oldy $lvl $newx $newy $cost
}

# move the cursor somewhere
proc at {x y} {return \033\[$y\;${x}H}

# move the cursor somewhere in the map (at an offset to the origin)
proc at_map {x y} {return \033\[[+ 2 $y]\;[+ 2 $x]H}

proc cmd_commands {entv depth ch} {
    global ecs
    # TODO instead post message or bring up a reader screen
    ecs eval {SELECT key,desc FROM keymap ORDER BY key} kmap {
        warn "[format %c $kmap(key)] - $kmap(desc)"
    }
}

# move something in response to keyboard input
proc cmd_movekey {entv depth ch} {
    global boundary ecs
    upvar $depth $entv ent
    set xy [ecs eval {SELECT dx,dy FROM keymoves WHERE key=$ch}]
    ecs eval {SELECT w,x,y FROM position WHERE entid=$ent(entid)} pos {
        set lvl  $pos(w)
        set newx [+ $pos(x) [lindex $xy 0]]
        set newy [+ $pos(y) [lindex $xy 1]]

        if {![<= [lindex $boundary 0] $newx [lindex $boundary 2]] ||
            ![<= [lindex $boundary 1] $newy [lindex $boundary 3]]} {
            return -code continue
        }

        if {[move_blocked $entv [+ $depth 1] $lvl $newx $newy]} {
            ecs eval {
              SELECT entid,interact FROM position
              INNER JOIN display USING (entid)
              WHERE w=$lvl AND x=$newx AND y=$newy ORDER BY zlevel DESC LIMIT 1
            } dest {
                tailcall $dest(interact) $entv $depth \
                  $lvl $pos(x) $pos(y) $newx $newy 10 $dest(entid)
            }
            warn "blocked but no interaction at $lvl,$newx,$newy"
            return -code continue
        } else {
            tailcall move_ent $ent(entid) $depth \
              $lvl $pos(x) $pos(y) $lvl $newx $newy 10
        }
    }
}

proc cmd_position {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    ecs eval {SELECT w,x,y FROM position WHERE entid=$ent(entid)} pos {
        logmsg "position $pos(w),\[$pos(x),$pos(y)]"
    }
}

# really instead should be "is there something here that matches desire
# (command key) and a suitable component so not doing hard to debug
# checks on display character types that might change
#
# also may need to differ "this happens when they move into cell"
# (Brogue) from "they need to hit some key" DCSS, Rogue for the stair
# thing to happen. also interaction on move may not require things
# to be solid, as presumably non-solid things could interact somehow?
# maybe there's a table that has "from,to" and maybe also whether
# it's due to a move or command?
#
# oh may also need ordering, as "burning cloud" above a hole might
# burn the entity *before* they get moved to new cell by hole
proc cmd_stair {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    ecs eval {SELECT w,x,y FROM position WHERE entid=$ent(entid)} pos {
        set found [ecs onecolumn {
          SELECT ch FROM display 
          INNER JOIN position USING (entid)
          WHERE w=$pos(w) AND x=$pos(x) AND y=$pos(y) AND ch=$ch
        }]
        if {$found == $ch} {
            if {$ch == 60} {
                set nlvl [- $pos(w) 1]
            } elseif {$ch == 62} {
                set nlvl [+ $pos(w) 1]
            } else {
                error "unknown stair type for entid $destid"
            }
            if {$nlvl == -1} {
                # TODO probably need to drop curses, etc
                warn "you have escaped?"
                exit 0
            }
            # TODO like with chute destination square must be empty of
            # solids...
            tailcall move_ent $ent(entid) $depth \
              $pos(w) $pos(x) $pos(y) $nlvl $pos(x) $pos(y) 20
        }
    }
    if {$ch == 62} {
        # are they somehow above a chute? (probably by being non-solid)
        set chute [ecs onecolumn {
          SELECT ch FROM display
          INNER JOIN position USING (entid)
          WHERE w=$pos(w) AND x=$pos(x) AND y=$pos(y) AND ch=32
        }]
        if {$chute == 32} {
            warn "going down"
            tailcall move_ent $ent(entid) $depth \
              $pos(w) $pos(x) $pos(y) [+ $pos(w) 1] $pos(x) $pos(y) 10
        }
    }
    return -code continue
}

proc cmd_pass {entv depth ch} {
    global ecs
    upvar $depth $entv ent
    uplevel $depth {if {$new_energy < 10} {set new_energy 10}}
    return -code break
}

proc cmd_quit {entv depth ch} {exit 0}

# a "do nothing" command that consumes no energy
proc cmd_version {entv depth ch} {
    warn "version 42"
    return -code continue
}

# from book
proc do {varname first last body} {
    upvar 1 $varname vv
    for {set vv $first} {$vv <= $last} {incr vv} {
        set code [catch {uplevel 1 $body} msg options]
        switch -- $code {
            0 -
            4 {}
            3 {return}
            default {
                dict incr options -level
                return -options $options $msg
            }
        }
    }
}

proc get_direction {} {
    while 1 {
        set ch [getch]
        if {$ch == 27} {return -code return}
        set xy [ecs eval {SELECT dx,dy FROM keymoves WHERE key=$ch}]
        if {[llength $xy] > 0} {break}
    }
    return $xy
}

proc init_map {} {
    global ecs boundary
    for {set lvl [lindex $boundary 4]} "\$lvl<=[lindex $boundary 5]" {incr lvl} {
        lappend maps [ecs eval {
            SELECT x,y,ch,max(zlevel) FROM position
            INNER JOIN display USING (entid)
            WHERE w=$lvl GROUP BY x,y
          }] \
          [ecs eval {
            SELECT DISTINCT x,y FROM position WHERE w=$lvl AND entid IN
            (SELECT entid FROM components WHERE comp='opaque')
          }]
    }
    initmap $boundary {*}$maps
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
# TODO honoring stairs would be good... maybe instead call over to cmd_movekey?
proc leftmover {entv depth} {
    global boundary ecs
    upvar $depth $entv ent
    ecs eval {SELECT w,x,y FROM position WHERE entid=$ent(entid)} pos {
        set newx [expr $pos(x) <= [lindex $boundary 0] \
                     ? [lindex $boundary 2] \
                     : $pos(x) - 1]
        if {![move_blocked $entv [+ $depth 1] $pos(w) $newx $pos(y)]} {
            ecs eval {UPDATE position SET x=$newx WHERE entid=$ent(entid)}
            ecs eval {
                UPDATE position SET dirty=TRUE
                WHERE (w=$pos(w) AND x=$pos(x) AND y=$pos(y))
                   OR (w=$pos(w) AND x=$newx AND y=$pos(y))
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
        ecs eval {UPDATE position SET dirty=TRUE}
        ecs cache size 100
    } else {
        global zlevel
        make_db
        ecs cache size 100

        make_entity Ekileugor 0 0 1 @ $zlevel(ekileugor) act_fight \
          energy keyboard

        make_entity "la nanmu poi terpa lo ke'a xirma" 0 1 1 H \
          $zlevel(monst) act_fight energy leftmover solid

        set wall [make_massent bitmu # $zlevel(feature) solid opaque]

        # a room with a door
        make_entity "a wild vorme" 0 3 4 + \
          $zlevel(feature) act_okay solid opaque
        do i 4 5 {
            set_position $wall 0 2 $i act_nope
            set_position $wall 0 4 $i act_nope
        }
        do i 2 4 {set_position $wall 0 $i 6 act_nope}

        # column-style room like seen in Zangband
        do i 4 9 {
            set_position $wall 0 5 $i act_nope
            set_position $wall 0 9 $i act_nope
        }
        set column [make_massent bitmu & $zlevel(feature) solid opaque]
        set_position $column 0 6 5 act_nope
        set_position $column 0 8 5 act_nope
        set_position $column 0 6 7 act_nope
        set_position $column 0 8 7 act_nope

        # probably need highlight (and prompt) like in Brogue
        set chuted [make_massent {chute down} { } $zlevel(feature) solid]
        set_position $chuted 0 7 3 act_chute

        set dstair [make_massent {stair up} > $zlevel(feature) solid]
        set_position $dstair 0 2 3 act_okay
        set ustair [make_massent {stair up} < $zlevel(feature) solid opaque]
        set_position $ustair 1 2 3 act_okay
        set_position $ustair 1 8 8 act_okay

        # merely something solid to be in the stair or chute destination
        make_entity {walrus} 1 7 3 W $zlevel(monst) act_fight opaque solid
        make_entity {walrus} 1 2 3 W $zlevel(monst) act_fight opaque solid

        # no interaction and non-solid to prevent interaction (without
        # various items or other conditions). probably needs a status
        # message to that effect somewhere
        make_entity "the way out" 0 0 0 < $zlevel(feature) act_missing opaque

        # this is what makes the "level map", such as it is
        set floor [make_massent "floor" . $zlevel(floor)]
        for {set w 0} {$w<2} {incr w} {
            for {set y 0} {$y<10} {incr y} {
                for {set x 0} {$x<10} {incr x} {
                    set_position $floor $w $x $y act_okay
                }
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
            CREATE TABLE display (
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
            CREATE TABLE position (
              entid INTEGER NOT NULL,
              w INTEGER,
              x INTEGER,
              y INTEGER,
              interact TEXT,
              dirty BOOLEAN DEFAULT TRUE,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        ecs eval {CREATE INDEX position2dirty ON position(dirty)}
        ecs eval {CREATE INDEX position2xy ON position(w,x,y)}
        # components an entity has
        ecs eval {
            CREATE TABLE components (
              entid INTEGER NOT NULL,
              comp TEXT NOT NULL,
              FOREIGN KEY(entid) REFERENCES ents(entid)
                    ON UPDATE CASCADE ON DELETE CASCADE
            )
        }
        ecs eval {CREATE INDEX components2comp ON components(comp)}
        # ascii(7) decimal values (and maybe some numbers invented by
        # ncurses) plus a proc to call for the given key
        ecs eval {
            CREATE TABLE keymap (
              key INTEGER NOT NULL,
              cmd TEXT NOT NULL,
              desc TEXT
            )
        }
        ecs eval {INSERT INTO keymap VALUES(46,'cmd_pass','skip a turn')}
        ecs eval {INSERT INTO keymap VALUES(60,'cmd_stair','ascend stair')}
        ecs eval {INSERT INTO keymap VALUES(62,'cmd_stair','descend stair')}
        ecs eval {INSERT INTO keymap VALUES(63,'cmd_commands','show commands')}
        ecs eval {INSERT INTO keymap VALUES(64,'cmd_position','show position')}
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
        # key to x,y offsets for said key
        ecs eval {
            CREATE TABLE keymoves (
                key INTEGER PRIMARY KEY NOT NULL,
                dx INTEGER NOT NULL,
                dy INTEGER NOT NULL,
                desc TEXT
            )
        }
        ecs eval {INSERT INTO keymoves VALUES(104,-1,0,"move west")}
        ecs eval {INSERT INTO keymoves VALUES(106,0,1,"move south")}
        ecs eval {INSERT INTO keymoves VALUES(107,0,-1,"move north")}
        ecs eval {INSERT INTO keymoves VALUES(108,1,0,"move east")}
        ecs eval {INSERT INTO keymoves VALUES(121,-1,-1,"move north-west")}
        ecs eval {INSERT INTO keymoves VALUES(117,1,-1,"move north-east")}
        ecs eval {INSERT INTO keymoves VALUES(98,-1,1,"move south-west")}
        ecs eval {INSERT INTO keymoves VALUES(110,1,1,"move south-east")}
    }
}
# oh can probably detect shift+move or control+move and pass shift/control
# flag into move routine? or just have entries for all those

# entity -- something that can be displayed and has a position and
# probably has some number of components
proc make_entity {name lvl x y ch zlevel interact args} {
    global ecs
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_position $entid $lvl $x $y $interact
        set_display $entid $ch $zlevel
        foreach comp $args {set_component $entid $comp}
    }
    return $entid
}

# something that can exist at multiple points such as floor or
# wall tiles
proc make_massent {name ch zlevel args} {
    global ecs
    ecs transaction {
        ecs eval {INSERT INTO ents(name) VALUES($name)}
        set entid [ecs last_insert_rowid]
        set_display $entid $ch $zlevel
        foreach comp $args {set_component $entid $comp}
    }
    return $entid
}

# solid things cannot be in the same square
proc move_blocked {entv depth lvl newx newy} {
    global ecs
    upvar $depth $entv ent
    set this [ecs eval {
        SELECT COUNT(*) FROM components WHERE entid=$ent(entid) AND comp='solid'
    }]
    set that [ecs eval {
        SELECT COUNT(*) FROM components INNER JOIN position USING (entid)
        WHERE comp='solid' AND w=$lvl AND x=$newx AND y=$newy
    }]
    return [expr {$this + $that > 1}]
}

proc move_ent {id depth oldw oldx oldy neww newx newy cost} {
    global ecs
    ecs eval {UPDATE position SET w=$neww,x=$newx,y=$newy WHERE entid=$id}
    ecs eval {
        UPDATE position SET dirty=TRUE
        WHERE (w=$oldw AND x=$oldx AND y=$oldy)
           OR (w=$neww AND x=$newx AND y=$newy)
    }
    uplevel $depth "if {\$new_energy < $cost} {set new_energy $cost}"
    return -code break
}

proc save_db {{file game.db}} {global ecs; ecs backup $file}

proc set_boundaries {} {
    global boundary ecs
    set boundary [ecs eval {
        SELECT min(x),min(y),max(x),max(y),min(w),max(w) FROM position
    }]
}

proc set_component {ent cname} {
    global ecs
    ecs eval {INSERT INTO components VALUES($ent, $cname)}
}

proc set_display {ent ch zlevel} {
    global ecs
    set ch [scan $ch %c]
    ecs eval {INSERT INTO display VALUES($ent,$ch,$zlevel)}
}

proc set_position {ent lvl x y act} {
    global ecs
    ecs eval {
        INSERT INTO position(entid,w,x,y,interact) VALUES($ent,$lvl,$x,$y,$act)
    }
}

proc unset_component {ent cname} {
    global ecs
    ecs eval {DELETE FROM components WHERE entid=$ent AND comp=$cname}
}

# TODO update routines probably should be in their own table so this
# does not need to get back random unrelated components
proc update_ent {entv depth} {
    global ecs
    upvar $depth $entv ent
    # NOTE may need a more specific ordering than alphabetic sort on
    # comp name such that environmental effects (wind blowing things
    # left) happens at a specific time in the sequence of components
    ecs eval {
        SELECT comp FROM components WHERE entid=$ent(entid) ORDER BY comp
    } comp {
        # NOTE "keyboard" comp requires that they have a position
        # (and maybe also display) but there's no actual constraint
        # enforcing that in the database
        switch $comp(comp) {
            keyboard -
            leftmover {$comp(comp) $entv [+ $depth 1]}
        }
    }
}

proc update_map {entv depth} {
    global ecs
    upvar $depth $entv ent
    set wxy [ecs eval {SELECT w,x,y FROM position WHERE entid=$ent(entid)}]
    set lvl [lindex $wxy 0]
    ecs transaction {
        set dirty [ecs eval {
            SELECT entid,x,y,ch,max(zlevel)
            FROM position INNER JOIN display USING (entid)
            WHERE dirty=TRUE AND w=$lvl GROUP BY x,y
        }]
        set len [llength $dirty]
        for {set i 0} {$i < $len} {incr i 5} {
            set x [lindex $dirty [+ $i 1]]
            set y [lindex $dirty [+ $i 2]]
            # max(zlevel) unused so insert the is-opaque boolean there
            lset dirty [+ $i 4] [ecs eval {
                SELECT COUNT(*) FROM components
                WHERE comp='opaque' AND entid
                IN (SELECT entid FROM position WHERE w=$lvl AND x=$x AND y=$y)
            }]
        }
        #                     FOV radius
        refreshmap $wxy $dirty 3
        ecs eval {UPDATE position SET dirty=FALSE WHERE dirty=TRUE AND w=$lvl}
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
        SELECT * FROM components INNER JOIN ents USING (entid)
        WHERE comp='energy'
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
