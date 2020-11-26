# Nop to styx file server.
# coherent caching client part using nop.
# most of the styx code comes from Inferno's styxservers.b
# that module is not used to exploit what we now when we
# receive styx requests.

implement Nopi;

include "sys.m";
	sys: Sys;
	fprint, mount, pipe, fildes, FD, MCREATE, sprint,
	MREPL, NEWPGRP, FORKNS, Connection, NEWFD,
	open, pctl, dial, OREAD, ORDWR, OWRITE: import sys;
include "nop.m";
	nop: Nop;
include "draw.m";
include "arg.m";
	arg: Arg;
	usage: import arg;
include "error.m";
	err: Error;
	panic, checkload, stderr, error, kill: import err;
include "netutil.m";
	util: Netutil;
	netmkaddr, authfd: import util;
include "blks.m";
	blks: Blks;
	Blk: import Blks;
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "ssrv.m";
	ssrv: Ssrv;
	Srv: import ssrv;
include "readdir.m";
	readdir: Readdir;
include "cache.m";
	cache: Cache;
include "tree.m";
	tree: Tree;

Nopi: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

debug := 0;

terminate(e: string)
{
	if(debug)
		fprint(stderr,  "nopi: exiting: " + s + "\n");
	kill(pctl(0,nil), "killgrp");
}

rdproc(fd: ref FD, srv: ref Srv)
{
	stderr = fildes(2);
	m: ref Tmsg;
	do {
		m = Tmsg.read(fd, srv.msize);
		if(debug && m != nil)
			fprint(stderr, "<- %s\n", m.text());
		srv.reqc <-= m;
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	srv.repc <-= nil;
	terminate("read");
}

wrproc(fd: ref FD, srv: ref Srv)
{
	stderr = fildes(2);
	for(;;){
		m := <-srv.repc;
		if(m == nil)
			break;
		if(srv.msize == 0)
			m = ref Rmsg.Error(m.tag, "Tversion not seen");
		if(debug)
			fprint(stderr, "-> %s\n", m.text());
		d := m.pack();
		if(srv.msize != 0 && len d > srv.msize){
			m = ref Rmsg.Error(m.tag, "Styx reply didn't fit");
			d = m.pack();
		}
		if(write(srv.fd, d, len d) != len d)
			terminate(sprint("write: %r"));
	}
}

srvreq(srv: ref Srv, t: ref Tmsg): ref  Rmsg
{
	pick m := t {
	Readerror => terminate();
	Version =>
		srv.repc <-= srv.version(m);
	Auth =>
		srv.repc <-= srv.auth(m);
	Attach =>
		srv.repc <-= srv.attach(m);
	Stat =>
		srv.repc <-= srv.stat(m);
	Walk =>
		srv.repc <-= srv.walk(m);
	Open =>
		srv.repc <-= srv.open(m);
	Create =>
		srv.repc <-= srv.create(m);
	Read =>
		srv.repc <-= srv.read(m);
	Write =>
		srv.repc <-= srv.write(m);
	Clunk =>
		srv.repc <-= srv.clunk(m);
	Remove =>
		srv.repc <-= srv.remove(m);
	Wstat =>
		srv.repc <-= srv.wstat(m);
	Flush =>
		srv.repc <-= srv.flush(m);
	* =>
		panic("bad styx request");
	}
}

srvproc(pidc: chan of int, sfd, cfd: ref FD, cdir: string, path: string)
{
	if(debug)
		fprint(stderr, "echo killgrp >/prog/%d/ctl\n", pctl(0, nil));
	pidc <-= pctl(FORKNS|NEWPGRP|NEWFD, list of {0,1,2,sfd.fd,cfd.fd});
	stderr = fildes(2);
	nop->init(sys, blks);
	styx->init();
	ssrv->init(styx, cache);
	tree->init(sys, str, err, names, readdir);
	cache->init(sys, err, nop, blks, tree);
	if((e := cache->attach(sfd, cdir)) != nil)
		terminate("nopattach: " + e);
	srv := Srv.new(cache->root());
	spawn rdproc(cfd, srv);
	spawn wrproc(cfd, srv);
	for(;;){
		req := <-reqc;
		if(req == nil)
			break;
		spawn srvreq(srv, req);
	}
	terminate("eof");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	nop = checkload(load Nop Nop->PATH, Nop->PATH);
	blks = checkload(load Blks Blks->PATH, Blks->PATH);
	blks->init();
	cache = checkload(load Cache Cache->PATH, Cache->PATH);
	tree = checkload(load Tree Tree->PATH, Tree->PATH);
	util = checkload(load Netutil Netutil->PATH, Netutil->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);

	mnt := "/mnt/nopi";
	path := "/";
	cdir, addr: string;
	arg->init(args);
	arg->setusage("ofs [-d] [-c dir] [-m mnt] addr [path]");
	while((opt := arg->opt()) != 0) {
		case opt{
		'c' =>
			cdir = arg->earg();
		'd' =>
			debug++;
		'm' =>
			mnt = arg->earg();
		* =>
			usage();
		}
	}
	args = arg->argv();
	case len args {
	2 =>
		addr = hd args;
		path = hd tl args;
	1 =>
		addr = hd args;
	* =>
		usage();
	}

	opfd, opcfd : ref FD;
	if(addr[0] == '/')
		opfd = open(addr, ORDWR);
	if(opfd == nil){
		addr = netmkaddr(addr, "tcp", "op");
		(rc, c) := dial(addr, nil);
		if(rc < 0)
			error(sprint("%s: %r\n", addr));
		opfd = c.dfd;
		opcfd = c.cfd;
		c.dfd = c.cfd = nil;
	}
	pidc := chan[1] of int;
	pfds := array[2] of ref FD;
	if(pipe(pfds) < 0)
		error(sprint("ofs: pipe: %r"));
	spawn srvproc(pidc, pfds[0], opfd, cdir, path);
	<- pidc;
	pfds[0] = nil;
	opfd = nil;
	if(mount(pfds[1], nil, mnt, MREPL|MCREATE, nil) < 0)
		error(sprint("ofs: mount: %r"));
	pfds[0] = nil;
}

