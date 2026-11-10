# Reproduce two Tk-loaded Tcl child interpreter lifecycles on macOS.
#
# SPDX-FileCopyrightText: 2026 nflyernz <319460892+nflyernz@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later

proc mark {message} {
    puts $message
    flush stdout
}

mark "V4: Tcl [info patchlevel]; executable [info nameofexecutable]"
mark "V4: before first child interpreter"
interp create first
mark "V4: after first child interpreter; before Tk load"
mark "V4: first Tk [interp eval first {package require Tk}]"
mark "V4: before first root destroy"
interp eval first {destroy .}
mark "V4: after first root destroy; before interpreter delete"
interp delete first
mark "V4: after first interpreter delete; before second create"
interp create second
mark "V4: after second child interpreter; before Tk load"
mark "V4: second Tk [interp eval second {package require Tk}]"
mark "V4: before second root withdraw"
interp eval second {wm withdraw .}
mark "V4: after second root withdraw; before update idletasks"
interp eval second {update idletasks}
mark "V4: after update idletasks; before second root destroy"
interp eval second {destroy .}
interp delete second
mark "V4: completed"
