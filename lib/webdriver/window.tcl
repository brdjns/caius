#
# Caius Functional Testing Framework
#
# Copyright (c) 2013, Tobias Koch <tobias.koch@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modifi-
# cation, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
# NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUD-
# ING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUD-
# ING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFT-
# WARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

package require Itcl
package require OOSupport
package require Error
package require cmdline

namespace eval WebDriver {

    ::itcl::class Window {

        common attributes {
            { string               handle  ""    rw }
            { ::WebDriver::Session session null  rw }
        }

        # these are not serializable
        private variable _cookies

        constructor {{handle ""} {session ""}} {
            OOSupport::init_attributes

            set _handle  $handle
            set _session $session
            set _cookies {}
        }

        destructor {
            foreach {name cookie} $_cookies {
                ::itcl::delete object $cookie
            }
        }

        # accessor functions and JSON support
        OOSupport::bless_attributes -json_support -collapse_underscore \
            -skip_undefined

        method select_frame {{id null}} {
            if {[::itcl::is object -class ::WebDriver::WebElement $id]} {
                set json "{ \"id\": \"[$id to_json]\" }"
            } else {
                set json "{ \"id\": \"$id\" }"
            }

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "select frame [string trim [string map {"\n" " "} $json]]"
            }

            set response [::WebDriver::Protocol::dispatch -query $json \
                [$_session session_url]/frame]
            ::itcl::delete object $response
        }

        method focus {} {
            set json "{ \"name\": \"$_handle\" }"
            set interval 5

            for {set i 0} {$i < 10} {incr i} {
                if {[[$_session active_window] handle]  ne [$this handle]} {

                    if {[$_session logging_enabled]} {
                        ::WebDriver::log [$_session session_id] "focus window $_handle"
                    }

                    set response [::WebDriver::Protocol::dispatch -query $json \
                        [$_session session_url]/window]
                    ::itcl::delete object $response

                    after $interval
                    set interval [expr $interval * 2]
                } else {
                    break
                }
            }

            if {$i == 10} {
                raise ::WebDriver::UnknownError "failed to activate window."
            }
        }

        method close {} {
            set all_windows [$_session all_windows]

            if {[llength $all_windows] == 1} {
                raise ::WebDriver::CloseSessionWindowError \
                    "the last session window must not be closed."
            }

            # before deleting it, make sure it's focused
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] "closing window '$_handle'"
            }

            set response [::WebDriver::Protocol::dispatch -method DELETE \
                [$_session session_url]/window]
            ::itcl::delete object $response
        }

        method set_size {w h} {
            set json "{\"width\": $w, \"height\": $h}"
            set response [::WebDriver::Protocol::dispatch -query $json \
                [$_session session_url]/window/$_handle/size]

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "set window size to ${w}x${h}"
            }

            # there can be a delay due to window manager animation etc.
            set interval 50
            for {set i 0} {$i < 5} {incr i} {
                after $interval
                set interval [expr $interval * 2]

                lassign [$this size] x y
                if {($x == $w) && ($y == $h)} {
                    break
                }
            }

            if {$i == 5} {
                raise ::WebDriver::UnknownError "failed to resize window."
            }

            ::itcl::delete object $response
        }

        method size {} {
            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/window/$_handle/size]

            array set value [$response value]
            ::itcl::delete object $response

            return [list $value(width) $value(height)]
        }

        method set_position {x y} {
            set json "{\"x\": $x, \"y\": $y}"
            set response [::WebDriver::Protocol::dispatch -query $json \
             [$_session session_url]/window/$_handle/position]

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "set window position to (${x}, ${y})"
            }

            # there can be a delay due to window manager animation etc
            set interval 50
            for {set i 0} {$i < 5} {incr i} {
                after $interval
                set interval [expr $interval * 2]

                lassign [$this position] x1 y1
                if {($x == $x1) && ($y == $y1)} {
                    break
                }
            }
            if {$i == 5} {
                raise ::WebDriver::UnknownError "failed to reposition window."
            }

            ::itcl::delete object $response
        }

        method position {} {
            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/window/$_handle/position]

            array set value [$response value]
            ::itcl::delete object $response

            return [list $value(x) $value(y)]
        }

        method maximize {} {
            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/window/$_handle/maximize]

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "maximize window"
            }

            after 100
            ::itcl::delete object $response
        }

        method name {} {
            $this focus
            set rval [$this execute "window.name"]

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "window name is '$rval'"
            }

            return $rval
        }

        method set_url {url} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "open '$url'"
            }
 
            set json "{ \"url\": \"$url\" }"
            set response [::WebDriver::Protocol::dispatch -query $json \
                [$_session session_url]/url]
            ::itcl::delete object $response
        }

        method url {} {
            $this focus

            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/url]

            set url [$response value]
            ::itcl::delete object $response

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "current url '$url'"
            }

            return $url
        }

        method forward {} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "go forward in history"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/forward]
            ::itcl::delete object $response
        }

        method back {} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "go back in history"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/back]
            ::itcl::delete object $response
        }

        method refresh {} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "refresh"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/refresh]
            ::itcl::delete object $response
        }

        method execute {script args} {
            $this focus

            set script [::OOSupport::json_escape_chars $script]
            set json "{ \"script\": \"$script\", \"args\": \[[join $args ", "]\] }"

            if {[$_session logging_enabled]} {
                set log_str "execute script [string range $script 0 50]"
                if {[string length $script] > 50} {
                    append log_str "..."
                }
                ::WebDriver::log [$_session session_id] $log_str
            }

            set response [::WebDriver::Protocol::dispatch \
                -query $json \
                [$_session session_url]/execute]

            # return TCL'ized JSON object or single value
            set result [$response value]

            ::itcl::delete object $response
            return $result
        }

        method execute_async {args} {
            set joinable     ""
            set result_array ""
            set result_var   ""
            set error_array  ""
            set error_var    ""

            # read options
            while {[string index [lindex $args 0] 0] == "-"} {
                set opt [lindex $args 0]

                switch $opt {
                    "-joinable" {
                        set joinable "-joinable"
                        set args [lreplace $args 0 0]
                    }
                    "-result" {
                        set result_array [lindex $args 1]
                        set result_var   [lindex $args 2]
                        set args         [lreplace $args 0 2]
                    }
                    "-error" {
                        set error_array [lindex $args 1]
                        set error_var   [lindex $args 2]
                        set args        [lreplace $args 0 2]
                    }
                    default {
                        error "execute_async: unknown option '$opt'"
                    }
                }
            }

            $this focus

            set script [lindex $args 0]
            set args   [lreplace $args 0 0]

            if {[$_session logging_enabled]} {
                set log_str "execute script asynchronously\
                    [::OOSupport::json_escape_chars \
                        [string range $script 0 50]]"

                if {[string length $script] > 50} {
                    append log_str "..."
                }
                ::WebDriver::log [$_session session_id] $log_str
            }

            # execute script in new thread
            set thread_id [if 1 "::thread::create $joinable {
                package require Itcl
                package require WebDriver
                package require Error
                package require Thread

                except {
                    set session \[\[::WebDriver::Session #auto] from_json \
                        {[$_session to_json]}]

                    \$session set_cloned true
                    set result \[namespace inscope ::WebDriver::Session \$session __execute_async {$script} {*}$args]

                    if {(\"$result_array\" ne \"\") && (\"$result_var\" ne \"\")} {
                        ::tsv::set $result_array $result_var \$result
                    }
                } e {
                    ::Exception {
                        if {(\"$error_array\" ne \"\") && (\"$error_var\" ne \"\")} {
                            ::tsv::set $error_array $error_var \[\$e msg]
                        }
                        ::itcl::delete object \$e
                    }
                } final {
                    if {\[info exists session]} {
                        ::itcl::delete object \$session
                    }
                }
            }"]

            return $thread_id
        }

        method screenshot {args} {
            set decode false

            # read options
            set opt [lindex $args 0]
            if {$opt eq "-decode"} {
                set decode true
                set args [lreplace $args 0 0]
            }

            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] "take screenshot"
            }

            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/screenshot]

            if {$decode} {
                set result [::base64::decode [$response value]]
            } else {
                set result [$response value]
            }
 
            ::itcl::delete object $response
            return $result
        }

        method cookies {} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "read all cookies"
            }

            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/cookie]

            array set c_idx {}
            array set session_cookies $_cookies
            set result {}

            # register or update all session cookies
            foreach {c_json} [$response value] {
                set c_obj [::itcl::code [::WebDriver::Cookie #auto]]
                $c_obj from_tcl $c_json

                set c_name "[$c_obj domain]+[$c_obj name]"
                set c_idx($c_name) 1

                if {[info exists session_cookies($c_name)]} {
                    $session_cookies($c_name) from_tcl $c_json
                    ::itcl::delete object $c_obj
                } else {
                    set session_cookies($c_name) $c_obj
                }

                lappend result $session_cookies($c_name)
            }
            ::itcl::delete object $response

            # delete cookies not visible to current page
            foreach {c_name c_obj} [array get session_cookies] {
                if {![info exists c_idx($c_name)]} {
                    delete $session_cookies($c_name)
                    unset session_cookies($c_name)
                }
            }

            set _cookies [array get session_cookies]
            return $result
        }

        method set_cookie {args} {
            set options {
                {path.arg      "/"  "the cookie path"                                }
                {domain.arg    ""   "the cookie domain"                              }
                {secure             "whether the cookie is a secure cookie"          }
                {http_only          "whether the cookie is an http only cookie"      }
                {expiry.arg    null "expiry in seconds since midnight 1 Jan 1970 UTC"}
            }

            array set params [::cmdline::getoptions args $options]

            if {[llength $args] != 2} {
                error "method set_cookie requires two non-keyword\
                    arguments for cookie name and value"
            }

            set name  [lindex $args 0]
            set value [lindex $args 1]

            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "set cookie '$name'"
            }

            if {$params(domain) eq ""} {
                array set url [::uri::split [$this url]]
                set params(domain) $url(host)
            }

            set c_name "${params(domain)}+${name}"
            array set session_cookies $_cookies

            if {[info exists session_cookies($c_name)]} {
                set cookie $session_cookies($c_name)
                $cookie set_value $value
            } else {
                set cookie [::WebDriver::Cookie #auto $name $value]
                set session_cookies($c_name) $cookie
            }

            $cookie set_domain    $params(domain)
            $cookie set_path      $params(path)
            $cookie set_secure    $params(secure)
            $cookie set_http_only $params(http_only)
            $cookie set_expiry    $params(expiry)

            set json "{\"sessionId\": \"[$_session session_id]\", \"cookie\": [$cookie to_json]}"

            except {
                set response [::WebDriver::Protocol::dispatch \
                    -query $json [$_session session_url]/cookie]
                ::itcl::delete object $response
            } e {
                ::Exception {
                    ::itcl::delete object $cookie
                    reraise $e
                }
            }

            set _cookies [array get session_cookies]
            return $cookie
        }

        method delete_cookie {cookie_name} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "delete cookie '$cookie_name'"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method DELETE \
                [$_session session_url]/cookie/$cookie_name]
            ::itcl::delete object $response
        }

        method purge_cookies {} {
            $this focus

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "purge cookies"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method DELETE \
                [$_session session_url]/cookie]
            ::itcl::delete object $response

            foreach {name cookie} $_cookies {
                ::itcl::delete object $cookie
            }
        }

        method page_source {} {
            $this focus
            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/source]
            set src [$response value]
            ::itcl::delete object $response
            return $src
        }

        method page_title {} {
            $this focus
            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/title]
            set title [$response value]
            ::itcl::delete object $response

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "page title is '$title'"
            }

            return $title
        }

        method element {by locator} {
            $this focus
            return [namespace inscope ::WebDriver::Session \
                $_session __elements $by "$locator" null true]
        }

        method elements {by locator} {
            $this focus
            return [namespace inscope ::WebDriver::Session \
                $_session __elements $by "$locator" null false]
        }

        method active_element {} {
            #$this focus

            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/element/active]
            set element [::itcl::code \
                [[::WebDriver::WebElement #auto $_session] from_tcl \
                    [$response value]]]
            ::itcl::delete object $response

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "active element: [$element ELEMENT]"
            }

            return $element
        }

        method orientation {} {
            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/orientation]

            set orientation [$response value]
            ::itcl::delete object $response

            return [string tolower $orientation]
        }

        method set_orientation {orientation} {
            set orientation [string toupper $orientation]

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "set orientation to $orientation"
            }

            set interval 50
            for {set i 0} {$i < 5} {incr i} {
                set response [::WebDriver::Protocol::dispatch \
                    -query $orientation \
                    [$_session session_url]/orientation]
                ::itcl::delete object $response

                after $interval
                set interval [expr $interval * 2]

                set actual_orientation [$this orientation]
                if {$actual_orientation == $orientation} {
                    break
                }
            }

            if {$i == 5} {
                raise ::WebDriver::UnknownError "failed to change orientation."
            }
        }

        method alert_text {} {
            set response [::WebDriver::Protocol::dispatch \
                [$_session session_url]/alert_text]

            set alert_text [$response value]
            ::itcl::delete object $response

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "alert text: '$alert_text'"
            }

            return $alert_text
        }

        method alert_send_text {text} {
            set text OOSupport::json_escape_chars $text
            set json "{\"text\": \"$text\"}"

            set response [::WebDriver::Protocol::dispatch \
                -query $json \
                [$_session session_url]/alert_text]
            ::itcl::delete object $response
        }

        method accept_alert {} {
            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "accept alert"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/accept_alert]
            ::itcl::delete object $response
        }

        method dismiss_alert {} {
            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "dismiss alert"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/dismiss_alert]
            ::itcl::delete object $response
        }

        method move_to {xoffset yoffset} {
            set json "{ \"xoffset\": $xoffset, \"yoffset\": $yoffset }"

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "move mouse (x+$xoffset, y+$yoffset)"
            }

            set response [::WebDriver::Protocol::dispatch \
                -query $json \
                [$_session session_url]/moveto]
            ::itcl::delete object $response
        }

        method button_down {{button left}} {
            array set button2num {
                left   0
                middle 1
                right  2
            }

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "press $button button"
            }

            set button $button2num($button)
            set json "{ \"button\": $button }"

            set response [::WebDriver::Protocol::dispatch \
                -query $json \
                [$_session session_url]/buttondown]
            ::ictl::delete $response
        }

        method button_up {{button left}} {
            array set button2num {
                left   0
                middle 1
                right  2
            }

            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "release $button button"
            }

            set button $button2num($button)
            set json "{ \"button\": $button }"

            set response [::WebDriver::Protocol::dispatch \
                -query $json \
                [$_session session_url]/buttonup]
            ::ictl::delete $response
        }

        method doubleclick {} {
            if {[$_session logging_enabled]} {
                ::WebDriver::log [$_session session_id] \
                    "double click"
            }

            set response [::WebDriver::Protocol::dispatch \
                -method POST \
                [$_session session_url]/doubleclick]
            ::itcl::delete $response
        }
    }
}

