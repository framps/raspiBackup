#!/bin/bash

# Code origin: https://www.howtoforge.com/detailed-error-handling-in-bash

# Needed variable: ERRORDB
# Optional variables: ERROROUTPUT, SQLITE3_EXECUTABLE, ERROR_CLEANUP_ACTION, ERROR_ENVIRONMENT_VARIABLES

if [ -z $ERROROUTPUT ];then
   ERROROUTPUT=/var/tmp/$$.err
fi
if [ -e $SQLITE3_EXECUTABLE ] ;then
   SQLITE3_EXECUTABLE=`which sqlite3`
fi
# The settings file for SQLite3:
ERROR_INIT_SQLITE=/var/tmp/$$_init.sql
# For convenience, a function to create the settings for SQLite3:
function Error_Create_Init_File
        {
         cat > $ERROR_INIT_SQLITE <<'ERROR_SQLITE_SETTINGS'
.bail ON
.echo OFF
PRAGMA foreign_keys = TRUE;
ERROR_SQLITE_SETTINGS
        }
# Create the database:
if [ -z $ERRORDB ] ;then
   echo "Error database is not defined."
   exit 1
else
   Error_Create_Init_File
   $SQLITE3_EXECUTABLE -batch -init $ERROR_INIT_SQLITE $ERRORDB <<'ERROR_TABLE_DEFINITION'
CREATE TABLE IF NOT EXISTS ErrorLog
      (intErrorLogId INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
       strMessage TEXT NOT NULL,
       tstOccurredAt DATE NOT NULL DEFAULT(CURRENT_TIMESTAMP) );
CREATE INDEX IF NOT EXISTS idxELOccurredAt ON ErrorLog(tstOccurredAt);

CREATE TABLE IF NOT EXISTS ErrorStackTrace
      (intErrorStackTraceId INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
       intErrorLogId INTEGER NOT NULL,
       strSourceFile TEXT NOT NULL,
       strFunction TEXT NOT NULL,
       intLine INTEGER NOT NULL,
       FOREIGN KEY(intErrorLogId) REFERENCES ErrorLog(intErrorLogId)
               ON DELETE CASCADE
               ON UPDATE CASCADE );
CREATE INDEX IF NOT EXISTS idxESTTraceErrorLogId ON ErrorStackTrace(intErrorLogId);

CREATE TABLE IF NOT EXISTS ErrorEnvironment
      (intErrorEnvironmentId INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
       intErrorLogId INTEGER NOT NULL,
       strVariable TEXT NOT NULL,
       strValue TEXT NULL,
       FOREIGN KEY(intErrorLogId) REFERENCES ErrorLog(intErrorLogId)
               ON DELETE CASCADE
               ON UPDATE CASCADE );
CREATE INDEX IF NOT EXISTS idxEEErrorLogId ON ErrorEnvironment(intErrorLogId);
ERROR_TABLE_DEFINITION
   rm -f $ERROR_INIT_SQLITE
fi
# Helper functions to "escape" strings tohexadecimal strings
function Error_Hexit # StringToHex
        {
         echo -n "$1" | hexdump -v -e '1 1 "%02X"'
        }

function Error_Hexit_File # FileToHex
        {
         if [ -e $1 -a -s $1 ] ;then
            hexdump -v -e '1 1 "%02X"' < $1
         else
            Error_Hexit '(No message)'
         fi
        }
# The error handling function:
# Enable with: trap Error_Handler ERR
# Disable with: trap '' ERR
function Error_Handler
        {
         local EXITCODE=$?
         trap '' ERR # switch off error handling to prevent wild recursion.
         local ARRAY=( `caller 0` )
         Error_Create_Init_File
         # Write the error message (from STDERR) and read the generated autonumber:
         local INSERT_ID=`$SQLITE3_EXECUTABLE -batch -init $ERROR_INIT_SQLITE $ERRORDB "INSERT INTO ErrorLog(strMessage) VALUES(CAST(x'$(Error_Hexit_File $ERROROUTPUT)' AS TEXT));SELECT last_insert_rowid();"`
         # Write the stack trace:
         local STACKLEVEL=0
         local STACK_ENTRY=`caller $STACKLEVEL`
         until [ -z "$STACK_ENTRY" ];do
               local STACK_ARRAY=( $STACK_ENTRY )
               $SQLITE3_EXECUTABLE -batch -init $ERROR_INIT_SQLITE $ERRORDB "INSERT INTO ErrorStackTrace(intErrorLogId,strSourceFile,strFunction,intLine) VALUES($INSERT_ID, CAST(x'$(Error_Hexit ${STACK_ARRAY[2]})' AS TEXT), '${STACK_ARRAY[1]}', ${STACK_ARRAY[0]})"
               let STACKLEVEL+=1
               STACK_ENTRY=`caller $STACKLEVEL`
         done
         # Write the error environment:
         for VAR in EXITCODE BASH_COMMAND BASH_LINENO BASH_ARGV $ERROR_ENVIRONMENT_VARIABLES ;do
             local CONTENT=$(Error_Hexit "${!VAR}")
             $SQLITE3_EXECUTABLE -batch -init $ERROR_INIT_SQLITE $ERRORDB "INSERT INTO ErrorEnvironment(intErrorLogId,strVariable,strValue) VALUES($INSERT_ID, '$VAR', CAST(x'$CONTENT' AS TEXT));"
         done
         # Clean up and provide feedback:
         if [ -e $ERROROUTPUT ] ;then
            cat $ERROROUTPUT 1>&2
         fi
         rm -f $ERROR_INIT_SQLITE
         rm -f $ERROROUTPUT
         if [ -n "$ERROR_CLEANUP_ACTION" ] ;then
            $ERROR_CLEANUP_ACTION
         fi
         exit $EXITCODE
        }


