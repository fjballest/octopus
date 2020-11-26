# machine dependent voice support
#
implement Mvoice;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	fprint, sprint, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "mvoice.m";

Dev : con "/mnt/fs/devs/voice/output";

init() : string
{
	sys = load Sys Sys->PATH;
	fd := open(Dev, OWRITE);
	if (fd == nil)
		return sprint("%s: %r", Dev);
	return nil;
}

speak(text: string): string
{
	fd := open(Dev, OWRITE);
	if (fd == nil)
		return sprint("voice: %r");
	if (fprint(fd, "%s\n", text)  < 0)
		return sprint("voice: %r");
	return nil;
}
