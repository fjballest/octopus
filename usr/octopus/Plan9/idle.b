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
	run: import Os;
Idle: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;

idle(): int
{
	(o, e) := os->run("cat '#m/mousectl'", nil);
	if (o == nil || o == "")
		error("idle: can't get Plan 9 idle");
	if (e != nil && e != "")
		error("idle: " + e);
	return int o;
}

sysname: string;
last: string;

here()
{
	if (sysname == nil){
		sysname = getenv("sysname");
		if(sysname == "pc")
			sysname = getenv("PC");
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
	i := 0;
	for(;;){
		sleep(5000);
		if ((++i % 6) == 0)	# Once in a while pretend we came
			sts = Away;	# to udate /mnt/who/$user/last
		t := idle();
		nsts := Away;
		if (t < 15)
			nsts = Here;
		if (nsts == Here && sts == Away)
			here();
		sts = nsts;
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
	idle();			# to detect errors
	spawn updater();
}
