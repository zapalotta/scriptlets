#!/bin/bash
#
# ============================== SUMMARY =====================================
#
# Program : check_m1000e.sh
# Version : 0.1
# Date    : March 14 2014
# Author  : Dirk Doerflinger - dirk(at)doerflinger(dot)org
# Summary : This is a nagios plugin that checks the status M1000e blade chassis
#           using DELL racadm
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
# This plugin checks the status of fans, ambient temperature and power supplies
# of DELL blade enclosures with the type M1000E using racadm
# It will return OK, WARNING, ERROR or UNKNOWN together with the correspondig 
# exit code 0, 1, 2, 3 in case of error.
# Fans are monitored if they provide an error state through racadm and also
# by calculating a percentage of actual RPMs vs. maximal RPMs defined by -w
# and -c parameters. Performance data consists of actual RPMs of each fan
# Ambient temperature is monitored if there is an error state through racadm and 
# by comparing the actual value to given -w and -c parameters
# Power ist just checked if there is an error state as racadm doesn't return 
# any actual performance data.
# There is a plugin called check_dell_bladechassis.pl by Trond H. Amundsen 
# <t.h.amundsen@usit.uio.no> which uses SNMP to gain different values.
#
# This program is written and maintained by:
#   Dirk Doerflinger - dirk(at)doerflinger(dot)org
#
# ============================= SETUP NOTES ====================================
#
# Copy this file to your Nagios plugin folder, e.g. /usr/lib64/nagios/plugins/. 
# Make sure it is executable for the nagios user
#
# You must have Dell OpenManage installed on the nagios server There must be a 
# user on the CMC with at least guest status in order
# to query data
# 
# ./check_m1000e.sh -H <host> -u <username> -p <password> -s <sensor> 
#
# Where <sensor> is "fan", "pwr" or "temp"
#
# ========================= SETUP EXAMPLES ==================================
#
# define command{
#       command_name    check_m1000e
#       command_line    $USER1$/check_m1000e.sh -H $HOSTADDRESS$ -s $ARG1$ -u $ARG2$ -p $ARG3$ -w $ARG4$ -c $ARG5$
#       }
#
# define service{
#       use                     generic-service
#       host_name               DELL-SERVER-00
#       service_description     Dell M1000e fans
#       check_command           check_m1000e!fan!monitoruser!monitorpass!90!95
#       normal_check_interval   3
#       retry_check_interval    1
#       }
#
# define service{
#       use                     generic-service
#       host_name               DELL-SERVER-01
#       service_description     Dell M1000e temperature
#       check_command           check_m1000e!temp!monitoruser!monitorpass!30!35
#       normal_check_interval   3
#       retry_check_interval    1
#       }
#
# ================================ REVISION ==================================
#
# 0.1 Initial release
#
# ============================================================================
package=check_m1000e

# Path to racadm binary
racadm=/opt/dell/srvadmin/sbin/racadm

# default values for warnings and critical
warning=90
critical=95
warningtemp=25
criticaltemp=30

# initialize an exit code
exitcode=0

# parse parameters
while test $# -gt 0; do
    case "$1" in
        -h|--help)
            echo "$package - Check M1000e Rack health"
            echo " "
            echo "Needs racadm!"
            echo "Fans and temperature can get performance data, Power doesn't. Temp provides ambient temperature only." 
            echo " "
            echo "ATTN: if run on a system which os not a physical DELL machine, line 12 in $racadm needs to be fixed, use a static SYSID_HEX, like 0x04DB"
            echo " "
            echo "$package -H [hostname] -s [fan|pwr|temp] [options]"
            echo " "
            echo "options:"
            echo "-h, --help                show brief help"
            echo "-H, --hostname            Host to check"
            echo "-u, --username            Username for racadm"
            echo "-p, --password            Password for racadm"
            echo "-s, --sensor              Sensor: fan, pwr, temp"
            echo "-w, --warning             Warning level for fan speed in percent. Default: $warning" 
	    echo "-                         Warning level for temperature in °C. Default: $warning"
            echo "-c, --critical            Crtitical level for fan speed in percent. Default: $critical"
	    echo "                          Crtitical level for temperature in °C. Default: $critical"
            echo "-m, --maxtemp             Temp: Critical alert on maximum ambient temperature. Default: $maxtemp"
            exit 0
            ;;
        -H|--hostname)
            shift
            if test $# -gt 0; then
		export host=$1
            else
                echo "No hostname specified"
                exit 1
            fi
            shift
            ;;
        -u|--username)
            shift
            if test $# -gt 0; then
                export username=$1
            else
                echo "no username specified"
                exit 1
            fi
            shift
            ;;
        -p|--password)
            shift
            if test $# -gt 0; then
                export password=$1
            else
                echo "no password specified"
                exit 1
            fi
            shift
            ;;
        -w|--warning)
            shift
            if test $# -gt 0; then
                export warning=$1
                export warningtemp=$1
            else
                echo "no warning level specified, defaulting to $warning"
            fi
            shift
            ;;
        -c|--critical)
            shift
            if test $# -gt 0; then
                export critical=$1
                export criticaltemp=$1
            else
                echo "no critical level specified, defaulting to $critical"
            fi
            shift
            ;;
        -s|--sensor)
            shift
            if test $# -gt 0; then
                export sensor=$1
            else
                echo "no sensor specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# make sure we have a hostname and a sensor type
if [[ -z "$host" ]]; then
    echo "UNKNOWN - hostname missing!"
    exit 3
fi
if [[ -z "$sensor" ]]; then
    echo "UNKNOWN - sensor missing"
    exit 3
fi

# Get data from racadm
# Output of racadm: FanSpeed
# senType Num sensorname status reading units lc uc
# Output of racadm: Temp
# senType Num sensorname status reading units lc uc
# Output of racadm: PWR
# senType Num sensorname status health

case $sensor in 
fan)
	result=$( $racadm -r $host -u $username -p $password getsensorinfo 2>&1| grep FanSpeed | awk '{print $2","$4","$5","$8"|"}') 
	;;
temp)
	result=$( $racadm -r $host -u $username -p $password getsensorinfo | grep Temp | awk '{print $2","$4","$5","$8"|"}')
	;;
pwr)
	result=$( $racadm -r $host -u $username -p $password getsensorinfo | grep PWR | awk '{print $2","$5",-1|"}')
	;;
esac

# Make sure we have a result. If we don't that usually means that the connection failed, e.g. wrom hostname or credentials
if [[ -z $result ]]; then
    echo "CRITICAL - No data, maybe no connection to $host"
    exit 2
fi

# Customize the Internal Field Separator to easily split  
IFS="|"

# get data, make sure to remove all non printable chars
for i in $result; do 
    case $sensor in
	fan)
	   #fan: compare rpms. Ratio results in compariosn between reading and uc
	    reading=$(echo $i|awk -F',' '{print $3 }' |tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'' ''\n')
	    max=$(echo $i|awk -F',' '{print $4 }' |tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'' ''\n')
	    ratio=$(echo "$reading $max" | awk '{printf "%.2f \n", ($1/$2)*100}')
	    if [ ${ratio/\.*} -gt $warning ]; then
		# Fan speed ratio above warn level 
		exitcode=1
	    fi
	    if [ ${ratio/\.*} -gt $critical ]; then
		# Fan speed ratio above critical level!
		exitcode=2
	    fi
	    ;;
	temp)
	    #temp: compare to $maxtemp
	    reading=$(echo $i|awk -F',' '{print $3 }' |tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'' ''\n')
	    if [ $reading -gt $warningtemp ]; then
		exitcode=1
	    fi
	    if [ $reading -gt $criticaltemp ]; then
		exitcode=2
	    fi
	    ;;
    esac
    #check if we got anything else but 'OK'
    ok=$(echo $i | awk -F',' '{print $2 }' |tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'' ''\n')
    if [[ $ok != OK ]]; then
	# some error
	exitcode=2
    fi
    # create performance data
    no=$(echo $i | awk -F',' '{print $1}'|tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'' ''\n')
    val=$(echo $i | awk -F',' '{print $3}'|tr -d '\001'-'\011''\013''\014''\016'-'\037''\200'-'\377'' ''\n')
    perfdata=$(echo $perfdata$sensor$no'='$val', ')
    if [ $sensor = 'pwr' ]; then
	# Disable perfdata for power, no values
	perfdata=""
    fi
done

unset IFS

case $exitcode in 
    0)
	echo "OK - Chassis Health| $perfdata"
	exit 0
	;;
    
    1)
	echo "WARNING - Chassis Health| $perfdata"
	exit 1
	;;
    
    2)
	echo "CRTITICAL - Health | $perfdata"
	exit 2
	;;
    *)
	echo "UNKNOWN - Weird health data"
	exit 3
	;;
esac

#EOF
