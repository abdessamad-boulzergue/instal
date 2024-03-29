#
# Copyright (c) 2003-2009, Ashok P. Nadkarni
# All rights reserved.
#
# See the file LICENSE for license

# TBD - allow access rights to be specified symbolically using procs
# from security.tcl
# TBD - add -user option to get_process_info and get_thread_info
# TBD - add wrapper for GetProcessExitCode

namespace eval twapi {}

# Get my process id
proc twapi::get_current_process_id {} {
    return [::pid]
}

# Get my thread id
proc twapi::get_current_thread_id {} {
    return [GetCurrentThreadId]
}



# Wait until the process is ready
proc twapi::process_waiting_for_input {pid args} {
    array set opts [parseargs args {
        {wait.int 0}
    } -maxleftover 0]

    if {$pid == [pid]} {
        variable my_process_handle
        return [WaitForInputIdle $my_process_handle $opts(wait)]
    }

    set hpid [get_process_handle $pid]
    trap {
        return [WaitForInputIdle $hpid $opts(wait)]
    } finally {
        CloseHandle $hpid
    }
}

# Create a process
proc twapi::create_process {path args} {
    array set opts [parseargs args \
                        [list \
                             [list cmdline.arg ""] \
                             [list inheritablechildprocess.bool 0] \
                             [list inheritablechildthread.bool 0] \
                             [list childprocesssecd.arg ""] \
                             [list childthreadsecd.arg ""] \
                             [list inherithandles.bool 0] \
                             [list env.arg ""] \
                             [list startdir.arg ""] \
                             [list inheriterrormode.bool 1] \
                             [list newconsole.bool 0] \
                             [list detached.bool 0] \
                             [list newprocessgroup.bool 0] \
                             [list noconsole.bool 0] \
                             [list separatevdm.bool 0] \
                             [list sharedvdm.bool 0] \
                             [list createsuspended.bool 0] \
                             [list debugchildtree.bool 0] \
                             [list debugchild.bool 0] \
                             [list priority.arg "normal" [list normal abovenormal belownormal high realtime idle]] \
                             [list desktop.arg "__null__"] \
                             [list title.arg ""] \
                             windowpos.arg \
                             windowsize.arg \
                             screenbuffersize.arg \
                             [list feedbackcursoron.bool false] \
                             [list feedbackcursoroff.bool false] \
                             background.arg \
                             foreground.arg \
                             [list fullscreen.bool false] \
                             [list showwindow.arg ""] \
                             [list stdhandles.arg ""] \
                             [list stdchannels.arg ""] \
                             [list returnhandles.bool 0]\
                            ] -maxleftover 0]

    set process_sec_attr [_make_secattr $opts(childprocesssecd) $opts(inheritablechildprocess)]
    set thread_sec_attr [_make_secattr $opts(childthreadsecd) $opts(inheritablechildthread)]

    # Check incompatible options
    foreach {opt1 opt2} {
        newconsole detached
        sharedvdm  separatevdm
    } {
        if {$opts($opt1) && $opts($opt2)} {
            error "Options -$opt1 and -$opt2 cannot be specified together"
        }
    }
    # Create the start up info structure
    set si_flags 0
    if {[info exists opts(windowpos)]} {
        foreach {xpos ypos} [_parse_integer_pair $opts(windowpos)] break
        setbits si_flags 0x4
    } else {
        set xpos 0
        set ypos 0
    }
    if {[info exists opts(windowsize)]} {
        foreach {xsize ysize} [_parse_integer_pair $opts(windowsize)] break
        setbits si_flags 0x2
    } else {
        set xsize 0
        set ysize 0
    }
    if {[info exists opts(screenbuffersize)]} {
        foreach {xscreen yscreen} [_parse_integer_pair $opts(screenbuffersize)] break
        setbits si_flags 0x8
    } else {
        set xscreen 0
        set yscreen 0
    }

    set fg 7;                           # Default to white
    set bg 0;                           # Default to black
    if {[info exists opts(foreground)]} {
        set fg [_map_console_color $opts(foreground) 0]
        setbits si_flags 0x10
    }
    if {[info exists opts(background)]} {
        set bg [_map_console_color $opts(background) 1]
        setbits si_flags 0x10
    }

    if {$opts(feedbackcursoron)} {
        setbits si_flags 0x40
    }

    if {$opts(feedbackcursoron)} {
        setbits si_flags 0x80
    }

    if {$opts(fullscreen)} {
        setbits si_flags 0x20
    }

    switch -exact -- $opts(showwindow) {
        ""        { }
        hidden    {set opts(showwindow) 0}
        normal    {set opts(showwindow) 1}
        minimized {set opts(showwindow) 2}
        maximized {set opts(showwindow) 3}
        default   {error "Invalid value '$opts(showwindow)' for -showwindow option"}
    }
    if {[string length $opts(showwindow)]} {
        setbits si_flags 0x1
    }

    if {[llength $opts(stdhandles)] && [llength $opts(stdchannels)]} {
        error "Options -stdhandles and -stdchannels cannot be used together"
    }

    if {[llength $opts(stdhandles)]} {
        if {! $opts(inherithandles)} {
            error "Cannot specify -stdhandles option if option -inherithandles is specified as 0"
        }
        setbits si_flags 0x100
    }

    if {[llength $opts(stdchannels)]} {
        if {! $opts(inherithandles)} {
            error "Cannot specify -stdhandles option if option -inherithandles is specified as 0"
        }
        if {[llength $opts(stdchannels)] != 3} {
            error "Must specify 3 channels for -stdchannels option corresponding stdin, stdout and stderr"
        }

        setbits si_flags 0x100

        # Convert the channels to handles
        lappend opts(stdhandles) [duplicate_handle [get_tcl_channel_handle [lindex $opts(stdchannels) 0] read] -inherit]
        lappend opts(stdhandles) [duplicate_handle [get_tcl_channel_handle [lindex $opts(stdchannels) 1] write] -inherit]
        lappend opts(stdhandles) [duplicate_handle [get_tcl_channel_handle [lindex $opts(stdchannels) 2] write] -inherit]
    }

    set startup [list $opts(desktop) $opts(title) $xpos $ypos \
                     $xsize $ysize $xscreen $yscreen \
                     [expr {$fg|$bg}] $si_flags $opts(showwindow) \
                     $opts(stdhandles)]

    # Figure out process creation flags
    set flags 0x00000400;               # CREATE_UNICODE_ENVIRONMENT
    foreach {opt flag} {
        debugchildtree       0x00000001
        debugchild           0x00000002
        createsuspended      0x00000004
        detached             0x00000008
        newconsole           0x00000010
        newprocessgroup      0x00000200
        separatevdm          0x00000800
        sharedvdm            0x00001000
        inheriterrormode     0x04000000
        noconsole            0x08000000
    } {
        if {$opts($opt)} {
            setbits flags $flag
        }
    }

    switch -exact -- $opts(priority) {
        normal      {set priority 0x00000020}
        abovenormal {set priority 0x00008000}
        belownormal {set priority 0x00004000}
        ""          {set priority 0}
        high        {set priority 0x00000080}
        realtime    {set priority 0x00000100}
        idle        {set priority 0x00000040}
        default     {error "Unknown priority '$priority'"}
    }
    setbits flags $priority

    # Create the environment strings
    if {[llength $opts(env)]} {
        set child_env [list ]
        foreach {envvar envval} $opts(env) {
            lappend child_env "$envvar=$envval"
        }
    } else {
        set child_env "__null__"
    }

    trap {
        foreach {ph th pid tid} [CreateProcess [file nativename $path] \
                                     $opts(cmdline) \
                                     $process_sec_attr $thread_sec_attr \
                                     $opts(inherithandles) $flags $child_env \
                                     [file normalize $opts(startdir)] $startup] {
            break
        }
    } finally {
        # If opts(stdchannels) is not an empty list, we duplicated the handles
        # into opts(stdhandles) ourselves so free them
        if {[llength $opts(stdchannels)]} {
            # Free corresponding handles in opts(stdhandles)
            close_handles $opts(stdhandles)
        }
    }

    # From the Tcl source code - (tclWinPipe.c)
    #     /*
    #      * "When an application spawns a process repeatedly, a new thread
    #      * instance will be created for each process but the previous
    #      * instances may not be cleaned up.  This results in a significant
    #      * virtual memory loss each time the process is spawned.  If there
    #      * is a WaitForInputIdle() call between CreateProcess() and
    #      * CloseHandle(), the problem does not occur." PSS ID Number: Q124121
    #      */
    # WaitForInputIdle $ph 5000 -- Apparently this is only needed for NT 3.5


    if {$opts(returnhandles)} {
        return [list $pid $tid $ph $th]
    } else {
        CloseHandle $th
        CloseHandle $ph
        return [list $pid $tid]
    }
}


# Get a handle to a process
proc twapi::get_process_handle {pid args} {
    # OpenProcess masks off the bottom two bits thereby converting
    # an invalid pid to a real one.
    if {(![string is integer -strict $pid]) || ($pid & 3)} {
        win32_error 87 "Invalid PID '$pid'.";  # "The parameter is incorrect"
    }
    array set opts [parseargs args {
        {access.arg process_query_information}
        {inherit.bool 0}
    } -maxleftover 0]
    return [OpenProcess [_access_rights_to_mask $opts(access)] $opts(inherit) $pid]
}

# Get the exit code for a process. Returns "" if still running.
proc twapi::get_process_exit_code {hpid} {
    set code [GetExitCodeProcess $hpid]
    return [expr {$code == 259 ? "" : $code}]
}



# Get the command line
proc twapi::get_command_line {} {
    return [GetCommandLineW]
}

# Parse the command line
proc twapi::get_command_line_args {cmdline} {
    # Special check for empty line. CommandLinetoArgv returns process
    # exe name in this case.
    if {[string length $cmdline] == 0} {
        return [list ]
    }
    return [CommandLineToArgv $cmdline]
}



# Return true if passed pid is system
# TBD - update for Win2k8, vista, Windows 7, 64 bits
proc twapi::is_system_pid {pid} {
    foreach {major minor} [get_os_version] break
    if {$major == 4 } {
        # NT 4
        set syspid 2
    } elseif {$major == 5 && $minor == 0} {
        # Win2K
        set syspid 8
    } else {
        # XP and Win2K3
        set syspid 4
    }

    # Redefine ourselves and call the redefinition
    proc ::twapi::is_system_pid pid "expr \$pid==$syspid"
    return [is_system_pid $pid]
}

# Return true if passed pid is of idle process
proc twapi::is_idle_pid {pid} {
    return [expr {$pid == 0}]
}


