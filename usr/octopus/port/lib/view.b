# File view spooler, for use with spool

implement Spooler;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	fprint, sprint, create, pwrite, read, remove, QTDIR, QTFILE, fildes, Qid: import sys;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "string.m";
	str: String;
	splitl, splitstrr : import str;
include "os.m";
	os: Os;
include "io.m";
	io: Io;
	readdev, readfile: import io;
include "spooler.m";

viewurlcmd(url: string): string
{
	cmd: string;
	host := os->emuhost;
	case host {
	"Plan9" or "PlanB" =>
		cmd = sprint("plumb '%s'", url);
	"MacOSX" =>
		cmd = sprint("open %s", url);
	"Linux" =>
		cmd = sprint("gnome-open %s", url);
	"Nt" =>
		cmd = sprint("cmd /c START %s", url);
	* =>
		cmd = sprint("open %s", url);
	}
	return cmd;
}

viewcmd(file: string): string
{
	cmd : string;
	(pref, suf) := splitstrr(file, ".url");
	if(suf == nil || suf == "")
	if(pref != nil && pref != ""){
		url := readdev(file, "none");
		if(url != nil)
			(url, suf) = splitl(url, "\n");
		return viewurlcmd(url);
	}
	r := os->filename(file);
	host := os->emuhost;
	case host {
	"Plan9" or "PlanB" =>
		cmd = sprint("plumb %s", r);
	"MacOSX" =>
		# lsof may report when we're done viewing the file
		cmd = sprint("open %s", r);
	"Linux" =>
		cmd = sprint("gnome-open %s", r);
	"Nt" =>
		cmd = sprint("cmd /c START %s", r);
	* =>
		cmd = sprint("open %s", r);
	}
	return cmd;
}

Sfile.start(path: string, endc: chan of string): (ref Sfile, string)
{
	debug = 1;
	cmd := viewcmd(path);

	if(debug)
		fprint(stderr, "view: cmd %s\n", cmd);

	cfd := open("/cmd/clone", ORDWR);
	if(cfd == nil) {
		if(endc != nil)
			endc <-= sprint("viewer: cmd: %r\n");
		return (nil, sprint("viewer: cmd: %r\n"));
	}
	fprint(cfd, "killonclose");
	fprint(cfd, "exec %s", cmd);
	if(endc != nil)
		endc <-= nil;

	return (ref Sfile(cfd, path, nil), nil);
}

Sfile.stop(f: self ref Sfile)
{
	f.fd = nil;
	remove(f.path); #no ORCLOSE because of windows
}

Sfile.status(nil: self ref Sfile): string
{
	return "started";
}

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	str = checkload(load String String->PATH, String->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	os = checkload(load Os Os->PATH, Os->PATH);
	os->init();
}

status(): string
{
	return "ok";
}
