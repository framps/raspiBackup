#!/bin/bash
#
:<<SKIP

bzip2 	.tar.bz2
gzip 	.tar.gz
lzip 	.tar.lz
lzma 	.tar.lzma
lzop	.tar.lzo
xz	.tar.xz
compress .tar.Z
zstd	.tar.zst
SKIP

DIR="./tarTest"
SOURCE="./tarData.img"
EXTENSIONS=(".bz2"  ".gz"  ".lz"  ".lzma" ".lzo" ".xz" ".zst")
TOOLS=(     "bzip2" "gzip" "lzip" "lzma"  "lzop" "xz"  "zstd")
OPTS=(      ""      ""     ""     ""      "-3"   ""    "-T0" )

rm -rf $DIR
mkdir $DIR

echo "Creating data ..."
rm $SOURCE
dd if=/dev/random of=$SOURCE bs=10MiB count=1

check_magic_number () {
  # Read the first 12 bytes of the file in hexadecimal format
  magic_number=$(head -c 12 "$1" | xxd -p)
  # Compare the magic number with the known values and print the tool name
  case $magic_number in
    1f8b*|1f9e*) echo "data compressed with: gzip";;
    425a68*|425a30*) echo "data compressed with: bzip2";;
    1f9d*|1fa0*) echo "data compressed with: compress";;
    4c525a49*) echo "data compressed with: lrzip";;
    4c5a4950*) echo "data compressed with: lzip";;
    5d0000*) echo "data compressed with: lzma";;
    894c5a4f000d0a1a0a*) echo "data compressed with: lzop";;
    52457e5e*|526172211a0700*|526172211a070100*) echo "data compressed with: rar";;
    377abcaf271c*) echo "data compressed with: 7z";;
    504b0304*) echo "data compressed with: zip";;
    fd377a585a*) echo "data compressed with: xz";;
    28b52ffd*|25b52ffd*) echo "data compressed with: zstd";;
    *) echo "Unknown magic number";;
  esac
}

function save() { # file tool opts
	echo -n "Compressing $1 wth $2($3)-> "
	#time tar -caf $1 $SOURCE
	time tar -c -I"$2 $opts" -f $1 $SOURCE
	#echo "Contents of $1"
	#tar --list -f $1
	check_magic_number $1
}

for (( i=0; i<${#EXTENSIONS[@]}; i++ )) ; do
	ext="${EXTENSIONS[$i]}"
	tool="${TOOLS[$i]}"
	opts="${OPTS[$i]}"
	save "$DIR/data.tar$ext" "$tool" "$opts"
	if ! which $tool &>/dev/null; then
		echo "??? $tool for $ext not found"
	fi
done

