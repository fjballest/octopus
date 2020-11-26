#!/bin/sh
#
# example start script for octopus on Linux or MacOS

DIR=/Users/inferno-os
RES=800x600

export PATH=$DIR/MacOSX/386/bin:$PATH
emu -r $DIR -g $RES -pheap=100M -pmain=100M -pimage=64M /dis/wm/wm.dis wm/logon -u `whoami`

