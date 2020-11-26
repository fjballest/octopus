# Experimental webdav server to export the inferno namespace
# to the underlying host system, for systems other than Plan 9.
# See rfc2518 and rfc2616 for more information than wanted.

implement Dav;
include "sys.m";
	pctl, FORKFD, NEWPGRP, fildes, open, OREAD, ORDWR,
	OWRITE, announce, fprint, sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "netutil.m";
	nutil: Netutil;
	netmkaddr: import nutil;
include "bufio.m";
	Iobuf: import bufio;
include "daytime.m";
include "readdir.m";
include "xml.m";
include "error.m";
	checkload, stderr, error, kill: import err;
include "string.m";
include "svc.m";
include "msgs.m";
	Hdr, Msg: import msgs;
include "xmlutil.m";
include "names.m";
include "dlock.m";
include "dat.m";
	dat: Dat;

Dav: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
	sys:	Sys;
	err:	Error;
	str:	String;
	daytime:	Daytime;
	readdir:	Readdir;
	names:	Names;
	bufio:	Bufio;
	xml:	Xml;
	xmlutil:	Xmlutil;
	msgs:	Msgs;
	svc:	Svc;
	dlock:	Dlock;
};

debug := 0;
once := 0;

reqproc(reqc: chan of (ref Msg, chan of int))
{
	for(;;){
		(m, rc) := <-reqc;
		if(m == nil){
			if(debug)
				fprint(stderr, "dav: short request ignored\n");
			rc <-= 1;
			continue;
		}
		m.hdr.dump(debug);
		r := svc->run(m);
		if(r != nil &&  r.putrep() < 0){
			if(debug)
				fprint(stderr, "dav: putrep on %s: %r\n", m.hdr.cdir);
			rc <-= 1;
			continue;
		}
		if(!m.hdr.keep || once)
			rc <-= 1;
		else
			rc <-= 0;
	}
		
}

davsrv(rc: chan of int, reqc: chan of (ref Msg, chan of int), cdir, dir: string)
{
	iobin := bufio->open(cdir+"/data", OREAD);
	iobout := bufio->open(cdir+"/data", OWRITE);
	rc <-= pctl(0, nil);
	if(iobin == nil || iobout == nil)
		error(sprint("dav: bufio: %r"));
	if(debug)
		fprint(stderr, "\n\ndav: new client: %s for %s\n", cdir, dir);
	rc = chan of int;
	for(;;){
		m := Msg.getreq(iobin, iobout, cdir);
		reqc <-= (m, rc);
		if(<-rc != 0)
			break;
	}
	iobin.close();
	iobout.close();
	if(debug)
		fprint(stderr, "\ndav: gone client %s for %s\n\n", cdir, dir);
}

dav(addr, dir: string)
{
	if(debug){
		fprint(stderr, "o/dav: announcing %s\n", addr);
		fprint(stderr, "echo killgrp >/prog/%d/ctl\n\n", pctl(0,nil));
	}
	(aok, c) := announce(addr);
	if(aok < 0)
		error(sprint("dav: announce: %r"));
	reqc := chan of (ref Msg, chan of int);
	spawn reqproc(reqc);
	for(;;){
		(lok, nc) := sys->listen(c);
		if(lok < 0)
			error(sprint("dav: listen: %r"));
		rc := chan of int;
		spawn davsrv(rc, reqc, nc.dir, dir);
		<-rc;
		if(once)
			exit;
	}
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	str = checkload(load String String->PATH, String->PATH);
	bufio = checkload(load Bufio Bufio->PATH, Bufio->PATH);
	names = checkload(load Names Names->PATH, Names->PATH);
	daytime =checkload(load Daytime Daytime->PATH, Daytime->PATH);
	readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	xml = checkload(load Xml Xml->PATH, Xml->PATH);
	nutil = checkload(load Netutil Netutil->PATH, Netutil->PATH);
	msgs = checkload(load Msgs Msgs->PATH, Msgs->PATH);
	svc = checkload(load Svc Svc->PATH, Svc->PATH);
	xmlutil = checkload(load Xmlutil Xmlutil->PATH, Xmlutil->PATH);
	dlock = checkload(load Dlock Dlock->PATH, Dlock->PATH);
	dat = load Dat "$self";
	if(dat == nil)
		error(sprint("can't load dat: %r"));
	# addr := "tcp!127.0.0.1!http";
	addr := "tcp!127.0.0.1!9999";
	dir := "/";
	rdonly := 0;
	arg->init(argv);
	arg->setusage("dav [-1dr] [-a addr] [dir]");
	while((opt := arg->opt()) != 0) {
		case opt {
		'1' =>
			once = 1;
		'd' =>
			debug++;
			msgs->debug = debug;
			svc->debug = debug;
			xmlutil->debug = debug;
			dlock->debug = debug;
		'a' =>
			addr = arg->earg();
		'r' =>
			rdonly = 1;
		* =>
			arg->usage();
		}
	}
	pctl(NEWPGRP, nil);
	argv = arg->argv();
	if(len argv > 1)
		arg->usage();
	if(argv != nil)
		dir = hd argv;
	addr = netmkaddr(addr, "tcp", "http");
	svc->init(dat, dir, rdonly);
	msgs->init(dat);
	xml->init();
	xmlutil->init(dat);
	dlock->init(dat);
	spawn dav(addr, dir);
}

