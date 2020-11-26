implement Idle;

include "sys.m";
	sys: Sys;
	open, sprint, fprint, create, remove,
	sleep, read, ORDWR, OWRITE, OTRUNC, OREAD, print: import sys;
include "draw.m";
include "env.m";
	env: Env;
	getenv: import env;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "os.m";
	os: Os;

Idle: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;

Cmd := array [2] of    {
	"xscreensaver-command -time |grep ' blanked'",
	"gnome-screensaver-command -q |grep inactive"
};

isidle(cmd: string): int
{
	i: int;

	i = 1;
	fd := create("/tmp/tmp.idle", OWRITE, 8r775);
	fprint(fd, "#!/bin/sh\n%s\n", cmd);
	fd = nil;

	(o, e) := os->run(os->filename("/tmp/tmp.idle"), nil);
	if (o  != nil)
		i = 0;
	else if (e != nil)
		i = -1;
	if (debug)
		fprint(stderr, "isidle: %d %s -> [%s, %s]\n", i, cmd, e, o);
	return i;
}

sysname: string;
last: string;

here()
{
	if (sysname == nil){
		sysname = getenv("sysname");
		last = sprint("/mnt/who/%s/last", getenv("user"));
	}
	fd := open(last, OWRITE|OTRUNC);
	if (fd == nil){
		fprint(stderr, "idle: %s: %r\n", last);
		return;
	}
	fprint(fd, "%s\n", sysname);
	if (debug)
		print("here\n");
}

updater()
{
	Here, Away: con iota;

	sts := Away;
	nsts := Away;
	i := 0;
	for(;;){
		if ((++i % 6) == 0)	# Once in a while pretend we came
			sts = Away;	# to update /mnt/who/$user/last

		for(j := 0; j < len Cmd; j++){
			idl := isidle(Cmd[j]);
			if(idl < 0)
				continue;
			nsts = Away;
			if(!idl)	
				nsts = Here;
		}
		if (nsts == Here && sts == Away)
			here();
		sts = nsts;
		sleep(15000);
	}
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	env = checkload(load Env Env->PATH, Env->PATH);
	os = checkload(load Os Os->PATH, Os->PATH);
	os->init();

	sys->print("hello");
	spawn updater();
}
