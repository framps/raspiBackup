#!/bin/bash
TYPES_TO_TEST1=( "dd" "tar" "rsync" )
TYPES_TO_TEST2=( "tar --tarCompressionTool lz4" "tar --tarCompressionTool zstd")
TYPES_TO_TEST=( "${TYPES_TO_TEST1[@]}" "${TYPES_TO_TEST2[@]}" )
for i in "${TYPES_TO_TEST[@]}"; do
	echo "$i"
done

