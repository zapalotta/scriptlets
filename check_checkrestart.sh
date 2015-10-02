#!/bin/sh
#
# ============================== SUMMARY =====================================
#
# Program : check_checkrestart.sh
# Version : 0.2
# Date    : January 28 2015
# Author  : Dirk Doerflinger - dirk(at)doerflinger(dot)org
# Summary : This is a Nagios plugin to check if any processes are still using 
#           old versions of updated libraries. I needs check_restart from
#           debian-goodies. Debian only!
#
# Licence : MIT 
#
# =========================== PROGRAM LICENSE =================================
#
# Copyright (C) 2014 Dirk Doerflinger
#
# Permission is hereby granted, free of charge, to any person obtaining a copy 
# of this software and associated documentation files (the "Software"), to deal 
# in the Software without restriction, including without limitation the rights 
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
# SOFTWARE.
#
# ===================== INFORMATION ABOUT THIS PLUGIN =========================
#
# This nagios plugin uses the checkrestart script from the debian-goodies to 
# check if any processes are still using old version of updated libs.
#
# This program is written and maintained by:
#   Dirk Doerflinger - dirk(at)doerflinger(dot)org
#   Landry MINOZA - lminoza[at]mgi.fr - v0.2
#
# ============================= SETUP NOTES ====================================
#
# Copy this file to your Nagios plugin folder, e.g. /usr/lib64/nagios/plugins/
# or /usr/local/lib/nagios/plugins. 
# Make sure it is executable for the nagios user
#
# You need to have debian-goodies installed, which provides 
# /usr/sbin/checkrestart
# 
# ./check_checkrestart.sh -w <warning> -c <critical>
#
# Where <warning> and <critical> is the number of processes found triggering
#
# ========================= SETUP EXAMPLES ==================================
#
# ===== Nagios command ======================================================
# define command{
#       command_name    check_checkrestart
#       command_line    $USER1$/check_checkrestart.sh -w $ARG1$ -c $ARG2$
#       }
#
# ===== Nagios service ======================================================
# define service{
#       use                     generic-service
#       host_name               debian-server
#       service_description     Debian obsolete libraries used
#       check_command           check_checkrestart!3!1
#       normal_check_interval   3
#       retry_check_interval    1
#       }
#
# ===== NRPE check ==========================================================
# command[check_checkrestart]=/usr/local/lib/nagios/plugins/check_checkrestart.sh
#
# ===== Sudoers conf ========================================================
# User_Alias CHECK_CHECKRESTART=nagios
# Defaults:CHECK_CHECKRESTART !requiretty
# CHECK_CHECKRESTART ALL=(root) NOPASSWD: /usr/sbin/checkrestart
#
# ================================ REVISION ==================================
#
# 0.1 Initial release
# 0.2 Add -p option for debian >= 7, use sudo if needed and add nrpe example
#
# ============================================================================
package=check_checkrestart

# Path to racadm binary
checkrestart=/usr/sbin/checkrestart

# use sudo for nrpe server running under nagios user
if [ $EUID -ne 0 ] ; then
	checkrestart="sudo ${checkrestart}"
fi

# use -p for newer versions
$checkrestart -h  2>&1 | grep -q vhpa
if  [ $? -eq 0 ] ; then
	checkrestart="${checkrestart} -p"
fi

# default values for warnings and critical
warning=1
critical=4

# initialize an exit code
exitcode=0

# parse parameters
while test $# -gt 0; do
    case "$1" in
        -h|--help)
            echo "$package - Check obsolete libraries still in use"
            echo " "
            echo "Needs debian-goodies!"
            echo " "
            echo "$package [options]"
            echo " "
            echo "options:"
            echo "-h, --help                show brief help"
            echo "-w, --warning             Warning number of processes using old libraries. Default: $warning" 
            echo "-c, --critical            Crtitical number of processes using old libraries. Default: $critical"
            exit 0
            ;;
        -w|--warning)
            shift
            if test $# -gt 0; then
                export warning=$1
            else
                echo "no warning level specified, defaulting to $warning"
            fi
            shift
            ;;
        -c|--critical)
            shift
            if test $# -gt 0; then
                export critical=$1
            else
                echo "no critical level specified, defaulting to $critical"
            fi
            shift
            ;;
    esac
done

result=$($checkrestart | grep Found | awk '{print $2}')

# Make sure we have a result. If we don't that usually means that the connection failed, e.g. wrom hostname or credentials
if [ -z $result ]; then
    echo "CRITICAL - No data, maybe $checkrestart missing?"
    exit 2
fi

if [ $result -ge $critical ]; then
    exitcode=2
elif [ $result -ge $warning ]; then
    exitcode=1
else
    exitcode=0
fi

    
case $exitcode in 
    0)
	echo "OK: no service or process to restart | to_restart=$result"
	exit 0
	;;
    
    1)
	echo "WARNING: $result services or processes to restart | to_restart=$result"
	exit 1
	;;
    
    2)
	echo "CRTITICAL: $result services or processes to restart | to_restart=$result"
	exit 2
	;;
    *)
	echo "UNKNOWN - Weird data"
	exit 3
	;;
esac

#EOF
