#/bin/bash

# Just some code to get familiar with STDIO and STDERR grabbing into variables

# Code grabbed and modified from https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables

# issue ls -b is not returned as one line but n lines
# but cat /etc/fstab returns n lines of file
function executeRemoteCommand() { # stoutVarName stdErrVarName command
	{
        IFS=$'\n' read -r -d '' "${1}";
        IFS=$'\n' read -r -d '' "${2}";
        (IFS=$'\n' read -r -d '' _ERRNO_; return ${_ERRNO_});
    } < <(
				(
					printf '\0%s\0%d\0' \
						"$(
							(
								(
									(
										{
											${3}; echo "${?}" 1>&3-;
										} | tr -d '\0' 1>&4-
									) 4>&2- 2>&1- | tr -d '\0' 1>&4-
								) 3>&1- | exit "$(cat)"
							) 4>&1-
						)" "${?}" 1>&2
				) 2>&1
			)
}
