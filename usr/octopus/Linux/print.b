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

printer := "default";

init(args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	os = checkload(load Os Os->PATH, Os->PATH);
	str = checkload(load String String->PATH, String->PATH);
	os->init();
	if (len args == 1)
		printer = hd args;
}

status(): string
{
	(out, e) := os->run("lpq", nil);
	if (e != nil)
		return e;
	(nlines, lines) := tokenize(out, "\n");
	if (nlines < 1)
		return "eof";
	sts := hd lines; lines = tl lines;
	(nil, sts) = splitstrr(sts, " is ");
	if (lines == nil || hd lines == "no entries")
		return sts + "\n" + "0 jobs\n";
	else
		return sts + "\n" + string (len lines -1) + " jobs\n";
}

Sfile.start(path: string, endc: chan of string): (ref Sfile, string)
{
	#run "lp" get job id and store in sfile.
	cmd := "lp " + os->filename(path);
	(out, e) := os->run(cmd, nil);
	sval: string;
	if (out != nil){
		# "request id is xxxxx-nb "
		(nwords, words) := tokenize(out, " ");
		if (nwords >=4)
			sval = hd tl tl tl words;
	}
	# BUG: must watch that the job did finish, and send
	# any diagnostic and termination through endc.
	# This requires fixing a BUG in spool.b
	if (endc != nil)
		endc <-= nil;
	return (ref Sfile(nil, nil, sval), e);
}

Sfile.stop(f: self ref Sfile)
{
	if (f.sval != nil){
		cmd := "lprm " + f.sval;
		os->run(cmd, nil);
	}
}

Sfile.status(nil: self ref Sfile): string
{
	# BUG request job status
	return "started";
}
