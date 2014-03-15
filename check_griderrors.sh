#!/bin/bash
#
# ============================== SUMMARY =====================================
#
# Program : check_griderrors.sh
# Version : 0.1
# Date    : March 14 2014
# Author  : Dirk Doerflinger - dirk(at)doerflinger(dot)org
# Summary : This is a nagios plugin that checks the status of the queues of an
#           SGE (or forks) installation
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
# This plugin checks the status of all queues of an SGE installation, warns 
# when a defined number of queues have errors and logs performance data.
# The host where the script is being executed needs to be a submit or an admin
# host of the SGE installation. NRPE is recommended in this case.
#
# This program is written and maintained by:
#   Dirk Doerflinger - dirk(at)doerflinger(dot)org
#
# ============================= SETUP NOTES ====================================
#
# Use NRPE.
# Copy this file to a submit or admin host of your installation.
# Adapt the paths of installation directly below this comment.
# You will need to set the base path of your SGE installation, the name of your
# SGE cell and the path to the common environment settings file of your 
# installation. 
# If you have overlapping queues (i.e. some nodes belong to more than one queue)
# You will have to ignore some of them, otherwise the total sums of cores will
# be wrong.
# 
# Example to test, run on submit host:
# 
# ./check_griderrors.sh -w 1 -c 2
#
#
# ========================= SETUP EXAMPLES ==================================
#
# define command{
#       command_name    check_griderrors.sh
#       command_line    $USER1$/check_nrpe -H $HOSTADDRESS$ -c check_griderrors
#       }
#
# nrpe.cfg:
# command[check_griderrors]=/usr/lib64/nagios/plugins/check_griderrors.sh -w 1 -c 2
#
# define service{
#       use                     generic-service
#       host_name               submithost01
#       service_description     Check Griderrors
#       check_command           check_griderrors
#       normal_check_interval   3
#       retry_check_interval    1
#       }
#
#
# ================================ REVISION ==================================
#
# 0.1 Initial release
#
# ============================================================================
package=check_griderrors

# Path to SGE installation
export SGE_ROOT=<BASEPATH TO SGE INSTALLATION>
# Name of the SGE cell to be monitored
export SGE_CELL=<NAME OF THE SGE CELL>
# Import environment
source $SGE_ROOT/<NAME OF THE INSTALLATION>/common/settings.sh
# Extension of queues
QEXT=".q"

# List of queues ignored when summing up. Separate by pipes.
IGNORE_QUEUES="<QUEUES.q|TO.q|BE.q|IGNORED.q>"

# Parse command line options
if [ "$#" == "0" ]; then
    echo "No arguments provided"
    exit 3
fi


# parse parameters
while test $# -gt 0; do
    case "$1" in
        -h|--help)
            echo "$package - Check faulty SGE queues"
            echo " "
            echo "Check all queues for errors and get performance data separately for each queue"
            echo " "
            echo "ATTN: The host running this script needs to be a submit or admin node, it is helpful to use NRPE"
            echo " "
            echo "$package -w <warning> -c <critical>"
            echo " "
            echo "options:"
            echo "-h, --help                show brief help"
            echo "-w, --warning             Number of faulty queues (not hosts!) triggering a warning"
            echo "-c, --critical            Number of faulty queues (not hosts!) triggering a critical error"
            exit 0
            ;;
        -w|--warning)
            shift
            if test $# -gt 0; then
                export warning=$1
            else
                echo "no warning level specified"
            fi
            shift
            ;;
        -c|--critical)
            shift
            if test $# -gt 0; then
                export critical=$1
            else
                echo "no critical level specified"
            fi
            shift
            ;;
    esac
done

# Get a list of all queues, filtering doubles
QUEUES=$(qconf -sql | egrep -v -E '($IGNORE_QUEUES)') 

# Get the number of faulty qeues by checking if the state column is different to 0
num_faulty_queues=`qstat -r -u "all" -g c  | grep $QEXT | egrep -v -E '($IGNORE_QUEUES)' | awk '{if ($8 > 0 ) print $0;}' | wc -l`

# Get the total number of used cores 
used_cores=`qstat -r -u "all" -g c  | grep $QEXT | egrep -v -E "($IGNORE_QUEUES)"  | awk '{ SUM += $3 } END {print SUM}'`
# Get the total number of available cores
available_cores=`qstat -r -u "all" -g c  | grep $QEXT | egrep -v -E "($IGNORE_QUEUES)" | awk '{ SUM += $5 } END {print SUM}'`
# Get the total number of cores in all queues
total_cores=`qstat -r -u "all" -g c  | grep $QEXT | egrep -v -E "($IGNORE_QUEUES)"  | awk '{ SUM += $6 } END {print SUM}'`

# Get number of used cores on each queue
all_queue_stats=''
for qs in $QUEUES; do
    ret=`qstat -r -u "all" -g c  | grep $QEXT | grep $qs | awk '{ print $3 }'`
    all_queue_stats+=" $qs=$ret,"
done

# Warning threshold
thresh_warn=-1
# Critical threshold
thresh_crit=-1

perfdata=" | available_cores=$available_cores, used_cores=$used_cores, total_cores=$total_cores, $all_queue_stats"

if  test $num_faulty_queues -ge $critical
then
    echo "CRITICAL: $num_faulty_queues queues have errors"$perfdata
    exit 2
elif test $num_faulty_queues -ge $warning
then
    echo "WARNING: $queues_with_errors queues have errors"$perfdata
    exit 1
else
    echo "OK: All queues are fine"$perfdata
    exit 0
fi
