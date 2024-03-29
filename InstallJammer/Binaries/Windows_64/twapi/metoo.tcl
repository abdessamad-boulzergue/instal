# MeTOO stands for "MeTOO Emulates TclOO" (at a superficial syntactic level)
#
# Implements a *tiny*, but useful, subset of TclOO, primarily for use 
# with Tcl 8.4. Intent is that if you write code using MeToo, it should work 
# unmodified with TclOO in 8.5/8.6. Obviously, don't try going the other way!
#
# Emulation is superficial, don't try to be too clever in usage.
# Doing funky, or even non-funky, things with object namespaces will
# not work as you would expect.
#
# See the metoo::demo proc for sample usage. Calling this proc
# with parameter "oo" will use the TclOO commands. Else the metoo::
# commands. Note the demo code remains the same for both.
#
# The following fragment uses MeToo only if TclOO is not available:
#   if {[llength [info commands oo::*]]} {
#       namespace import oo::*
#   } else {
#       source metoo.tcl
#       namespace import metoo::class
#   }
#   class create C {...}
#
# Summary of the TclOO subset implemented - see TclOO docs for detail :
#
# Creating a new class: 
#   metoo::class create CLASSNAME CLASSDEFINITION
#
# Destroying a class:
#   CLASSNAME destroy
#    - this also destroys objects of that class and recursively destroys
#      child classes. NOTE: deleting the class namespace or renaming 
#      the CLASSNAME command to "" will NOT call object destructors.
#
# CLASSDEFINITION: Following may appear in CLASSDEFINTION
#   method METHODNAME params METHODBODY
#    - same as TclOO
#   constructor params METHODBODY
#    - same syntax as TclOO
#   destructor METHODBODY
#    - same syntax as TclOO
#   unknown METHODNAME ARGS
#    - if defined, called when an undefined method is invoked
#   superclass SUPER
#    - inherits from SUPER. Unlike TclOO, only single inheritance. Also
#      no checks for inheritance loops. You'll find out quickly enough!
#   All other commands within a CLASSDEFINITION will either raise error or
#   work differently from TclOO. Actually you can use pretty much any
#   Tcl command inside CLASSDEFINITION but the results may not be what you
#   expect. Best to avoid this.
#
# METHODBODY: The following method-internal TclOO commands are available:
#   my METHODNAME ARGS
#    - to call another method METHODNAME
#   my variable VAR1 ?VAR2...?
#    - brings object-specific variables into scope
#   next ?ARGS?
#    - calls the superclass method of the same name
#   self
#   self object
#    - returns the object name (usable as a command)
#   self namespace
#    - returns namespace of this object
#
# Creating objects:
#   CLASSNAME create OBJNAME ?ARGS?
#    - creates object OBJNAME of class CLASSNAME, passing ARGS to constructor
#      Returns the fully qualified object name that can be used as a command.
#   CLASSNAME new ?ARGS?
#    - creates a new object with an auto-generated name
#
# Destroying objects
#   OBJNAME destroy
#    - destroys the object calling destructors
#   rename OBJNAME ""
#    - same as above
#
# Renaming an object
#   rename OBJNAME NEWNAME
#    - the object can now be invoked using the new name. Note this is unlike
#      classes which should not be renamed.
#
# Differences and missing features from TclOO: Everything not listed above
# is missing. Some notable differences:
# - MeTOO is class-based, not object based like TclOO, thus class instances
#   (objects) cannot be modified by adding instance-specific methods etc..
#   Also a class is not itself an object.
# - does not support class refinement/definition.
# - no filters, forwarding, multiple-inheritance
# - no introspection capabilities
# - no private methods (all methods are exported).

catch {namespace delete metoo}

# TBD - variable ("my variable" is done, "variable" in method or
# class definition is not)
# TBD - default constructor and destructor to "next" (or maybe that
# is already taken care of by the inheritance code

namespace eval metoo {
    variable next_id 0
}

# Namespace in which commands in a class definition block are called
namespace eval metoo::define {
    proc method {class_ns name params body} {
        # Methods are defined in the methods subspace of the class namespace.
        # We prefix with _m_ to prevent them from being directly called
        # as procs, for example if the method is a Tcl command like "set"
        # The first parameter to a method is always the object namespace
        # denoted as the paramter "_this"
        namespace eval ${class_ns}::methods [list proc _m_$name [concat [list _this] $params] $body]

    }
    proc superclass {class_ns superclass} {
        if {[info exists ${class_ns}::super]} {
            error "Only one superclass allowed for a class"
        }
        set sup [uplevel 3 "namespace eval $superclass {namespace current}"]
        set ${class_ns}::super $sup
        # We store the subclass in the super so it can be destroyed
        # if the super is destroyed.
        set ${sup}::subclasses($class_ns) 1
    }
    proc constructor {class_ns params body} {
        method $class_ns constructor $params $body
    }
    proc destructor {class_ns body} {
        method $class_ns destructor {} $body
    }
    proc export {args} {
        # Nothing to do, all methods are exported anyways
        # Command is here for compatibility only
    }
}

# Namespace in which commands used in objects methods are defined
# (self, my etc.)
namespace eval metoo::object {
    proc next {args} {
        upvar 1 _this this;     # object namespace

        # Figure out what class context this is executing in. Note
        # we cannot use _this in caller since that is the object namespace
        # which is not necessarily related to the current class namespace.
        set class_ns [namespace parent [uplevel 1 {namespace current}]]
        
        # Figure out the current method being called
        set methodname [namespace tail [lindex [uplevel 1 {info level 0}] 0]]
        
        # Find the next method in the class hierarchy and call it
        while {[info exists ${class_ns}::super]} {
            set class_ns [set ${class_ns}::super]
            if {[llength [info commands ${class_ns}::methods::$methodname]]} {
                return [uplevel 1 [list ${class_ns}::methods::$methodname $this] $args]
            }
        }
        
        error "'next' command has no receiver in the hierarchy for method $methodname"
    }

    proc self {{what object}} {
        upvar 1 _this this
        switch -exact -- $what {
            namespace { return $this }
            object { return [set ${this}::_(name)] }
            default {
                error "Argument '$what' not understood by self method"
            }
        }
    }

    proc my {methodname args} {
        # We insert the object namespace as the first parameter to the command.
        # This is passed as the first parameter "_this" to methods. Since
        # "my" can be only called from methods, we can retrieve it fro
        # our caller.
        upvar 1 _this this;     # object namespace

        set class_ns [namespace parent $this]

        set meth [::metoo::_locate_method $class_ns $methodname]
        if {$meth ne ""} {
            # We need to invoke in the caller's context so upvar etc. will
            # not be affected by this intermediate method dispatcher
            return [uplevel 1 [list $meth $this] $args]
        }

        set meth [::metoo::_locate_method $class_ns "unknown"]
        if {$meth ne ""} {
            # We need to invoke in the caller's context so upvar etc. will
            # not be affected by this intermediate method dispatcher
            return [uplevel 1 [list $meth $this $methodname] $args]
        }

        error "Unknown method $methodname"
    }
}

# Given a method name, locate it in the class hierarchy. Returns
# fully qualified method if found, else an empty string
proc metoo::_locate_method {class_ns methodname} {
    # See if there is a method defined in this class.
    # Breakage if method names with wildcard chars. Too bad
    if {[llength [info commands ${class_ns}::methods::_m_$methodname]]} {
        # We need to invoke in the caller's context so upvar etc. will
        # not be affected by this intermediate method dispatcher
        return ${class_ns}::methods::_m_$methodname
    }

    # No method here, check for super class.
    while {[info exists ${class_ns}::super]} {
        set class_ns [set ${class_ns}::super]
        if {[llength [info commands ${class_ns}::methods::_m_$methodname]]} {
            return ${class_ns}::methods::_m_$methodname
        }
    }

    return "";                  # Not found
}

proc metoo::_new {class_ns cmd args} {
    variable next_id

    # IMPORTANT:
    # object namespace *must* be child of class namespace. 
    # Saves a bit of bookkeeping. Putting it somewhere else will require
    # changes to many other places in the code.
    set objns ${class_ns}::o#[incr next_id]

    switch -exact -- $cmd {
        create {
            if {[llength $args] < 1} {
                error "Insufficient args, should be: class create CLASSNAME ?args?"
            }
            # TBD - check if command already exists
            # Note objname must always be fully qualified
            set objname ::[string trimleft "[uplevel 1 "namespace current"]::[lindex $args 0]" :]
            set args [lrange $args 1 end]
        }
        new {
            set objname $objns
        }
        default {
            error "Unknown command '$cmd'. Should be create or new."
        }
    }

    # Create the namespace. The array _ is used to hold private information
    namespace eval $objns {
        variable _
    }
    set ${objns}::_(name) $objname

    # When invoked by its name, call the dispatcher
    interp alias {} $objname {} ${class_ns}::_call $objns

    # Invoke the constructor
    if {[catch {
        eval [list $objname constructor] $args
    } msg]} {
        # Undo what we did
        set erinfo $::errorInfo
        set ercode $::errorCode
        rename $objname ""
        namespace delete $objns
        error $msg $erinfo $ercode
    }

    # Set up trace to track when the object is renamed/destroyed
    trace add command $objname {rename delete} [list [namespace current]::_trace_object_renames $objns]

    return $objname
}

proc metoo::_trace_object_renames {objns oldname newname op} {
    if {$op eq "rename"} {
        set ${objns}::_(name) $newname
    } else {
        $oldname destroy
    }
}

proc metoo::_class_cmd {class_ns cmd args} {
    switch -exact -- $cmd {
        create -
        new {
            return [uplevel 1 [list [namespace current]::_new $class_ns $cmd] $args]
        }
        destroy {
            # Destroy all objects belonging to this class
            foreach objns [namespace children ${class_ns} o#*] {
                [set ${objns}::_(name)] destroy
            }
            # Destroy all classes that inherit from this
            foreach child_ns [array names ${class_ns}::subclasses] {
                # Child namespace is also subclass command
                $child_ns destroy
            }
            namespace delete ${class_ns}
            rename ${class_ns} ""
        }
        default {
            error "Unknown command '$cmd'. Should be create, new or destroy."
        }
    }
}

proc metoo::class {cmd cname definition} {
    variable next_id

    if {$cmd ne "create"} {
        error "Syntax: class create CLASSNAME DEFINITION"
    }

    if {[uplevel 1 "namespace exists $cname"]} {
        error "can't create class '$cname': namespace already exists with that name."
    }

    # Resolve cname into a namespace in the caller's context
    set class_ns [uplevel 1 "namespace eval $cname {namespace current}"]
    
    if {[llength [info commands $class_ns]]} {
        # Delete the namespace we just created
        namespace delete $class_ns
        error "can't create class '$cname': command already exists with that name."
    }

    # Define the commands/aliases that are used inside a class definition
    foreach procname [info commands [namespace current]::define::*] {
        interp alias {} ${class_ns}::[namespace tail $procname] {} $procname $class_ns
    }

    # Define the built in commands callable within class instance methods
    foreach procname [info commands [namespace current]::object::*] {
        interp alias {} ${class_ns}::methods::[namespace tail $procname] {} $procname
    }

    # Define the class
    if {[catch {
        namespace eval $class_ns $definition
    } msg ]} {
        namespace delete $class_ns
        error $msg $::errorInfo $::errorCode
    }

    # Define the destroy method for the class
    namespace eval $class_ns {
        method destroy {} {
            my destructor
            # Remove trace on command rename/deletion.
            # ${_this}::_(name) contains the object's current name on
            # which the trace is set
            trace remove command [set ${_this}::_(name)] {rename delete} [list ::metoo::_trace_object_renames $_this]
            rename [self object] ""
            namespace delete $_this
            return
        }
        method variable {args} {
            if {[llength $args]} {
                set cmd [list upvar 0]
                foreach varname $args {
                    lappend cmd ${_this}::$varname $varname
                }
                uplevel 1 $cmd
            }
        }
    }

    # Also define the call dispatcher within the class.
    # TBD - not sure this is actually necessary any more
    namespace eval ${class_ns} {
        proc _call {objns methodname args} {
            # Note this duplicates the "my" code but cannot call that as
            # it adds another frame level which interferes with uplevel etc.

            set class_ns [namespace parent $objns]

            # We insert the object namespace as the first param to the command.
            # This is passed as the first parameter "_this" to methods.

            set meth [::metoo::_locate_method $class_ns $methodname]
            if {$meth ne ""} {
                # We need to invoke in the caller's context so upvar etc. will
                # not be affected by this intermediate method dispatcher
                return [uplevel 1 [list $meth $objns] $args]
            }

            # It is ok for constructor or destructor to be undefined. For
            # the others, invoke "unknown" if it exists

            if {$methodname eq "constructor" || $methodname eq "destructor"} {
                return
            }

            set meth [::metoo::_locate_method $class_ns "unknown"]
            if {$meth ne ""} {
                # We need to invoke in the caller's context so upvar etc. will
                # not be affected by this intermediate method dispatcher
                return [uplevel 1 [list $meth $objns $methodname] $args]
            }

            error "Unknown method $methodname"
        }
    }

    # The namespace is also a command used to create class instances
    interp alias {} $class_ns {} [namespace current]::_class_cmd $class_ns

    return $class_ns
}

namespace eval metoo { namespace export class }

# Simple sample class showing all capabilities. Anything not shown here will
# probably not work. Call as "demo" to use metoo, or "demo oo" to use TclOO.
# Output should be same in both cases.
proc ::metoo::demo {{ns metoo}} {
    ${ns}::class create Base {
        constructor {x y} { puts "Base constructor ([self object]): $x, $y"
        }
        method m {} { puts "Base::m called" }
        method n {args} { puts "Base::n called: [join $args {, }]"; my m }
        method unknown {methodname args} { puts "Base::unknown called for $methodname [join $args {, }]"}
        destructor { puts "Base::destructor ([self object])" }
    }

    ${ns}::class create Derived {
        superclass Base
        constructor {x y} { puts "Derived constructor ([self object]): $x, $y" ; next $x $y }
        destructor { puts "Derived::destructor called ([self object])" ; next }
        method n {args} { puts "Derived::n ([self object]): [join $args {, }]"; eval next $args}
        method put {val} {my variable var ; set var $val}
        method get {varname} {my variable var ; upvar 1 $varname retvar; set retvar $var}
    }

    Base create b dum dee;      # Create named object
    Derived create d fee fi;    # Create derived object
    set o [Derived new fo fum]; # Create autonamed object
    $o put 10;                  # Use of instance variable
    $o get v;                   # Verify correct frame level ...
    puts "v:$v";                # ...when calling methods
    b m;                        # Direct method
    b n;                        # Use of my to call another method
    $o m;                       # Inherited method
    $o n;                       # Overridden method chained to inherited
    $o nosuchmethod arg1 arg2;  # Invoke unknown
    $o destroy;                 # Explicit destroy
    rename b "";                # Destroy through rename
    Base destroy;               # Should destroy object d, Derived, Base
}

