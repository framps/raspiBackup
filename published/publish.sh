#!/bin/bash

cd ..
make buildFiles BRANCH=$1
cp ~/depl/* published
git -c filter.dater.clean= add published/*

