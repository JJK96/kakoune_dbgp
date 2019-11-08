# override to allow starting wrapper scripts
# they must be compatible with dbgp arguments
declare-option -hidden str dbgp_source %sh{echo "${kak_source%/*}"}

# script summary:
# a long running shell process starts a dbgp session (or connects to an existing one) and handles input/output
# kakoune -> dbgp communication is done by writing the dbgp commands to a fifo
# dbgp -> kakoune communication is done by a perl process that translates dbgp events into kakoune commands
# the dbgp-handle-* commands act upon dbgp notifications to update the kakoune state

decl str dbgp_breakpoint_active_symbol "●"
decl str dbgp_breakpoint_inactive_symbol "○"
decl str dbgp_location_symbol "➡"

face global DbgpBreakpoint red,default
face global DbgpLocation blue,default

# a debugging session has been started
decl bool dbgp_started false
# the debugged program is currently running (stopped or not)
decl bool dbgp_program_running false
# the debugged program is currently running, but stopped
decl bool dbgp_program_stopped false
# Whether autojump should be enabled
decl bool dbgp_autojump true
# if not empty, contains the name of client in which the value is printed
# set by default to the client which started the session
decl str dbgp_print_client

# contains all known breakpoints in this format:
# id enabled line file id enabled line file  ...
decl str-list dbgp_breakpoints_info
# if execution is currently stopped, contains the location in this format:
# line file
decl str-list dbgp_location_info
# note that these variables may reference locations that are not in currently opened buffers

# a visual indicator showing the current state of the script
decl str dbgp_indicator

# the directory containing the input fifo, pty object and backtrace
decl -hidden str dbgp_dir "/tmp/kakoune_dbgp/%val{session}"

decl str dbgp_port 9000

# corresponding flags generated from the previous variables
# these are only set on buffer scope
decl -hidden line-specs dbgp_breakpoints_flags
decl -hidden line-specs dbgp_location_flag

addhl shared/dbgp group -passes move
addhl shared/dbgp/ flag-lines DbgpLocation dbgp_location_flag
addhl shared/dbgp/ flag-lines DbgpBreakpoint dbgp_breakpoints_flags

def dbgp-start %{
    evaluate-commands %sh{
        if $kak_opt_dbgp_started; then
            # a previous session was ongoing, stop it and clean the options
            echo dbgp-stop
        fi
    }
    nop %sh{
        if ! $kak_opt_dbgp_started; then
            mkdir -p $kak_opt_dbgp_dir
            mkfifo "$kak_opt_dbgp_dir"/input_pipe
            ( tail -f "$kak_opt_dbgp_dir"/input_pipe | python $kak_opt_dbgp_source/dbgp_client.py $kak_opt_dbgp_port $kak_session $kak_client > /tmp/test 2>&1 ) >/dev/null 2>&1 </dev/null &
        fi
    }
    set global dbgp_started true
    set global dbgp_print_client %val{client}
    dbgp-set-indicator-from-current-state
    hook -group dbgp global BufOpenFile .* %{
        dbgp-refresh-location-flag %val{buffile}
        dbgp-refresh-breakpoints-flags %val{buffile}
    }
    hook -group dbgp global KakEnd .* %{
        dbgp-stop
    }
    addhl global/dbgp-ref ref -passes move dbgp
}

def dbgp-stop %{
    nop %sh{
        if $kak_opt_dbgp_started; then
            echo "exit()" > "$kak_opt_dbgp_dir"/input_pipe
        fi
    }
    set global dbgp_started false
    set global dbgp_program_running false
    set global dbgp_program_stopped false
    set global dbgp_indicator ""

    set global dbgp_breakpoints_info
    set global dbgp_location_info
    eval -buffer * %{
        unset buffer dbgp_location_flag
        unset buffer dbgp_breakpoints_flags
    }
    rmhl global/dbgp-ref
    rmhooks global dbgp-ref
}

def dbgp-jump-to-location %{
    try %{ eval %sh{
        eval set -- "$kak_opt_dbgp_location_info"
        [ $# -eq 0 ] && exit
        line="$1"
        buffer="$2"
        printf "edit -existing '%s' %s; exec gi" "$buffer" "$line"
    }}
}

# $1 = command and arguments
# $2 = extra info needed by the python script (usually none)
def dbgp -params 1..2 %{
    eval %sh{
        echo "$kak_client $2 $1" > "$kak_opt_dbgp_dir"/input_pipe
    }
}

def dbgp-set-breakpoint    %{ dbgp-breakpoint-impl false true }
def dbgp-clear-breakpoint  %{ dbgp-breakpoint-impl true false }
def dbgp-toggle-breakpoint %{ dbgp-breakpoint-impl true true }

def dbgp-get-context %{
    dbgp-create-context-buffer
    dbgp context_get
}

def dbgp-get-property -params 1 %{
    dbgp-create-context-buffer
    dbgp "property_get -n %arg{1}"
}

def -hidden dbgp-create-context-buffer %{
    edit -scratch *dbgp-context*
    set-option buffer filetype dbgp
    execute-keys \%
}

# dbgp doesn't tell us in its output what was the expression we asked for, so keep it internally for printing later
decl -hidden str dbgp_expression_demanded

def dbgp-enable-autojump %{
    set global dbgp_autojump true
}

def dbgp-disable-autojump %{
    set global dbgp_autojump false
}

def dbgp-toggle-autojump %{
    evaluate-commands %sh{
        if $kak_opt_dbgp_autojump; then
            echo "dbgp-disable-autojump"
        else
            echo "dbgp-enable-autojump"
        fi
    }
}

decl -hidden int backtrace_current_line

def dbgp-backtrace %{
    try %{
        try %{ db *dbgp-backtrace* }
        eval %sh{
            [ "$kak_opt_dbgp_stopped" = false ] && printf fail
            mkfifo "$kak_opt_dbgp_dir"/backtrace
        }
        dbgp-cmd '-stack-list-frames'
        eval -try-client %opt{toolsclient} %{
            edit! -fifo "%opt{dbgp_dir}/backtrace" *dbgp-backtrace*
            set buffer backtrace_current_line 0
            addhl buffer/ regex "^([^\n]*?):(\d+)" 1:cyan 2:green
            addhl buffer/ line '%opt{backtrace_current_line}' default+b
            map buffer normal <ret> ': dbgp-backtrace-jump<ret>'
            hook -always -once buffer BufCloseFifo .* %{
                nop %sh{ rm -f "$kak_opt_dbgp_dir"/backtrace }
            }
        }
    }
}

def -hidden dbgp-backtrace-jump %{
    eval -save-regs '/' %{
        try %{
            exec -save-regs '' 'xs^([^:]+):(\d+)<ret>'
            set buffer backtrace_current_line %val{cursor_line}
            eval -try-client %opt{jumpclient} "edit -existing %reg{1} %reg{2}"
            try %{ focus %opt{jumpclient} }
        }
    }
}

def dbgp-backtrace-up %{
    eval -try-client %opt{jumpclient} %{
        buffer *dbgp-backtrace*
        exec "%opt{backtrace_current_line}gk<ret>"
        dbgp-backtrace-jump
    }
    try %{ eval -client %opt{toolsclient} %{ exec %opt{backtrace_current_line}g } }
}

def dbgp-backtrace-down %{
    eval -try-client %opt{jumpclient} %{
        buffer *dbgp-backtrace*
        exec "%opt{backtrace_current_line}gj<ret>"
        dbgp-backtrace-jump
    }
    try %{ eval -client %opt{toolsclient} %{ exec %opt{backtrace_current_line}g } }
}

# implementation details

def -hidden dbgp-set-indicator-from-current-state %{
    set global dbgp_indicator %sh{
        [ "$kak_opt_dbgp_started" = false ] && exit
        printf 'dbgp '
        a=$(
            [ "$kak_opt_dbgp_program_running" = true ] && printf '[running]'
            [ "$kak_opt_dbgp_program_stopped" = true ] && printf '[stopped]'
        )
        [ -n "$a" ] && printf "$a "
    }
}

# the two params are bool that indicate the following
# if %arg{1} == true, existing breakpoints where there is a cursor are cleared (untouched otherwise)
# if %arg{2} == true, new breakpoints are set where there is a cursor and no breakpoint (not created otherwise)
def dbgp-breakpoint-impl -hidden -params 2 %{
    eval -draft %{
        # reduce to cursors so that we can just extract the line out of selections_desc without any hassle
        exec 'gh'
        eval %sh{
            [ "$kak_opt_dbgp_started" = false ] && exit
            delete="$1"
            create="$2"
            commands=$(
                # iterating with space-splitting is safe because it's not arbitrary input
                # lucky me
                for selection in $kak_selections_desc; do
                    cursor_line=${selection%%.*}
                    match_found="false"
                    eval set -- "$kak_opt_dbgp_breakpoints_info"
                    while [ $# -ne 0 ]; do
                        if [ "$4" = "$kak_buffile" ] && [ "$3" = "$cursor_line" ]; then
                            [ "$delete" = true ] && printf "dbgp %%{breakpoint_remove -d %s}\n" "$1"
                            match_found="true"
                        fi
                        shift 4
                    done
                    if [ "$match_found" = false ] && [ "$create" = true ]; then
                        printf "dbgp %%{breakpoint_set -t line -f file://%s -n %s}\n" "$kak_buffile" "$cursor_line"
                    fi
                done
            )
            printf "%s\n" "$commands"
        }
    }
}


def -hidden -params 2 dbgp-handle-break %{
    set global dbgp_program_stopped true
    dbgp-set-indicator-from-current-state
    set global dbgp_location_info  %arg{1} %arg{2}
    dbgp-refresh-location-flag %arg{2}
    evaluate-commands %sh{
        [ "$kak_opt_dbgp_autojump" = true ] && echo 'eval -try-client %opt{jumpclient} dbgp-jump-to-location'
    }
}

def -hidden dbgp-handle-stopped %{
    set global dbgp_program_stopped true
    set global dbgp_program_running false
    dbgp-set-indicator-from-current-state
}

def -hidden dbgp-handle-running %{
    set global dbgp_program_running true
    set global dbgp_program_stopped false
    dbgp-set-indicator-from-current-state
    dbgp-clear-location
}

def -hidden dbgp-clear-location %{
    try %{ eval %sh{
        eval set -- "$kak_opt_dbgp_location_info"
        [ $# -eq 0 ] && exit
        buffer="$2"
        printf "unset 'buffer=%s' dbgp_location_flag" "$buffer"
    }}
    set global dbgp_location_info
}

# refresh the location flag of the buffer passed as argument
def -hidden -params 1 dbgp-refresh-location-flag %{
    # buffer may not exist, only try
    try %{
        eval -buffer %arg{1} %{
            eval %sh{
                buffer_to_refresh="$1"
                eval set -- "$kak_opt_dbgp_location_info"
                [ $# -eq 0 ] && exit
                buffer_stopped="$2"
                [ "$buffer_to_refresh" != "$buffer_stopped" ] && exit
                line_stopped="$1"
                printf "set -add buffer dbgp_location_flag '%s|%s'" "$line_stopped" "$kak_opt_dbgp_location_symbol"
            }
        }
    }
}

def -hidden -params 4 dbgp-handle-breakpoint-created %{
    # id_modified active line file 
    set -add global dbgp_breakpoints_info %arg{1} %arg{2} %arg{3} %arg{4}
    dbgp-refresh-breakpoints-flags %arg{4}
}

def -hidden -params 1 dbgp-handle-breakpoint-deleted %{
    eval %sh{
        id_to_delete="$1"
        printf "set global dbgp_breakpoints_info\n"
        eval set -- "$kak_opt_dbgp_breakpoints_info"
        while [ $# -ne 0 ]; do
            if [ "$1" = "$id_to_delete" ]; then
                buffer_deleted_from="$4"
            else
                printf "set -add global dbgp_breakpoints_info %s %s %s '%s'\n" "$1" "$2" "$3" "$4"
            fi
            shift 4
        done
        printf "dbgp-refresh-breakpoints-flags '%s'\n" "$buffer_deleted_from"
    }
}

def -hidden -params 4 dbgp-handle-breakpoint-modified-cmd %{
    eval %sh{
        id_modified="$1"
        active="$2"
        line="$3"
        file="$4"
        printf "set global dbgp_breakpoints_info\n"
        eval set -- "$kak_opt_dbgp_breakpoints_info"
        while [ $# -ne 0 ]; do
            if [ "$1" = "$id_modified" ]; then
                printf "set -add global dbgp_breakpoints_info %s %s %s '%s'\n" "$id_modified" "$active" "$line" "$file"
            else
                printf "set -add global dbgp_breakpoints_info %s %s %s '%s'\n" "$1" "$2" "$3" "$4"
            fi
            shift 4
        done
    }
    dbgp-refresh-breakpoints-flags %arg{4}
}

# Show the current context (variables) in the context buffer
def -hidden -params 1 dbgp-handle-context %{
    # User should already be in the context buffer and have the text to be replaced selected
    evaluate-commands -save-regs '"' -draft %{
        set-register dquote %arg{1}
        execute-keys <a-x>R
    }
}

def -hidden dbgp-expand-property %{
    # Reduce to a single selection
    execute-keys <space>
    evaluate-commands -save-regs '"a' %{
        try %{
            # only execute on properties with children
            execute-keys '<a-x><a-k>> \d+<ret>'
            # count leading spaces for indent and cut it to
            evaluate-commands -draft %{
                try %{
                    # select the whitespace
                    execute-keys 's^ *<ret>'
                    # check if it is only whitespace that is selected
                    execute-keys '<a-k>\s<ret>'
                    # count the characters and store in register a
                    evaluate-commands %sh{
                        count=$(printf "$kak_selection" | wc -c)
                        echo "set-register a $count"
                    }
                } catch %{
                    # No leading whitespace
                    set-register a 0
                }
            }
            # select and copy the variable
            execute-keys -save-regs "" 'git<space>y'
            # expand it
            # no need to use the dbgp-get-property wrapper since the user is already in the right buffer
            dbgp "property_get -n %reg{dquote}" %reg{a}
        } catch %{
            echo -markup "{Error}Variable has no children to expand"
        }
    }
}

# refresh the breakpoint flags of the file passed as argument
def -hidden -params 1 dbgp-refresh-breakpoints-flags %{
    # buffer may not exist, so only try
    try %{
        eval -buffer %arg{1} %{
            unset buffer dbgp_breakpoints_flags
            eval %sh{
                to_refresh="$1"
                eval set -- "$kak_opt_dbgp_breakpoints_info"
                while [ $# -ne 0 ]; do
                    buffer="$4"
                    if [ "$buffer" = "$to_refresh" ]; then
                        line="$3"
                        enabled="$2"
                        if [ "$enabled" ]; then
                            flag="$kak_opt_dbgp_breakpoint_active_symbol"
                        else
                            flag="$kak_opt_dbgp_breakpoint_inactive_symbol"
                        fi
                        printf "set -add buffer dbgp_breakpoints_flags '%s|%s'\n" "$line" "$flag"
                    fi
                    shift 4
                done
            }
        }
    }
}

def -hidden dbgp-handle-print -params 1 %{
    try %{
        eval -buffer *dbgp-print* %{
            reg '"' "%opt{dbgp_expression_demanded} == %arg{1}"
            exec gep
            try %{ exec 'ggs\n<ret>d' }
        }
    }
    try %{ eval -client %opt{dbgp_print_client} 'info "%opt{dbgp_expression_demanded} == %arg{1}"' }
}

# clear all breakpoint information internal to kakoune
def -hidden dbgp-clear-breakpoints %{
    eval -buffer * %{ unset buffer dbgp_breakpoints_flags }
    set global dbgp_breakpoints_info
}

hook global WinSetOption filetype=dbgp %{
    hook buffer -group dbgp-hooks NormalKey <ret> dbgp-expand-property
    hook -once -always window WinSetOption filetype=.* %{ remove-hooks buffer dbgp-hooks }
}

declare-user-mode dbgp
map global dbgp s -docstring 'start' ': dbgp-start<ret>'
map global dbgp b -docstring 'create breakpoints' ': dbgp-toggle-breakpoint<ret>'
map global dbgp r -docstring 'run/continue' ': dbgp run<ret>'
map global dbgp n -docstring 'step over' ': dbgp step_over<ret>'
map global dbgp i -docstring 'step into' ': dbgp step_into<ret>'
map global dbgp c -docstring 'view context (variables)' ': dbgp-get-context<ret>'
map global dbgp v -docstring 'view property (variable)' ': dbgp-get-property '
map global dbgp t -docstring 'status' ': dbgp status<ret>'
map global dbgp a -docstring 'toggle autojump' ': dbgp-toggle-autojump<ret>'
map global dbgp q -docstring 'stop' ': dbgp-stop<ret>'
map global dbgp . -docstring 'lock' ': enter-user-mode -lock dbgp<ret>'
