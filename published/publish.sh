#!/bin/bash

cd ..
make buildFiles BRANCH=m_published
cp ~/depl/* published
git -c filter.dater.clean= add published/*

