implement Mcamera;
include "mcamera.m";
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	fprint, sprint, create, print, pwrite, read, remove, QTDIR, QTFILE, fildes, Qid: import sys;
include "draw.m";
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "string.m";
	str: String;
	splitr: import str;
include "env.m";
	env: Env;
	getenv: import env;

# must be in $PATH in the host.
CFSMACOSX: con "isightcapture" ;
CFSMACOSXMODS: con "-t jpg -w 640 -h 480";
ERRORNOCMD: con  "isightcapture not found, read the manual please";
FILENAME: con "/tmp/cfs.pic0000";

takejpg() : (array of byte, int)
{	
	u := getenv("user"); 
	r := getenv("emuroot");
	if (r == nil)
		r = "/Users/" + u + "/Library/Octopus/";
	cmd := CFSMACOSX + "  " +  CFSMACOSXMODS+  "  " +  r + FILENAME ;

	if (sys == nil){
		sys = load Sys Sys->PATH;
		err = load Error Error->PATH;
		err->init(sys);
		env = checkload(load Env Env->PATH, Env->PATH);
	}
	cfd := open("/cmd/clone", ORDWR);
	if (cfd == nil)
		return (nil, 0);

	nam := array[30] of byte;
	nr := read(cfd, nam, len nam);
	if (nr <= 0)
		return (nil, 0);
	dir := "/cmd/" + string nam[0:nr];
	wfd := open(dir + "/wait", OREAD);
	if (wfd == nil)
		return (nil, 0);
	efd := open(dir + "/ctl", OWRITE);
	if (efd == nil)
		return (nil, 0);

	nr = fprint(efd, "exec %s", cmd);
	if(nr < 0)
		return (nil, 0);

	sts := array[1024] of byte;
	nr = read(wfd, sts, len sts);
	if(nr <= 0)
		return (nil, 0);

	dfd :=  open(dir + "/data", OREAD);
	if(dfd == nil)
		return (nil, 0);
	while(read(dfd, sts, len sts) > 0)  ;

	picfd := open(FILENAME, OREAD);
	if(picfd == nil)
		return (nil, 0);
	image := array[1024*1024] of byte; 
	done := 0;
	while((nr = read(picfd, image[done:len image], (len image) - done)) > 0){
		done += nr;
		if(done == 1024*1024)  # too long!!
			return (nil, 0);
	}
	if(nr < 0)
		return (nil, 0);
	
	remove(FILENAME);
	efd = nil;
	dfd = nil;
	wfd = nil;
	cfd = nil;
	picfd = nil;
	return (image, done);
}


# checks if there is the command in the host and it's executable
# just tries to execute it 
commandexists()
{	
	if (sys == nil){
		sys = load Sys Sys->PATH;
		err = load Error Error->PATH;
		err->init(sys);
		env = checkload(load Env Env->PATH, Env->PATH);
	}

	cmd := CFSMACOSX;
	cfd := open("/cmd/clone", ORDWR);
	if (cfd == nil)
		error("cannot open /cmd/clone");
	nam := array[30] of byte;
	nr := read(cfd, nam, len nam);
	if (nr <= 0)
		error("cannot read from /cmd/clone");
	dir := "/cmd/" + string nam[0:nr];
	wfd := open(dir + "/wait", OREAD);
	if (wfd == nil)
		error("cannot write to /cmd/clone");
	efd := open(dir + "/ctl", OWRITE);
	if (efd == nil)
		error("cannot open ctl");

	if(fprint(efd, "exec %s", cmd) < 0)
		error("error: " + ERRORNOCMD);
	efd = nil;
	wfd = nil;
	cfd = nil;
}

init()
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	str = checkload(load String String->PATH, String->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	commandexists();
}

