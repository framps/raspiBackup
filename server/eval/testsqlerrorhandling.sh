#!/bin/bash

# Code origin: https://www.howtoforge.com/detailed-error-handling-in-bash

# Find out where I am to load the library from the same directory:
HERE=`dirname $0`

# Error handling settings:
ERRORDB=~/test.sqlite
ERROR_ENVIRONMENT_VARIABLES='USER TERM PATH HOSTNAME LANG DISPLAY NOTEXIST'
ERROR_CLEANUP_ACTION="echo I'm cleaning up!"

source $HERE/liberrorhandler.bash
trap Error_Handler ERR
# The above trap statement will do nothing in this example,
# unless you comment out the other trap statement.

function InnerFunction
        {
         trap Error_Handler ERR
         # The above trap statement will cause the error handler to be called.
         cat $1 2> $ERROROUTPUT
         # This will fail, because the file passed in $1 does not exist.
        }

function OuterFunction
        {
         InnerFunction /doesnot.exist
        }

OuterFunction 2>$ERROROUTPUT


