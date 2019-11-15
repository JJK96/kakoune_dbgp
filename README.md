# kakoune-dbgp

[kakoune](http://kakoune.org) plugin for [dbgp](https://xdebug.org/docs/dbgp) integration (i.e. [xdebug](https://xdebug.org) integration).

Largely based on the excelent work by Olivier Perret: [kakoune-gdb](https://github.com/occivink/kakoune-gdb)  
I only had to implement the communication between the debugging engine and kakoune instead of having to things like updating line-flags and jumping to the execution location.

## Setup

### Dependencies

* kakoune
* python3

### Plug.kak (recommended)

Use [plug.kak](https://github.com/andreyorst/plug.kak) to install this plugin

Example
```
plug 'jjk96/kakoune-dbgp' %{
    map global user x -docstring 'dbgp' ': enter-user-mode dbgp<ret>'
    dbgp-enable-autojump
}
```

### Manually
Add `dbgp.kak` to your autoload dir: `~/.config/kak/autoload/`, or source it manually.
Adapt the path for the python executable in `dbgp.kak` to point to the correct location.

## Usage

### Interfacing with a dbgp debugging engine

The first step in using the script is to connect kakoune and a dbgp debugging engine together.
There are multiple ways to do this, detailed below:

#### Starting a dbgp session

If you wish to start a new debugging session, you should call `dbgp-start`. 
A dbgp IDE session will be started which can be used to connect to by a dbgp debugger engine 

### Communicating with the debuggin engine 

Once kakoune is connected to the debugging engine, it can be communicated with through the `dbgp` kakoune command.
Kakoune will then be updated in real-time to show the current state of the debugging engine (current line, breakpoints).  
The script provides commands for the most common operations 

| kakoune command | Description |
| --- |  --- |
| `dbgp-start` | listen for an incoming connection from the debuggin engine |
| `dbgp-stop` | exit debugging session|
| `dbgp-step_into` | execute the next line, entering the function if applicable (step in) |
| `dbgp-step_over` | execute the next line of the current function (step over)|
| `dbgp-run` | start/continue execution until the next breakpoint |
| `dbgp-jump-to-location` | if execution is stopped, jump to the location |
| `dbgp-set-breakpoint` | set a breakpoint at the cursor location |
| `dbgp-clear-breakpoint` | remove any breakpoints at the cursor location |
| `dbgp-toggle-breakpoint` | remove or set a breakpoint at the cursor location|
| `dbgp-get-context` | get the context (variables) at the cursor location |
| `dbgp-get-property` | get the content of a variable in the context of the cursor location |
| `dbgp-eval` | evaluate the given expression in the context of the program |
| `dbgp-stacktrace` | show a stacktrace |

The `dbgp-{enable,disable,toggle}-autojump` commands let you control if the current client should jump to the current location when execution is stopped.

### View context (variables)

The command `dbgp-get-context` or `dbgp-get-property <variable>` can be used to view variables in the current context.
Those commands open a new buffer with all the variables (in the case of `dbgp-get-context`) or the specified variable in the case of `dbgp-get-property <variable>`.

A variable with children (indicated by ` > #children` at the end of the line) can be expanded by hitting `<ret>` while on that line. 
It can be collapsed by using `u` to undo the expansion

### Clients

All jump commands are executed in the `%opt{jumpclient}` and the variable view is opened in the `%opt{toolsclient}`

## Extending the script

This script can be extended by defining your own commands. `dbgp` is provided for that purpose: it simply forwards its arguments to the debugging engine. 
Some of the predefined commands are defined like that as shown above.

You can also use the existing options to further refine your commands. Some of these are read-only (`[R]`), some can also be written to (`[RW]`).
* `dbgp_started`[bool][R]        : true if a debugging session has been started
* `dbgp_program_running`[bool][R]: true if the debugged program is currently running (stopped or not)
* `dbgp_program_stopped`[bool][R]: true if the debugged program is currently running, and stopped
* `dbgp_autojump`[bool][RW]      : true if autojump is enabled
* `dbgp_location_info`[str][R]   : if running and stopped, contains the location in the format `line` `file`
* `dbgp_breakpoints_info`[str][R]: contains all known breakpoints in the format `id1` `enabled1` `line1` `file1` `id2` `enabled2` `line2` `file2` ...

### Customization

The gutter symbols can be modified by changing the values of these options: 
```
dbgp_breakpoint_active_symbol
dbgp_breakpoint_inactive_symbol
dbgp_location_symbol
```
as well as their associated faces:
```
DbgpBreakpoint
DbgpLocation
```

It is possible to show in the modeline the status of the plugin using the option `dbgp_indicator`. 
An example:
```
set global modelinefmt '%val{bufname} %val{cursor_line}:%val{cursor_char_column} {{context_info}} {{mode_info}} {red,default}%opt{dbgp_indicator}{default,default}- %val{client}@[%val{session}]'
```

To setup "standard" debugger shortcuts a custom usermode is created.
See [dbgp.kak](https://github.com/JJK96/kakoune_dbgp/blob/f1f95b18750c9e31eb11b2a582ee14bb0ec517f1/dbgp.kak#L400)

The actions to execute upon receiving a respons can be overridden by overriding the `dbgp-handle-*` commands.

### Inner workings

A python program is used to forward dbgp commands from kakoune to the debugging engine and to interpret the XML response into commands that will be executed in kakoune.

## TODO

* support printing variables by selecting them in the code and executing `dbgp-print`
* support other commands of the dbgp protocol
    * breakpoint modification 
    * evaluation of expressions
* support expanding variable children with multiple cursors at the same time
