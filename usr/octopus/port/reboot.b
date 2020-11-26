#
# Watchs out the registry for the octopus.
# 1. Old, and not refreshed entries are removed, and their Ofs processes killed.
# 2. New ofs entries are announced via plumb messages
# 3. Gone ofs entries are announced as gone via plumb messages

implement Reboot;

include "sys.m";
	sys: Sys;
	FD, fprint, sprint, remove, read, sleep, unmount,
	pctl, NEWPGRP, write, OWRITE, OREAD, dirread, open: import sys;
include "error.m";
	err: Error;
	stderr, checkload, panic, error, kill: import err;
include "env.m";
	env: Env;
include "draw.m";

Reboot: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;
regok := 1;

watcher()
{
	for(;;){
		fd := open("/pc/lib/ndb", OREAD);
		if(fd == nil){
			fprint(stderr, "o/reboot: connection to PC lost: %r");
			break;
		} else
			fd = nil;
		regok = 1;
		sleep(5000);
	}
}

trigger()
{
	do{
		regok = 0;
		sleep(10000);
	} while(regok);
	fd := open("#c/sysctl", OWRITE);
	fprint(fd, "reboot");
}


init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	env = checkload(load Env Env->PATH, Env->PATH);
	spawn watcher();
	spawn trigger();
}
