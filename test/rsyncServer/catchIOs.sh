#/bin/bash

# Just some code to get familiar with STDIO and STDERR grabbing into variables

# Code grabbed from https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables

# SYNTAX:
#   catch STDOUT_VARIABLE STDERR_VARIABLE COMMAND
catch() {
    {
        IFS=$'\n' read -r -d '' "${1}";
        IFS=$'\n' read -r -d '' "${2}";
        (IFS=$'\n' read -r -d '' _ERRNO_; return ${_ERRNO_});
    } < <((printf '\0%s\0%d\0' "$(((({ ${3}; echo "${?}" 1>&3-; } | tr -d '\0' 1>&4-) 4>&2- 2>&1- | tr -d '\0' 1>&4-) 3>&1- | exit "$(cat)") 4>&1-)" "${?}" 1>&2) 2>&1)
}

c="ssh pi@192.168.0.152 ls /"
#catch STDOUT STDERR "ssh pi@192.168.0.152 ls /" "$c"
catch STDOUT STDERR "echo "eins$'\n'zwei""
echo "$c"
echo "STDOUT"
echo "$STDOUT"
echo "STDERR"
echo "$STDERR"
exit
c="ssh pi@192.168.0.152 ls /hugo"
catch STDOUT STDERR "$c"
echo "$c"
echo "STDOUT"
echo "$STDOUT"
echo "STDERR"
echo "$STDERR"
