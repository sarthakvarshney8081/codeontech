#!/bin/bash
# vmutil.sh
# Script to manage VMWare virtual machines using the vmrun utility
# Author: Gary Childers	2009-03-13	Version 1.8
# Usage: vmutil.sh < list | start | status | down | stop | reset > [ < VM or group name > ]

#----------------------------------------------------------------------------#
## Set required parameters
USAGE0="Usage: vmutil.sh <action> [ < VM or group name > ]"
USAGE1="Valid actions: < list | start | status | down | stop | reset >"
SCRIPT=vmutil.sh
SCRIPTDIR=/home/VM/scripts
CONFFILE=vmutil.conf
VMRUN=/usr/bin/vmrun
TYPE=server

## Set VM environment-specific variables from a separate config file
if [ -f $SCRIPTDIR/$CONFFILE ]; then
  . $SCRIPTDIR/$CONFFILE
else
  echo "Configuration file $SCRIPTDIR/$CONFFILE missing!"
  exit 1
fi

## Ensure that mandatory variables are set in the config file
MANDATORY="HOST PORT STOREGRP1 ALLVMS"
for VAR in $MANDATORY; do
  if  [ "`eval echo '${'$VAR'}'`" = "" ]; then
    echo "Variable $VAR must have a value in $CONFFILE"
    exit 1
  fi
done

## Set parameters passed from the command line
ACTION=$1
VMLIST=$2

## Set additional required global parameters
ALLVMNAMES=`for VM in $ALLVMS; do eval echo '${'$VM"_NAM"'}'; done`

#----------------------------------------------------------------------------#
## Define functions

function LCASE()
{
  ## Function to translate strings to lowercase
  ## Requires input variable: 1-(string)
  echo $1 | tr [:upper:] [:lower:]
}

function ERROROUT()
{
  ## Function to echo error message(s) and exit script
  ## Requires input variables: 1,2,3-(error messages)
  echo $1
  if [ "$2" != "" ]; then echo $2; fi
  if [ "$3" != "" ]; then echo $3; fi
  exit 1
}

function VALIDATEVMNAME()
{
  ## Validate VM Group Name
  for VMGROUP in $VMGROUPS; do
    if [ "$(LCASE $1)" = "$(LCASE $VMGROUP)" ]; then
      TARGETVMS=`eval echo '${'$VMGROUP'}'`
      return 1
    fi
  done
  ## Validate VM name
  for VM in $ALLVMS; do
    VMNAME=`eval echo '${'$VM"_NAM"'}'`
    if [ "$(LCASE $1)" = "$(LCASE $VMNAME)" ]; then
      TARGETVMS=$VM
      return 1
    fi
  done
}

function NOBLANK()
{
  ## Echo error and exit if input is blank
  ## Requires input variables: 1-(input variable), 2-(variable description)
  if [ "$1" = "" ]; then
    ERRMSG1="Blank $2 is not allowed"
    ERROROUT "$ERRMSG1"
  fi
}

function CHECKAUTH()
{
  ## Prompt for username and password, if not provided
  ## Requires input variables: 1-[ Host | Guest ], 2-(username_var), 3-(password_var)
  if [ "`eval echo '${'$2'}'`" = "" ]; then
    read -p "Enter the $1 auth user name: " $2
    NOBLANK "`eval echo '${'$2'}'`" username
  fi
  if [ "`eval echo '${'$3'}'`" = "" ]; then
    read -p "Enter the $1 password for `eval echo '${'$2'}'`: " -s $3
    echo ""
    NOBLANK "`eval echo '${'$3'}'`" password
  fi
}

function VMLISTSTATUS()
{
  ## Execute vmrun to list the currently running VMs
  $VMRUN -T $TYPE -h $HOST:$PORT/sdk -u $AUTHUSER -p $AUTHPWD list
}

function CHECKIFRUNNING()
{
  ## Check if the current VM is running
  ## Requires input variables: 1-$VM_VMX
  STOREGRP=`echo "$1" | cut -d" " -f1`
  for LISTVM in $ACTIVEVMS; do
    if [ "$STOREGRP $LISTVM" = "$1" ]; then return 1; fi
  done
}

function VMRUNACTION()
{
  ## Execute the specified action (start, stop) using vmrun
  ## Requires input variables: 1-$ACTION, 2-$VM_VMX
###Debug###
#  echo "$VMRUN -T $TYPE -h $HOST:$PORT/sdk -u $AUTHUSER -p $AUTHPWD $1 \"$2\""
  $VMRUN -T $TYPE -h $HOST:$PORT/sdk -u $AUTHUSER -p $AUTHPWD $1 "$2"
}

function VMGUESTACTION()
{
  ## Execute the specified command in the guest OS using vmrun
  ## Requires input variables: 1-$VM_USR, 2-$VM_PWD, 3-command, 4-$VM_VMX, 5-$VM_CMD
###Debug###
#  echo "$VMRUN -T $TYPE -h $HOST:$PORT/sdk -u $AUTHUSER -p $AUTHPWD -gu $1 -gp $2 $3 \"$4\" \"$5\""
  $VMRUN -T $TYPE -h $HOST:$PORT/sdk -u $AUTHUSER -p $AUTHPWD -gu $1 -gp $2 $3 "$4" "$5"
}

#----------------------------------------------------------------------------#

## Validate the action parameter, perform "list" or "status" actions
case $ACTION in
  list 	)	# List all available VMs configured in the config file
			echo "Listing available VMs from $CONFFILE ..."
			echo "$ALLVMNAMES"
			exit 0								;;
  status 	)	# List the status of running VMs using vmrun utility
			echo "Listing VMs that are currently running ..."
			CHECKAUTH Host AUTHUSER AUTHPWD
			VMLISTSTATUS
			exit 0								;;
  start	)	ACTDESC="Starting"						;;
  down 	)	ACTDESC="Downing"						;;
  stop 	)	ACTDESC="Stopping"						;;
  reset	)	ACTDESC="Resetting"						;;
    *		)	## Echo error message for all invalid actions
			ERRMSG1="$ACTION: Invalid action specified"
			ERROROUT "$ERRMSG1" "$USAGE0" "$USAGE1"			;;
esac

## Validate the specified VM name parameter
case $VMLIST in
  ""		)	ERRMSG1="Error: a valid VM name or VM group must be specified"
			ERROROUT "$ERRMSG1" "$USAGE0"				;;
  *		)	VALIDATEVMNAME $VMLIST
			if [ "$?" != "1" ]; then
			  ERRMSG1="Error: $VMLIST is not a valid virtual machine or group"
			  ERRMSG2="Valid VM names (in $CONFFILE): $ALLVMNAMES"
			  ERROROUT "$ERRMSG1" "$USAGE0" "$ERRMSG2"
			fi								;;
esac

#----------------------------------------------------------------------------#

## Determine what Virtual Machines are currently running using vmrun
CHECKAUTH Host AUTHUSER AUTHPWD
ACTIVEVMS=`VMLISTSTATUS | grep ".vmx" | cut -d" " -f2`

## Start, down or stop the specified VMs using vmrun utility
echo "Executing vmrun to $ACTION VMs ... $VMLIST ($TARGETVMS)"
# Set the values of the required variables
for VM in $TARGETVMS; do
  VM_NAM=`eval echo '${'$VM"_NAM"'}'`
  VM_VMX=`eval echo '${'$VM"_VMX"'}'`
  VM_USR=`eval echo '${'$VM"_USR"'}'`
  VM_PWD=`eval echo '${'$VM"_PWD"'}'`
  VM_CMD=`eval echo '${'$VM"_CMD"'}'`
  echo " * $ACTION $VM_NAM ..."
  # Perform the action on the specified VMs
  case $ACTION in
    start	)	## Start the specified VMs using vmrun utility
			CHECKIFRUNNING "$VM_VMX"
			if [ $? = 1 ]; then
			  echo "  - $VM_NAM is already running"
			  DELAY=0
			else
			  VMRUNACTION $ACTION "$VM_VMX"
			  DELAY=$STARTDELAY
			fi								;;
    down	)	## Run a script in the guest VM to down the VM
			CHECKIFRUNNING "$VM_VMX"
			if [ $? = 1 ]; then
			  CHECKAUTH Guest VM_USR VM_PWD
			  VMGUESTACTION $VM_USR $VM_PWD runProgramInGuest "$VM_VMX" $VM_CMD
			  DELAY=$DOWNDELAY
			else
			  echo "  - $VM_NAM is not currently running"
			  DELAY=0
			fi								;;
    stop	)	## Stop the specified VMs using vmrun utility
			CHECKIFRUNNING "$VM_VMX"
			if [ $? = 1 ]; then
			  VMRUNACTION $ACTION "$VM_VMX"
			  DELAY=$STOPDELAY
			else
			  echo "  - $VM_NAM is not currently running"
			  DELAY=0
			fi								;;
    reset	)	## Stop the specified VMs using vmrun utility
			CHECKIFRUNNING "$VM_VMX"
			if [ $? = 1 ]; then
			  VMRUNACTION $ACTION "$VM_VMX"
			  DELAY=$RESETDELAY
			else
			  echo "  - $VM_NAM is not currently running"
			  DELAY=0
			fi								;;
  esac
  sleep $DELAY
done

exit 0

##END##
