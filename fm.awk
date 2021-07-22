#!/usr/bin/awk -f

BEGIN {

    ###################
    #  Configuration  #
    ###################

    OPENER = ( ENVIRON["OSTYPE"] ~ /darwin.*/ ? "open" : "xdg-open" )
    LASTPATH = ( ENVIRON["LASTPATH"] == "" ? ( ENVIRON["HOME"] "/.cache/lastpath" ) : ENVIRON["LASTPATH"] )
    HISTORY = ( ENVIRON["HISTORY"] == "" ? ( ENVIRON["HOME"] "/.cache/history" ) : ENVIRON["HISTORY"] )
    PREVIEW = 0
    RATIO = 0.35
    HIST_MAX = 5000

    ####################
    #  Initialization  #
    ####################

    init()
    RS = "\a"
    dir = ( ENVIRON["PWD"] == "/" ? "/" : ENVIRON["PWD"] "/" )
    cursor = 1; curpage = 1;

    # load alias
    cmd = "${SHELL:=/bin/sh} -c \". ~/.${SHELL##*/}rc && alias\""
    cmd | getline alias
    close(cmd)
    split(alias, aliasarr, "\n")
    for (line in aliasarr) {
        key = aliasarr[line]; gsub(/=.*/, "", key); gsub(/^alias /, "", key)
        cmd = aliasarr[line]; gsub(/.*=/, "", cmd); gsub(/^'|'$/, "", cmd)
        cmdalias[key] = cmd
    }

    #############
    #  Actions  #
    #############

    action = "History" RS \
         "mv" RS \
         "cp -R" RS \
         "ln -sf" RS \
         "rm -rf"
    help = "[num] - choose entries"  RS \
       "[num]+G - Go to page [num]" RS \
       "k/↑ - up" RS \
       "j/↓ - down" RS \
       "l/→ - right" RS \
       "h/← - left" RS \
       "n/PageDown - PageDown" RS \
       "p/PageUp - PageUp" RS \
       "t/Home - go to first page" RS \
       "b/End - go to last page" RS \
       "g - go to first entry in current page" RS \
       "G - go to last entry in current page" RS \
       "r - refresh" RS \
       "! - spawn shell" RS \
       "/ - search" RS \
       ": - commandline mode" RS \
       "- - go to previous directory" RS \
       "␣ - bulk (de-)selection" RS \
       "V - bulk (de-)selection all " RS \
       "v - toggle preview" RS \
       "> - more directory ratio" RS \
       "< - less directory ratio" RS \
       "a - actions"
       "? - show keybinds" RS \
       "q - quit"

    main();
}

END {
    finale();
    hist_clean();
    if (list != "empty") {
        printf("%s", dir) > "/dev/stdout"; close("/dev/stdout")
        printf("%s", dir) > LASTPATH; close(LASTPATH)
    }
}

function main() {

    do {

        list = gen_content(dir)
        delim = "\f"; num = 1; tmsg = dir; bmsg = ( bmsg == "" ? "Browsing" : bmsg );
        menu_TUI(list, delim, num, tmsg, bmsg)
        response = result[1]
        bmsg = result[2]

        #######################
        #  Matching: Actions  #
        #######################

        if (bmsg == "Actions") {
            if (response == "History") { hist_act(); empty_selected(); response = result[1]; bmsg = ""; }
            if (response == "mv" || response == "cp -R" || response == "ln -sf" || response == "rm -rf") {
                if (isEmpty(selected)) {
                    bmsg = sprintf("\033\13338;5;15m\033\13348;5;9m%s\033\133m", "Error: Nothing Selected")
                }
                else if (response == "rm -rf") {
                    act = response
                    list = "Yes" delim "No"; tmsg = "Execute " response "? "; bmsg = "Action: " response
                    menu_TUI(list, delim, num, tmsg, bmsg)
                    if (result[1] == "Yes") {
                        for (sel in selected) {
                            system(act " \"" selected[sel] "\"")
                        }
                    }
                    empty_selected()
                    bmsg = ""
                    continue
                }
                else {
                    bmsg = "Action: choosing destination";  act = response
                    while (1) {
                        list = gen_content(dir); delim = "\f"; num = 1; tmsg = dir;
                        menu_TUI(list, delim, num, tmsg, bmsg)
                        gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", result[1])
                        if (result[1] == "../") { gsub(/[^\/]*\/?$/, "", dir); dir = ( dir == "" ? "/" : dir ); continue }
                        if (result[1] == "./") { bmsg = "Browsing"; break; }
                        if (result[1] == "History") { hist_act(); dir = result[1]; continue; }
                        if (result[1] ~ /.*\/$/) dir = dir result[1]
                    }
                    for (sel in selected) {
                        system(act " \"" selected[sel] "\" \"" dir "\"")
                    }
                    empty_selected()
                    bmsg = ""
                    continue
                }
            }
        }

        ########################
        #  Matching: Browsing  #
        ########################

        gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", response)

        if (response == "../") {
            parent = ( dir == "/" ? "/" : dir )
            old_dir = parent
            if (hist != 1) {
                gsub(/[^\/]*\/?$/, "", dir)
                gsub(dir, "", parent)
            }
            empty_selected()
            dir = ( dir == "" ? "/" : dir ); hist = 0
            printf("%s\n", dir) >> HISTORY; close(HISTORY)
            continue
        }

        if (response == "./") {
            finale()
            system("cd \"" dir "\" && ${SHELL:=/bin/sh}")
            init()
            continue
        }

        if (response ~ /.*\/$/) {
            empty_selected()
            old_dir = dir
            dir = ( hist == 1 ? response : dir response )
            printf("%s\n", dir) >> HISTORY; close(HISTORY)
            cursor = 1; curpage = 1; hist = 0
            continue
        }

        finale()
        system(OPENER " \"" dir response "\"")
        init()

    } while (1)

}

function hist_act() {
    list = ""
    getline hisfile < HISTORY; close(HISTORY);
    N = split(hisfile, hisarr, "\n")
    for (i = N; i in hisarr; i--) {
        list = list "\n" hisarr[i]
    }
    list = substr(list, 3)
    list = list "\n../"; delim = "\n"; num = 1; tmsg = "Choose history: "; bmsg = "Action: " response; hist = 1;
    menu_TUI(list, delim, num, tmsg, bmsg)
}


function hist_clean() {
    getline hisfile < HISTORY; close(HISTORY);
    N = split(hisfile, hisarr, "\n")
    if (N > HIST_MAX) {
        for (i = N-HIST_MAX+1; i in hisarr; i++) {
            histmp = histmp "\n" hisarr[i]
        }
        hisfile = substr(histmp, 2)
        printf("%s", hisfile) > HISTORY; close(HISTORY)
    }
}

function gen_content(dir) {

    cmd = "for f in \"" dir "\"* \"" dir "\".* ; do "\
          "test -L \"$f\" && test -f \"$f\" && printf '\f\033\1331;36m%s\033\133m' \"$f\" && continue; "\
          "test -L \"$f\" && test -d \"$f\" && printf '\f\033\1331;36m%s\033\133m' \"$f\"/ && continue; "\
          "test -x \"$f\" && test -f \"$f\" && printf '\f\033\1331;32m%s\033\133m' \"$f\" && continue; "\
          "test -f \"$f\" && printf '\f%s' \"$f\" && continue; "\
          "test -d \"$f\" && printf '\f\033\1331;34m%s\033\133m' \"$f\"/ ; "\
      "done"

    code = cmd | getline list
    close(cmd)
    if (code <= 0) {
        list = "empty"
    }
    else if (dir != "/") {
        gsub(/[\\.^$(){}\[\]|*+?]/, "\\\\&", dir) # escape special char
        gsub(dir, "", list)
        list = substr(list, 2)
    }
    else {
        Narr = split(list, listarr, "\f")
        delete listarr[1]
        list = ""
        for (entry = 2; entry in listarr; entry++) {
            sub(/\//, "", listarr[entry])
            list = list "\f" listarr[entry]
        }
        list = substr(list, 2)
    }
    return list

}

# Credit: https://stackoverflow.com/a/20078022
function isEmpty(arr) { for (idx in arr) return 0; return 1 }

##################
#  Start of TUI  #
##################

function finale() {
    printf "\033\1332J\033\133H" >> "/dev/stderr" # clear screen
    printf "\033\133?7h" >> "/dev/stderr" # line wrap
    printf "\033\1338" >> "/dev/stderr" # restore cursor
    printf "\033\133?25h" >> "/dev/stderr" # hide cursor
    printf "\033\133?1049l" >> "/dev/stderr" # back from alternate buffer
    system("stty isig icanon echo")
    ENVIRON["LANG"] = LANG; # restore LANG
}

function init() {
    system("stty -isig -icanon -echo")
    printf "\033\1332J\033\133H" >> "/dev/stderr" # clear screen
    printf "\033\133?1049h" >> "/dev/stderr" # alternate buffer
    printf "\033\1337" >> "/dev/stderr" # save cursor
    printf "\033\133?25l" >> "/dev/stderr" # hide cursor
    printf "\033\1335 q" >> "/dev/stderr" # blinking bar
    printf "\033\133?7l" >> "/dev/stderr" # line wrap
    LANG = ENVIRON["LANG"]; # save LANG
    ENVIRON["LANG"] = C; # simplest locale setting
}


function CUP(lines, cols) {
    printf("\033\133%s;%sH", lines, cols) >> "/dev/stderr"
}

function draw_selected() {
    for (sel in selected) {
        if (selpage[sel] == curpage) {
            CUP(top + (sel-dispnum*(curpage-1))*num - num, 1)
            for (i = 1; i <= num; i++) {
                printf "\033\1332K" >> "/dev/stderr" # clear line
                CUP(top + cursor*num - num + i, 1)
            }
            CUP(top + (sel-dispnum*(curpage-1))*num - num, 1)
            gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", seldisp[sel])

            if (cursor == sel-dispnum*(curpage-1)) {
                printf "  \033\1337;31m%s%s\033\133m", sel ". ", seldisp[sel] >> "/dev/stderr"
            }
            else {
                printf "  \033\1331;31m%s%s\033\133m", sel ". ", seldisp[sel] >> "/dev/stderr"
            }
        }
    }
}

function empty_selected() { split("", selected, ":"); split("", seldisp, ":"); split("", selpage, ":"); }

function menu_TUI_page(list, delim) {
    answer = ""; page = 0; split("", pagearr, ":") # delete saved array
    cmd = "stty size"
    cmd | getline d
    close(cmd)
    split(d, dim, " ")
    top = 3; bottom = dim[1] - 4;
    fin = bottom - ( bottom - (top - 1) ) % num; end = fin + 1;
    dispnum = (end - top) / num

    Narr = split(list, disp, delim)
    dispnum = (dispnum <= Narr ? dispnum : Narr)

    # generate display content for each page (pagearr)
    for (entry = 1; entry in disp; entry++) {
        if ((+entry) % (+dispnum) == 1) { # if first item in each page
            pagearr[++page] = entry ". " disp[entry]
        }
        else {
            pagearr[page] = pagearr[page] "\n" entry ". " disp[entry]
        }
        if (parent != "" && disp[entry] == sprintf("\033\1331;34m%s\033\133m", parent)) {
            cursor = entry - dispnum*(page - 1); curpage = page
        }
    }
}

function search(list, delim, str, mode) {
    find = ""; str = tolower(str);
    if (mode == "dir") {
        regex = str ".*/";
    }
    else {
        regex = ".*" str ".*";
    }
    Narr = split(list, sdisp, delim)

    for (entry = 1; entry in sdisp; entry++) {
        match(tolower(sdisp[entry]), regex)
        if (RSTART) find = find delim sdisp[entry]
    }

    slist = substr(find, 2)
    return slist
}

function key_collect() {
    key = ""
    do {
        cmd = "dd ibs=1 count=1 2>&1"
        cmd | getline record;
        close(cmd)
        ans = substr(record, 1, 1)
        match(record, /[0-9.]* kB\/s/)
        sec = substr(record, RSTART, RLENGTH-4)
        gsub(/[\\^$()\[\]|*+?]/, "\\\\&", ans) # escape special char
        key = ( ans ~ /\033/ ? key : key ans )
        if (key ~ /^\\\[5$|^\\\[6$$/) ans = ""; continue;
    } while (ans !~ /[\003\177[:space:][:alnum:]><\}\{.~\/:!?-]/ )
    return key
}

function cmd_mode() {

    while (key = key_collect()) {
        if (key == "\003" || key == "\n") {
            if (key == "\003") { reply = "\003"; }
            split("", comparr, ":")
            break;
        }
        if (key == "\177") {
            reply = substr(reply, 1, length(reply) + cc - 1) substr(reply, length(reply) + cc + 1);
            split("", comparr, ":")
        }
        # cd
        else if (answer reply == ":cd " && key == "~") { reply = reply ENVIRON["HOME"] "/" }
        else if (answer reply ~ /:cd .*/ && key ~ /\t|\[Z/) { # Tab / Shift-Tab
            cc = 0
            if (isEmpty(comparr)) {
                comp = reply; gsub(/cd /, "", comp)
                compdir = comp;
                if (compdir ~ /^\.\.\/.*/) {
                    tmpdir = dir
                    while (compdir ~ /^\.\.\/.*/) { # relative path
                        gsub(/[^\/]*\/?$/, "", tmpdir)
                        gsub(/^\.\.\//, "", compdir)
                        tmpdir = ( tmpdir == "" ? "/" : tmpdir )
                    }
                    compdir = tmpdir
                }
                else {
                    gsub(/[^\/]*\/?$/, "", compdir); gsub(compdir, "", comp)
                }
                compdir = (compdir == "" ? dir : compdir);
                list = gen_content(compdir)
                gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", list)
                complist = search(list, delim, comp, "dir")
                Ncomp = split(complist, comparr, delim)
                c = ( key == "\t" ? 1 : Ncomp )
            }
            else {
                if (key == "\t") c = (c == Ncomp ? 1 : c + 1)
                else c = (c == 1 ? Ncomp : c - 1)
            }
            reply = "cd " compdir comparr[c]
        }
        # search
        else if (answer == "/" && key ~ /\t|\[Z/) {
            cc = 0
            if (isEmpty(comparr)) {
                comp = reply; complist = search(list, delim, comp, "")
                gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", complist)
                Ncomp = split(complist, comparr, delim)
                c = ( key == "\t" ? 1 : Ncomp )
            }
            else {
                if (key == "\t") c = (c == Ncomp ? 1 : c + 1)
                else c = (c == 1 ? Ncomp : c - 1)
            }
            reply = comparr[c]
        }
        else if (key ~ /\[D|\[C/) { # Left / Right arrow
            if (-cc < length(reply) && key ~ /\[D/) { cc-- }
            if (cc < 0 && key ~ /\[C/) { cc++ }
        }
        else if (key ~ /\[.+/) {
            continue
        }
        else {
            reply = substr(reply, 1, length(reply) + cc) key substr(reply, length(reply) + cc + 1);
            split("", comparr, ":")
        }
        CUP(dim[1], 1)
        status = sprintf("\033\1332K%s%s", answer, reply)
        printf(status) >> "/dev/stderr" # clear line
        if (cc < 0) { CUP(dim[1], length(status) + cc - 3) } # adjust cursor
    }

    printf "\033\133?25l" >> "/dev/stderr" # hide cursor
    if (reply == "\003") { answer = ""; key = ""; reply = ""; break; }
    answer = answer reply; reply = ""; split("", comparr, ":"); cc = 0

}

function menu_TUI(list, delim, num, tmsg, bmsg) {

    menu_TUI_page(list, delim)
    while (answer !~ /^[[:digit:]]+$|\.\.\//) {
        oldCursor = 1

        ## calculate cursor and Ncursor
        cursor = ( cursor+dispnum*(curpage-1) > Narr ? Narr - dispnum*(curpage-1) : cursor )
        Ncursor = cursor+dispnum*(curpage-1)

        printf "\033\1332J\033\133H" >> "/dev/stderr" # clear screen and move cursor to 0, 0
        CUP(top, 1); print pagearr[curpage] >> "/dev/stderr"
        CUP(top + cursor*num - num, 1); printf "%s\033\1337m%s\033\133m", Ncursor ". ", disp[Ncursor] >> "/dev/stderr"
        CUP(top - 2, 1); print tmsg >> "/dev/stderr"
        CUP(dim[1] - 2, 1); print bmsg >> "/dev/stderr"
        CUP(dim[1], 1)
        printf "Choose [\033\1331m1-%d\033\133m], current page num is \033\133;1m%d\033\133m, total page num is \033\133;1m%d\033\133m: ", Narr, curpage, page >> "/dev/stderr"
        if (bmsg !~ /Action.*|Helps/ && ! isEmpty(selected)) draw_selected()
        if (bmsg !~ /Action.*|Helps/ && PREVIEW == 1) draw_preview(disp[Ncursor])

        while (1) {

            answer = key_collect()

            #######################################
            #  Key: entry choosing and searching  #
            #######################################

            if ( answer ~ /^[[:digit:]]$/ || answer == "/" || answer == ":" ) {
                CUP(dim[1], 1)
                if (answer ~ /^[[:digit:]]$/) {
                    printf "Choose [\033\1331m1-%d\033\133m], current page num is \033\133;1m%d\033\133m, total page num is \033\133;1m%d\033\133m: %s", Narr, curpage, page, answer >> "/dev/stderr"
                }
                else {
                    printf "\033\1332K%s", answer >> "/dev/stderr" # clear line
                }
                printf "\033\133?25h" >> "/dev/stderr" # show cursor

                # system("stty icanon echo -tabs")
                # cmd = "read -r ans; echo \"$ans\" 2>/dev/null"
                # RS = "\n"; cmd | getline ans; RS = "\a"
                # close(cmd)
                # system("stty -icanon -echo tabs")
                # answer = answer ans; ans = ""

                cmd_mode()

                ## cd
                if (answer ~ /:cd .*/) {
                    old_dir = dir
                    gsub(/:cd /, "", answer)
                    if (answer ~ /^\/.*/) { # full path
                        dir = ( answer ~ /.*\/$/ ? answer : answer "/" )
                    }
                    else {
                        while (answer ~ /^\.\.\/.*/) { # relative path
                            gsub(/[^\/]*\/?$/, "", dir)
                            gsub(/^\.\.\//, "", answer)
                            dir = ( dir == "" ? "/" : dir )
                        }
                        dir = ( answer ~ /.*\/$/ || answer == "" ? dir answer : dir answer "/" )
                    }
                    empty_selected()
                    tmplist = gen_content(dir)
                    if (tmplist == "empty") {
                        dir = old_dir
                        bmsg = sprintf("\033\13338;5;15m\033\13348;5;9m%s\033\133m", "Error: Path Not Exist")
                    }
                    else {
                        list = tmplist
                    }
                    menu_TUI_page(list, delim)
                    tmsg = dir;
                    cursor = 1; curpage = (+curpage > +page ? page : curpage);
                    break
                }

                ## cmd mode
                if (answer ~ /:[^[:cntrl:]*]/) {
                    command = substr(answer, 2)
                    match(command, /\{\}/)
                    if (RSTART) {
                        post = substr(command, RSTART+RLENGTH+1);
                        command = substr(command, 1, RSTART-1)
                    }
                    if (command in cmdalias) command = cmdalias[command]

                    if (isEmpty(selected)) {
                        system("cd \"" dir "\" && " command " 2>/dev/null &")
                    }
                    else {
                        for (sel in selected) {
                            if (RSTART) {
                                system("cd \"" dir "\" && " command " \"" selected[sel] "\" " post " 2>/dev/null &")
                            }
                            else {
                                system("cd \"" dir "\" && " command " \"" selected[sel] "\" 2>/dev/null &")
                            }
                        }
                        empty_selected()
                    }

                    list = gen_content(dir)
                    menu_TUI_page(list, delim)
                    break
                }

                ## search
                if (answer ~ /\/[^[:cntrl:]*]/) {
                    slist = search(list, delim, substr(answer, 2), "")
                    if (slist != "") {
                        menu_TUI_page(slist, delim)
                        cursor = 1; curpage = 1;
                    }
                    break
                }

                ## go to page
                if ( (answer ~ /[[:digit:]]+G/) ) {
                    ans = answer; gsub(/G/, "", ans);
                    curpage = (+ans <= +page ? ans : page)
                    break
                }
                if (+answer > +Narr) answer = Narr
                if (+answer < 1) answer = 1
                break
            }

            if (answer ~ /[?]/) {
                menu_TUI_page(help, RS)
                tmsg = "Key bindings"; bmsg = "Helps"
                cursor = 1; curpage = 1;
                break
            }

            if (answer == "!") {
                finale()
                system("cd \"" dir "\" && ${SHELL:=/bin/sh}")
                init()
                break
            }

            if (answer == "-") {
                if (old_dir == "") break
                TMP = dir; dir = old_dir; old_dir = TMP;
                list = gen_content(dir)
                menu_TUI_page(list, delim)
                tmsg = dir; bmsg = "Browsing"
                cursor = 1; curpage = (+curpage > +page ? page : curpage);
                break
            }


            ########################
            #  Key: Total Redraw   #
            ########################

            if ( answer == "v" ) { PREVIEW = (PREVIEW == 1 ? 0 : 1); break }
            if ( answer == ">" ) { RATIO = (RATIO > 0.8 ? RATIO : RATIO + 0.05); break }
            if ( answer == "<" ) { RATIO = (RATIO < 0.2 ? RATIO : RATIO - 0.05); break }
            if ( answer == "r" ||
               ( answer ~ /^[[:digit:]]$/ && (+answer > +Narr || +answer < 1) ) ) {
               menu_TUI_page(list, delim)
               empty_selected()
               tmsg = dir; bmsg = "Browsing"
               cursor = 1; curpage = (+curpage > +page ? page : curpage);
               break
           }
           if ( bmsg == "Helps" && (answer == "\r" || answer == "l" || answer ~ /\[C/) ) { continue }
           if ( bmsg != "Helps" && (answer == "\r" || answer == "l" || answer ~ /\[C/) ) { answer = Ncursor; break }
           if ( answer == "a" ) {
               menu_TUI_page(action, RS)
               tmsg = "Choose an action"; bmsg = "Actions"
               cursor = 1; curpage = 1;
               break
           }
           if ( answer ~ /q|\003/ ) exit
           if ( (answer == "h" || answer ~ /\[D/) && dir != "/" ) { answer = "../"; disp[answer] = "../"; bmsg = ""; break }
           if ( (answer == "h" || answer ~ /\[D/) && dir = "/" ) continue
           if ( (answer == "n" || answer ~ /\[6~/) && +curpage < +page ) { curpage++; break }
           if ( (answer == "n" || answer ~ /\[6~/) && +curpage == +page && cursor != Narr - dispnum*(curpage-1) ) { cursor = ( +curpage == +page ? Narr - dispnum*(curpage-1) : dispnum ); break }
           if ( (answer == "n" || answer ~ /\[6~/) && +curpage == +page && cursor = Narr - dispnum*(curpage-1) ) continue
           if ( (answer == "p" || answer ~ /\[5~/) && +curpage > 1) { curpage--; break }
           if ( (answer == "p" || answer ~ /\[5~/) && +curpage == 1 && cursor != 1 ) { cursor = 1; break }
           if ( (answer == "p" || answer ~ /\[5~/) && +curpage == 1 && cursor = 1) continue
           if ( (answer == "t" || answer ~ /\[H/) && ( curpage != 1 || cursor != 1 ) ) { curpage = 1; cursor = 1; break }
           if ( (answer == "t" || answer ~ /\[H/) && curpage = 1 && cursor = 1 ) continue
           if ( (answer == "b" || answer ~ /\[F/) && ( curpage != page || cursor != Narr - dispnum*(curpage-1) ) ) { curpage = page; cursor = Narr - dispnum*(curpage-1); break }
           if ( (answer == "b" || answer ~ /\[F/) && curpage = page && cursor = Narr - dispnum*(curpage-1) ) continue

            #########################
            #  Key: Partial Redraw  #
            #########################

           if ( (answer == "j" || answer ~ /\[B/) && +cursor <= +dispnum ) { oldCursor = cursor; cursor++; }
           if ( (answer == "j" || answer ~ /\[B/) && +cursor > +dispnum  && page > 1 ) { cursor = 1; curpage++; break }
           if ( (answer == "k" || answer ~ /\[A/) && +cursor == 1  && curpage > 1 && page > 1 ) { cursor = dispnum; curpage--; break }
           if ( (answer == "k" || answer ~ /\[A/) && +cursor >= 1 ) { oldCursor = cursor; cursor--; }
           if ( answer == "g" ) { oldCursor = cursor; cursor = 1; }
           if ( answer == "G" ) { oldCursor = cursor; cursor = ( +curpage == +page ?  Narr - dispnum*(curpage-1) : dispnum ); }

            ####################
            #  Key: Selection  #
            ####################

           if ( answer == " " ) {
               if (selected[Ncursor] == "") {
                   TMP = disp[Ncursor]; gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", TMP)
                   selected[Ncursor] = dir TMP;
                   seldisp[Ncursor] = TMP;
                   selpage[Ncursor] = curpage;
                   if (+cursor <= +dispnum || +cursor <= +Narr) { cursor++ }
                   if (+cursor > +dispnum || +cursor > +Narr) { cursor = 1; curpage = ( +curpage == +page ? curpage : curpage + 1 ) }
                   bmsg = disp[Ncursor] " selected"
                   break
               }
               else {
                   delete selected[Ncursor]
                   delete seldisp[Ncursor]
                   delete selpage[Ncursor]
                   if (+cursor <= +dispnum || +cursor <= +Narr) { cursor++ }
                   if (+cursor > +dispnum) { cursor = 1; curpage = ( +curpage == +page ? curpage : curpage + 1 ) }
                   bmsg = disp[Ncursor] " cancelled"
                   break
               }
           }

           if (answer == "V") {
               if (isEmpty(selected)) {
                   selp = 0
                   for (entry = 1; entry in disp; entry++) {
                       TMP = disp[entry]; gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", TMP)
                       selected[entry] = dir TMP;
                       seldisp[entry] = TMP;
                       selpage[entry] = ((+entry) % (+dispnum) == 1 ? ++selp : selp)
                   }
                   bmsg = "All selected"
               }
               else {
                   empty_selected()
                   bmsg = "All cancelled"
               }
               break
           }

            ####################################################################
            #  Partial redraw: tmsg, bmsg, old entry, new entry, and selected  #
            ####################################################################

            Ncursor = cursor+dispnum*(curpage-1); oldNcursor = oldCursor+dispnum*(curpage-1);
            if (Ncursor > Narr) { Ncursor = Narr; cursor = Narr - dispnum*(curpage-1); continue }
            if (Ncursor < 1) { Ncursor = 1; cursor = 1; continue }

            CUP(dim[1] - 2, 1); # bmsg
            printf "\033\1332K" >> "/dev/stderr" # clear line
            print bmsg >> "/dev/stderr"

            CUP(top + oldCursor*num - num, 1); # old entry
            for (i = 1; i <= num; i++) {
                printf "\033\1332K" >> "/dev/stderr" # clear line
                CUP(top + oldCursor*num - num + i, 1)
            }
            CUP(top + oldCursor*num - num, 1);
            printf "%s", oldNcursor ". " disp[oldNcursor] >> "/dev/stderr"

            CUP(top + cursor*num - num, 1); # new entry
            for (i = 1; i <= num; i++) {
            printf "\033\1332K" >> "/dev/stderr" # clear line
            CUP(top + cursor*num - num + i, 1)
            }
            CUP(top + cursor*num - num, 1);
            printf "%s\033\1337m%s\033\133m", Ncursor ". ", disp[Ncursor] >> "/dev/stderr"

            if (bmsg !~ /Action.*|Helps/ && ! isEmpty(selected)) draw_selected()
            if (bmsg !~ /Action.*|Helps/ && PREVIEW == 1) draw_preview(disp[Ncursor])

        }

    }

    result[1] = disp[answer]
    result[2] = bmsg
}

function draw_preview(item) {

    # clear RHS of screen based on border
    border = int(dim[2]*RATIO)
    for (i = top; i <= end; i++) {
        CUP(i, border - 1)
        printf "\033\133K" >> "/dev/stderr" # clear line
    }

    if (+sec > 0.0) {
        CUP(top, border + 1)
        printf "\033\13338;5;0m\033\13348;5;15m%s\033\133m", "move too fast!" >> "/dev/stderr"
        return
    }

    gsub(/\033\[[0-9];[0-9][0-9]m|\033\[m/, "", item)
    path = dir item
    if (path ~ /.*\/$/) { # dir
        content = gen_content(path)
        split(content, prev, "\f")
        for (i = 1; i <= ((end - top) / num); i++) {
            CUP(top + i - 1, border + 1)
            print prev[i] >> "/dev/stderr"
        }
    }
    else if (path ~ /.*\.pdf/) {
        CUP(top, border + 1)
        cmd = "pdftoppm -jpeg -f 1 -singlefile \"" path "\" 2>/dev/null | chafa -s " 2.5*((end - top) / num) "x \"-\" 2>/dev/null"
        cmd | getline fig
        close(cmd)
        split(fig, prev, "\n")
        for (i = 1; i <= ((end - top) / num); i++) {
            CUP(top + i - 1, border + 1)
            print prev[i] >> "/dev/stderr"
        }
    }
    else if (path ~ /.*\.bmp|.*\.jpg|.*\.jpeg|.*\.png|.*\.xpm|.*\.webp|.*\.gif/) {
        CUP(top, border + 1)
        if (path ~ /.*\.gif/) {
            printf "\033\13338;5;0m\033\13348;5;15m%s\033\133m", "image" >> "/dev/stderr"
        }
        else {
            cmd = "chafa -s " 2.5*((end - top) / num) "x \"" path "\""
            cmd | getline fig
            close(cmd)
            split(fig, prev, "\n")
            for (i = 1; i <= ((end - top) / num); i++) {
                CUP(top + i - 1, border + 1)
                print prev[i] >> "/dev/stderr"
            }
        }
    }
    else if (path ~ /.*\.avi|.*\.mp4|.*\.wmv|.*\.dat|.*\.3gp|.*\.ogv|.*\.mkv|.*\.mpg|.*\.mpeg|.*\.vob|.*\.fl[icv]|.*\.m2v|.*\.mov|.*\.webm|.*\.ts|.*\.mts|.*\.m4v|.*\.r[am]|.*\.qt|.*\.divx/) {
        CUP(top, border + 1)
        cmd = "ffmpegthumbnailer -i \"" path "\" -o \"-\" -c jpg -s 0 -q 5 2>/dev/null | chafa -s " 2.5*((end - top) / num) "x \"-\" 2>/dev/null"
        cmd | getline fig
        close(cmd)
        split(fig, prev, "\n")
        for (i = 1; i <= ((end - top) / num); i++) {
            CUP(top + i - 1, border + 1)
            print prev[i] >> "/dev/stderr"
        }
    }
    else {
        getline content < path
        close(path)
        split(content, prev, "\n")
        for (i = 1; i <= ((end - top) / num); i++) {
            CUP(top + i - 1, border + 1)
            code = gsub(/\000/, "", prev[i])
            if (code > 0) {
                printf "\033\13338;5;0m\033\13348;5;15m%s\033\133m", "binary" >> "/dev/stderr"
                break
            }
            print prev[i] >> "/dev/stderr"
        }

    }
}

function notify(msg, str) {

    printf "\033\1332J\033\133H"
    print msg
    system("stty icanon echo")
    printf "\033\133?25h" >> "/dev/stderr" # show cursor
    cmd = "read -r ans; echo \"$ans\" 2>/dev/null"
    RS = "\n"; cmd | getline ans; RS = "\a"
    close(cmd)
    printf "\033\133?25l" >> "/dev/stderr" # hide cursor
    system("stty -icanon -echo")
    return str
}
