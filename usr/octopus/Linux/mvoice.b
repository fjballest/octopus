# machine dependent voice support
#
implement Mvoice;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	fprint, sprint, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "env.m";
	env: Env;
	getenv: import env;
include "mvoice.m";

include "os.m";
	os: Os;

init() : string
{
	if (sys == nil){
		sys = load Sys Sys->PATH;
		err = load Error Error->PATH;
		err->init(sys);
		env = checkload(load Env Env->PATH, Env->PATH);
	}
	os = checkload(load Os Os->PATH, Os->PATH);
	os->init();
	return nil;
}

speakfile(text: string): (ref FD, string)
{
	r := getenv("emuroot");
	if (r == nil)
		r = "/Users/inferno";
	r +=  "/tmp/tmp.voice";
	fd := create("/tmp/tmp.voice", OWRITE, 8r664);
	fprint(fd, "%s\n", text);
	return (fd, r);
}

speak(text: string): string
{
	(nil, fname) := speakfile(text);
	cmds:=sprint("espeak -f %s", fname);
	(nil, e) := os->run(cmds, nil);
	if( e != nil )
		return e;
	return nil;
}
