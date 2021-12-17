#/bin/bash

# Just some code to get familiar with STDIO and STDERR grabbing into variables

# Code grabbed and modified from https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables

function executeCommand() { # stoutVarName stdErrVarName command
	{
        IFS=$'\n' read -r -d '' "${1}";
        IFS=$'\n' read -r -d '' "${2}";
        (IFS=$'\n' read -r -d '' _ERRNO_; return ${_ERRNO_});
    } < <((printf '\0%s\0%d\0' "$(((({ ${3}; echo "${?}" 1>&3-; } | tr -d '\0' 1>&4-) 4>&2- 2>&1- | tr -d '\0' 1>&4-) 3>&1- | exit "$(cat)") 4>&1-)" "${?}" 1>&2) 2>&1)
}


cmds=("ssh pi@192.168.0.152 ls -b /" \
	  "ssh pi@192.168.0.152 ls -b /m" \
	  "ssh pi@192.168.0.152 ls -b /root/.ssh" \
	  "ssh pi@192.168.0.152 sudo ls -b /root/.ssh" \
	  "ssh pi@192.168.0.152 mkdir /dummy" \
	  "ssh pi@192.168.0.152 sudo mkdir /dummy" \
	  "ssh pi@192.168.0.152 ls -b /" \
	  "ssh pi@192.168.0.152 sudo rmdir /dummy")

for cmd in "${cmds[@]}"; do
	echo "CMD: $cmd"
	executeCommand std err "$cmd"
	echo "--- RC: $?"
	echo "--- STDOUT"
	echo "${std[@]}"
	echo "--- STDERR"
	echo "$err"
done

# issue ls -b is not returned as one line but n lines :-((
