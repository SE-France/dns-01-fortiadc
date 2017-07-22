#!/usr/bin/expect -f

# Set variables
set certname [lindex $argv 0]
set certkey [lindex $argv 1]
set certcert [lindex $argv 2]
set adom [lindex $argv 3]
set hostname [lindex $argv 4]
set username [lindex $argv 5]
set password [lindex $argv 6]
set timeout 3

set filekey [read -nonewline [open $certkey r]]
set filecert [read -nonewline [open $certcert r]]

# Announce which device we are working on and at what time
send_user "\n"
send_user ">>>>>  Working on $hostname @ [exec date] <<<<<\n"
send_user "\n"

# Don't check keys
spawn ssh -o StrictHostKeyChecking=no $username\@$hostname

# Allow this script to handle ssh connection issues
expect {
    timeout { send_user "\nTimeout Exceeded - Check Host\n"; exit 1 }
    eof { send_user "\nSSH Connection To $hostname Failed\n"; exit 1 }
    "*# " {}
    "*assword:" {
        send -- "$password\n"
    }
}

# If there are adom configured go to the global
# the cert can be used on all adom
if {$adom == 1} {
    send "config global\n"
}

send "config system certificate local\n"
expect {
    default { send_user "\nCan't access to the vdom\n"; exit 1 }
    "*(local) #" {
        send -- "edit '$certname'\n"
        expect {
            default {send_user "\nSomething wrong append (duplicate ?)\n"; exit 1}
            "*Command fail.*" {send_user "\nSomething wrong append (duplicate ?)\n"; exit 1}
            "*) #" {
                send -- "unset private-key\n"
                send -- "unset certificate\n"
                send -- "set private-key '$filekey'\n"
                expect {
                    "*Command fail.*" {
                        send_user "\nSomething wrong append (wrong cert files)\n";
                        send -- "next\n";
                        exit 1
                    }
                    default {}
                }
                send -- "set certificate '$filecert'\n"
                expect {
                    "*Command fail.*" {
                        send_user "\nSomething wrong append (wrong cert files)\n";
                        send -- "next\n";
                        exit 1
                    }
                    default {}
                }
                send -- "next\n"
                expect {
                    "*Command fail.*" {send_user "\nSomething wrong append (???)\n"; exit 1}
                    default {}
                }
            }
        }
        send -- "end\n"
    }
}

send -- "exit\n"
exit 0