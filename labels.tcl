
set labels {}               ; # Holds a dict of lists of resolve forward refs
set LABEL(.) 0              ; # Dot is just a special label that advances as we assemble

# Catch unknown commands in the .rva file and treat them as labels if they end in ':'
#
rename unknown _unknown
proc unknown { args } {
    switch -regex -- [lindex $args 0] {
        {[0-9a-zA-Z_]+:} { 
            : [string range [lindex $args 0] 0 end-1] {*}[lrange $args 1 end]
        }
        default {
            _unknown {*}$args
        }
    }
}

# Introduce a label in the .rva file
#
proc : { name args } {
    set ::LABEL($name) $::LABEL(.)

    # The list of forward refs to this label has a dict with the 
    # address and immediate type of each ref.  Read the word at
    # the address, evaluate the immediate bits with the now known
    # value of the label and store it back to address
    #
    foreach label [dict get? $::labels $name] {
        dict with $label {
            set word [ld_uword $addr]
            set word [expr { $word | [::tcl::mathfunc::$type $::LABEL(.)] }]
            if { $word & 0x03 } {
                st_uword $addr $word
            } else {
                st_uhalf $addr $word
            }
        }
    }
    dict unset ::labels $name

    if { [llength $args] } {
        {*}$args
    }
}

namespace eval ::tcl::mathfunc {
    proc match_label { value } {
        switch -regex -- $value {
            {.*[a-zA-z].*} {
                if { [info exists ::LABEL($value)] } {
                    return $::LABEL($value)
                }

                return 0x7FFFFF
            }
        }
        return $value
    }

    # Look up a label while generating an immediate value
    #
    proc label { value type } {
        switch -regex -- $value {
            {[0-9]+b} {                     # A back ref must be know now.

                set value [string range $value 0 end-1]
                if { ![info exists ::LABEL($value)] } {
                    error "unkown back label ref for $value"
                }
            }
            {[0-9]+f} {                     # A forward ref is added to the labels lists and returns 0

                set value [string range $value 0 end-1] 
                dict lappend ::labels $value [dict create  addr $::LABEL(.) type $type]
                return 0
            }
            {[a-zA-Z_][a-zA-Z_0-9]*} {      #  A normal label might exist of might be a forward ref.

                if { [info exists ::LABEL($value)] } {
                    return [expr { $::LABEL($value) - $::LABEL(.) }]
                } else {
                    dict lappend ::labels $value [dict create  addr $::LABEL(.) type $type]
                    return 0
                }
            }
        }
        return $value
    }
}
