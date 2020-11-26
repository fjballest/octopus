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

init() : string
{
	return nil;
}

speakcmd(text: string): (ref FD, string)
{
	cmd : string;
	r := getenv("emuroot");
	if (r == nil)
		r = "/Users/inferno";
	r +=  "/tmp/tmp.voice";
	fd := create("/tmp/tmp.voice", OWRITE, 8r664);
	fprint(fd, "Say \"%s\"\n", text);
	cmd = sprint("osascript %s", r);
	return (fd, cmd);
}

speak(text: string): string
{
	if (sys == nil){
		sys = load Sys Sys->PATH;
		err = load Error Error->PATH;
		err->init(sys);
		env = checkload(load Env Env->PATH, Env->PATH);
	}
	(fd, cmd) := speakcmd(text);
	cfd := open("/cmd/clone", ORDWR);
	if (cfd == nil)
		return sprint("voice: cmd: %r");
	nam := array[30] of byte;
	nr := read(cfd, nam, len nam);
	if (nr <= 0)
		return sprint("voice: cmd: %r");
	dir := "/cmd/" + string nam[0:nr];
	wfd := open(dir + "/wait", OREAD);
	if (wfd == nil)
		return sprint("voice: wait: %r");
	fprint(cfd, "exec %s", cmd);
	sts := array[1024] of byte;
	nr = read(wfd, sts, len sts);
	fd = nil;
	return nil;
}
