#
# Execution helpers for os commands
#

implement Os;
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
include "string.m";
	str: String;
	splitl, splitstrr : import str;
include "names.m";
	names: Names;
	cleanname, rooted: import names;
include "workdir.m";
	wdir: Workdir;
include "io.m";
	io: Io;
	readfile: import io;
include "os.m";


init()
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	str = checkload(load String String->PATH, String->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	names = checkload(load Names Names->PATH, Names->PATH);
	wdir = checkload(load Workdir Workdir->PATH, Workdir->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	emuhost = getenv("emuhost");
	emuroot = getenv("emuroot");
	if(emuroot == nil)
		emuroot = "/usr/inferno";
}

filename(name: string): string
{
	name = cleanname(name);
	name = rooted(wdir->init(), name);
	return emuroot + name;
}

reader(fd: ref Sys->FD, c: chan of string)
{
	out := string readfile(fd);
	fd = nil;
	c <-= out;
}

reader1(fd: ref Sys->FD, c: chan of string)
{
	buf := array[128] of byte;
	nr := read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0)
		c <-= "errors";
	else
		c <-= string buf[0:nr];
}

writer(fd: ref Sys->FD)
{
	fprint(fd, "");
	fd = nil;
}

# cmd(3) seems a little bit buggy
# Either you open wait, then exec, then open stdout/stderr
# or you'd get leaked (pipe) file descriptors in emu.

frun(cmd: string, udir: string): (ref Cmdio, string)
{
	cfd := open("/cmd/clone", ORDWR);
	if(cfd == nil) 
		return (nil, sprint("cmd: clone: %r"));
	nam := array[40] of byte;
	nr := read(cfd, nam, len nam);
	if(nr == 0)
		return(nil, "cmd: ctl eof");
	if(nr < 0)
		return (nil, sprint("cmd: ctl: %r"));
	dir := "/cmd/" + string nam[0:nr];
	wfd := open(dir + "/wait", OREAD);
	if(wfd == nil)
		return(nil, sprint("os wait: %r"));
	fprint(cfd, "killonclose");

#	this hangs if the dir does not exist.
#	if(udir != nil)
#		if(fprint(cfd, "dir %s", udir) < 0)
#			return (nil, sprint("chdir: %r"));
	if(fprint(cfd, "exec %s", cmd) < 0)
		return(nil, sprint("os run: %r"));
	ifd := open(dir + "/data", OWRITE);
	if(ifd == nil)
		return(nil, sprint("os stdin: %r"));
	ofd := open(dir + "/data", OREAD);
	if(ofd == nil)
		return(nil, sprint("os stdout: %r"));
	efd := open(dir + "/stderr", OREAD);
	# Some /cmd do not have stderr (use stdout instead).
	if(efd == nil)
		efd = open("/dev/null", OREAD);
	return (ref Cmdio(ifd, ofd, efd, wfd, cfd), nil);
}

run(cmd: string, dir: string): (string, string)
{
	(cio, e) := frun(cmd, dir);
	if(e != nil)
		return (nil, e);
	oc := chan[1] of string;
	ec := chan[1] of string;
	wc := chan[1] of string;
	spawn writer(cio.ifd);
	spawn reader(cio.ofd, oc);
	spawn reader(cio.efd, ec);
	spawn reader1(cio.wfd, wc);
	out := <-oc;
	errors := <-ec;
	sts := <-wc;
	l := str->unquoted(sts);
	if(len l < 5)
		sts = "bad status";
	else
		sts = hd tl tl tl tl l;
	fprint(cio.cfd, "kill");
	cio = nil;
	if(0)fprint(stderr, "cmd: out [%s] err [%s] sts [%s]\n", out, errors, sts);
	return (out, errors);
}
