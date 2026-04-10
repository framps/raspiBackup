#!/bin/bash
sed -E 's/\x1b\[(K|.+(;|m))//g' $1
