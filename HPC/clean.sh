#!/bin/bash

##############################################################
# Author: Josh R
# Script: clean.sh
# CAUTION:
#   Due to a quote on the number of inodes, removing extraneous
#   files helps us hold more compiled versions of NWChem for more
#   comprehensive comparison testing.
# Purpose: 
#   Removing unecessary files from the NWCHEM_TOP directory to
#   reduce the number inodes used per NWChem install
# Usage:
#  `./clean.sh nwchem/`
# Notes:
#  nwchem/ here is the path to the git repository used to build
#  NWChem. It is the same as NWCHEM_TOP set by the install script.
#  This script is probably not necessary to use unless gadi
#  starts giving inode quota violation warnings. 
# Last Updated: 8 September 2025
##############################################################

set -e

echo "================== Beginning clean up process =================="
if [ -v $1 ]; then
	echo "Pass NWCHEM_TOP into this script please "
	exit
fi 

initial_dir=$(pwd)

echo "===================== moving into nwchem ====================="

cd $1

echo "===================== Deleting in nwchem ====================="


for FILE in * ; do
	case $FILE in
		"bin" | "src" | "lib" )
			echo not deleting $FILE
			;;
		*)
			echo deleting $FILE
			rm -rf $FILE
			;;
	esac
done

echo "======================= Moving into src ======================="

cd src/

echo "======================= Deleting in src ======================="

for FILE in * ; do
	case $FILE in
		"basis" ) 
			echo not deleting $FILE
			;;
		*)
			echo deleting $FILE
			rm -rf $FILE
			;;
	esac
done

cd initial_dir