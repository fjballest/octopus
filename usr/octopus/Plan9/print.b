# File printer spooler, for use with spool

implement Spooler;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	tokenize,
	fprint, sprint, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "string.m";
	str: String;
	splitstrr: import str;
include "os.m";
	os: Os;
include "spooler.m";

dflag := "";

init(args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	os = checkload(load Os Os->PATH, Os->PATH);
	str = checkload(load String String->PATH, String->PATH);
	os->init();
	if (len args == 1)
		dflag = "-d" + hd args;
}

status(): string
{
	# BUG: we could use lp -q, but that might block while the
	# printer is busy with the current job. Let's sacrifice this.
	return "ready\n";
}

print(cmd: string, endc: chan of string)
{
	e: string;
	(nil, e) = os->run(cmd, nil);
	if (endc != nil)
		endc <-= e;
}

Sfile.start(path: string, endc: chan of string): (ref Sfile, string)
{
	cmd := "lp " + os->filename(path);
	spawn print(cmd, endc);
	return (ref Sfile(nil, nil, nil), nil);
}

Sfile.stop(nil: self ref Sfile)
{
}

Sfile.status(nil: self ref Sfile): string
{
	# BUG request job status
	return "started";
}
