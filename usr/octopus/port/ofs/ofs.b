# Op to styx file server
implement Ofs;

include "sys.m";
	sys: Sys;
	MREPL, FD, MAFTER, DMDIR, QTDIR, fprint, pctl, fildes,
	MBEFORE, MCREATE, create, OREAD,
	open, read, ORDWR, nulldir, dial, sprint, pipe, stat,
	mount, werrstr, OTRUNC: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "ofsstyx.m";
	styxs: Styxservers;
	Styxserver, Fid, Ebadfid, Navigator, Navop: import styxs;
	Enotdir, Enotfound: import styxs;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "keyring.m";
include "security.m";
include "env.m";
	env: Env;
	getenv: import env;
include "string.m";
	str: String;
	splitstrl: import str;
include "netutil.m";
	util: Netutil;
	Client, netmkaddr, authfd : import util;
include "op.m";
	op: Op;
include "opmux.m";
	opmux: Opmux;
include "stop.m";
	stop: Stop;
include "error.m";
	err: Error;
	checkload, kill, stderr, error: import err;
include "ofsnotify.m";
	notify: Ofsnotify;

Ofs: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Stats: adt {
	nwalk, nopen, ncreate, nread, nwrite: int;
	nclunk, nstat, nremove, nwstat: int;

	dump: fn(s: self ref Stats);
};

# Process model:
# 	requestproc accepts one request after another from either the styxserver
#	or the navigator, and spawns one process per request (either
#	fsreq or navreq). Thus, we process concurrent requests.
#
#	In the stop cache, a single process synchronizes access to the tree and takes
#	one request after another. However, it spawns other processes to speak
#	Op. Cached requests are replied by the central cfsproc process. Other
#	requests spawn a process to issue the Op RPC(s) concurrently.
#	Such Op speaker processes are spawned by xcfsproc(), to control the max
#	number of concurrent requests that we might place on the remote server.
#
#	replyproc accepts one reply after another to be sent to the client


debug := 0;
doauth := 1;
dostats := 0;
stats : ref Stats;
user := "none";

Stats.dump(s: self ref Stats)
{
	tot := s.nwalk + s.nopen + s.ncreate + s.nread + s.nwrite;
	tot += s.nclunk + s.nstat + s.nremove  + s.nwstat;
	tot += 2;	# attach/version
	fprint(stderr,"styx:\n");
	fprint(stderr,"\t%s\t%d\n", "walk", s.nwalk);
	fprint(stderr,"\t%s\t%d\n", "open", s.nopen);
	fprint(stderr,"\t%s\t%d\n", "create", s.ncreate);
	fprint(stderr,"\t%s\t%d\n", "read", s.nread);
	fprint(stderr,"\t%s\t%d\n", "write", s.nwrite);
	fprint(stderr,"\t%s\t%d\n", "clunk", s.nclunk);
	fprint(stderr,"\t%s\t%d\n", "stat", s.nstat);
	fprint(stderr,"\t%s\t%d\n", "remove", s.nremove);
	fprint(stderr,"\t%s\t%d\n", "wstat", s.nwstat);
	fprint(stderr,"\ttotal\t%d\n", tot);
}


navreq(m: ref Navop)
{
	qid := m.path;
	pick n := m {
	Stat =>
		n.reply <-= stop->stat(m.tag, qid);
	Walk =>
		if(n.name == nil || n.name == ".")
			n.reply <-= stop->validate(m.tag, qid, "");
		else if(n.name[0] == '/'){
			# see ./ofsstyxservers.b
			# Got "/a/b/c" because we are about to process a Twalk
			# for {a, b, c} for qid.
			# Here is when we check that the cache entry is valid.
			stats.nwalk++;
			(nil, sub) := splitstrl(n.name, "!!DUMP");
			if(sub != nil){
				# stop->dump();
				stats.dump();
				opmux->dump();
			}
			n.reply <-= stop->validate(m.tag, qid, n.name);
		} else{
			# Then we get one-by-one walks
			n.reply <-= stop->walk1(m.tag, qid, n.name);
		}
	Readdir =>
		# BUG: This asks stop to read a directory a lot of times,
		# even for a single directory.  Fixing this requires changes to
		# Styxserver.read (label Dread in ofsstyx.b).
		# Indeed, the real BUG is that the navigator should go.
		# We can adjust ofsstyx.b to ask us what we know we have
		# in stop.b

		(dl, e) := stop->readdir(m.tag, qid, n.count, n.offset);
		if(e != nil)
			n.reply <-= (nil, e);
		else {
			for(; dl != nil; dl = tl dl)
				n.reply <-= (ref hd dl, nil);
			n.reply <-= (nil, nil);
		}
	}
}

ofsreq(srv: ref Styxserver, req: ref Tmsg)
{
	if(req != nil)
	pick m := req {
	Readerror =>
		fprint(stderr, "ofs: read error: %s\n", m.error);
	Attach =>
		# Tattach wont Twalk "/", and stop  validates at Twalk
		(nil, e) := stop->validate(m.tag, big 0, "");
		if(e != nil)
			srv.reply(ref Rmsg.Error(m.tag, e));
		else
			srv.attach(m);
	Open =>
		stats.nopen++;
		umode := m.mode;	# save OTRUNC
		fid := srv.open(m);
		if(fid != nil)
		if((umode & OTRUNC) != 0){
			d := ref nulldir;
			d.length = big 0;
			stop->wstat(m.tag, fid.path, d);	# this truncates.
		}
	Read =>
		stats.nread++;
		(fid, e) := srv.canread(m);
		if(e != nil){
			srv.reply(ref Rmsg.Error(m.tag, e));
			return;
		}
		if(fid.qtype & QTDIR){
			srv.default(m);
			return;
		}
		(d, re) := stop->pread(m.tag, fid.path, m.count, m.offset);
		if(re != nil)
			srv.reply(ref Rmsg.Error(m.tag, re));
		else
			srv.reply(ref Rmsg.Read(m.tag, d));		
	Write =>
		stats.nwrite++;
		(fid, e) := srv.canwrite(m);
		if(e != nil){
			srv.reply(ref Rmsg.Error(m.tag, e));
			return;
		}
		we : string;
		cnt : int;
		if(len m.data > 0)
			(cnt, we) = stop->pwrite(m.tag, fid.path, m.data, m.offset);
		if(we != nil)
			srv.reply(ref Rmsg.Error(m.tag, we));
		else
			srv.reply(ref Rmsg.Write(m.tag, cnt));
	Flush =>
		stop->flush(m.tag, m.oldtag);
		srv.reply(ref Rmsg.Flush(m.tag));
	Clunk =>
		stats.nclunk++;
		fid := srv.getfid(m.fid);
		if(fid == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
			return;
		}
		srv.delfid(fid);
		e := stop->sync(m.tag, fid.path);
		if(e != nil)
			srv.reply(ref Rmsg.Error(m.tag, e));
		else
			srv.reply(ref Rmsg.Clunk(m.tag));
	Create =>
		stats.ncreate++;
		(fid, mode, d, e) := srv.cancreate(m);
		if(e != nil){
			srv.reply(ref Rmsg.Error(m.tag, e));
			return;
		}
		(d, e) = stop->create(m.tag, fid.path, d);
		if(e != nil){
			srv.reply(ref Rmsg.Error(m.tag, e));
			return;
		}
		fid.open(mode, d.qid);
		srv.reply(ref Rmsg.Create(m.tag, d.qid, 8*1024));
	Remove =>
		stats.nremove++;
		(fid, nil, e) := srv.canremove(m);
		if(e != nil) {
			srv.reply(ref Rmsg.Error(m.tag, e));
			return;
		}
		e = stop->remove(m.tag, fid.path);
		if(e != nil){
			srv.reply(ref Rmsg.Error(m.tag, e));
			return;
		}
		srv.delfid(fid);
		srv.reply(ref Rmsg.Remove(m.tag));
	Wstat =>
		stats.nwstat++;
		fid := srv.getfid(m.fid);
		if(fid == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
			return;
		}
		(nil, e) := stop->wstat(m.tag, fid.path, ref m.stat);
		if(e != nil)
			srv.reply(ref Rmsg.Error(m.tag, e));
		else
			srv.reply(ref Rmsg.Wstat(m.tag));
	*  =>
		srv.default(m);
	}
}

terminate(srv: ref Styxserver, navc: chan of ref Navop, optoo: int)
{
	if(dostats){
		stats.dump();
		opmux->dump();
	}
	if(notify != nil)
		notify->gone();
	navc <-= nil;
	stop->term();
	if(optoo)
		opmux->term();
	srv.replychan <-= nil;
	kill(pctl(0,nil), "killgrp");	# kill tmsgreader and any other
	exit;
}

fsrequestproc(srv: ref Styxserver, reqc: chan of ref Tmsg, navc: chan of ref Navop, endc: chan of string)
{
	if(debug)
		fprint(stderr, "echo killgrp >/prog/%d/ctl\n", pctl(0,nil));
	if(notify != nil)
		notify->arrived();
	for(;;){
		# BUG: should cache fs and nav processes.
		alt {
		<- endc =>
			terminate(srv, navc, 0);
		r := <-reqc =>
			if(r == nil)
				terminate(srv, navc, 1);
			ofsreq(srv, r);
		}
	}
}

navrequestproc(navc: chan of ref Navop)
{
	for(;;){
		n := <-navc;
		if(n == nil)
			exit;
		navreq(n);
	}
}

replyproc(srv: ref Styxserver)
{
	for(;;){
		r := <- srv.replychan;
		if(r == nil)
			break;
		nw := srv.replydirect(r);
		if(nw < 0){
			opmux->term();
			stop->term();
			break;
		}
	}
}

attach(path: string) : string
{
	rc := opmux->rpc(ref (Op->Tmsg).Attach(0, "nemo", path));
	r := <- rc;
	pick rr := r {
	Attach =>
		return nil;
	Error =>
		return rr.ename;
	* =>
		return "can't attach";
	}
}

dorecover := 0;
recoveraddr: string;
recoveralg: string;
recoverkfile: string;
recoverpath: string;

recover(): ref FD
{
	addr := recoveraddr;
	alg := recoveralg;
	kfile := recoverkfile;
	opfd, opcfd: ref FD;
	while(dorecover){
		if(addr[0] == '/')
			opfd = open(addr, ORDWR);
		if(opfd == nil){
			addr = netmkaddr(addr, "tcp", "op");
			(rc, c) := dial(addr, nil);
			if(rc < 0)
				continue;
			opfd = c.dfd;
			opcfd = c.cfd;
			c.dfd = c.cfd = nil;
		}
		if(doauth){
			(afd, ae) := authfd(opfd, Client, alg, kfile, addr);
			opfd = afd; afd = nil;
			if(debug && ae != nil)
				fprint(stderr, "ofs: authenticated: %s\n", ae);
			if(opfd == nil)
				continue;
			user = ae;
		}
		e := attach(recoverpath);
		if(e == nil)
			return opfd;
	}
	return nil;
}

service(pidc: chan of int, sfd, cfd: ref FD, cdir: string, path: string, lag: int)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWPGRP|Sys->NEWFD, list of {0,1,2,sfd.fd,cfd.fd});
	stats = ref Stats(0, 0, 0, 0, 0, 0, 0, 0, 0);
	op->init();
	endc := chan[1] of string;
	opmux->init(cfd, op, endc);
	e := attach(path);
	if(e != nil){
		sfd = cfd = nil;
		error("ofs: can't attach");
	} else if(debug)
		fprint(stderr, "attached as %s\n", user);
	styx->init();
	styxs->init(styx);
	navc := chan of ref Navop;
	nav := Navigator.new(navc);
	(reqc, srv) := Styxserver.new(sfd, nav, big 0);
	srv.replychan = chan[10] of ref Styx->Rmsg;
	spawn replyproc(srv);
	if(stop->init(styx, opmux, cdir, lag) != nil){
		fprint(stderr, "should not happen: cache init failed\n");
		raise("fail:stop");
	}
	spawn navrequestproc(navc);
	spawn fsrequestproc(srv, reqc, navc, endc);
	if(debug)
		fprint(stderr, "ps | grep ' %d ' \n", pctl(0,nil));
}

oimport(fd: ref FD): string
{
	data := array[10] of byte;

	nr := read(fd, data, 9);
	if(nr <= 0){
		if(debug)fprint(stderr, "ofs: import: %r\n");
		return nil;
	}
	dr := int (string data);
	data = array[dr] of byte;
	nr = read(fd, data, dr);
	if(nr != dr){
		if(debug)fprint(stderr, "ofs: import: short read\n");
		return nil;
	}
	return string data;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxs = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	str = checkload(load String String->PATH, String->PATH);
	op = checkload(load Op Op->PATH, Op->PATH);
	opmux = checkload(load Opmux Opmux->PATH, Opmux->PATH);
	stop = checkload(load Stop Stop->PATH, Stop->PATH);
	util = checkload(load Netutil Netutil->PATH, Netutil->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);

	mnt : string;
	cdir, alg, kfile : string;
	path := "/";
	arg->init(args);
	lag := 1000;
	arg->setusage("ofs [-Adr] [-C alg] [-k keyfile] [-c dir] [-m mnt] [-l n] addr [path]");
	while((opt := arg->opt()) != 0) {
		case opt{
		'A' =>
			doauth = 0;
		'C' =>
			alg = arg->earg();
		'k' =>
			kfile = arg->earg();
		'c' =>
			cdir = arg->earg();
		'd' =>
			debug++;
			if(debug > 1)
				opmux->debug = 1;
			if(debug > 2)
				stop->debug = 1;
			styxs->traceset(1);
		'v' =>
			dostats = 1;
		'l'	=>
			lag = int arg->earg();
		'm' =>
			mnt = arg->earg();
		'r' =>
			dorecover = 1;
		* =>
			usage();
		}
	}
	addr : string;
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
	if(doauth){
		(afd, ae) := authfd(opfd, Client, alg, kfile, addr);
		opfd = afd; afd = nil;
		if(debug && ae != nil)
			fprint(stderr, "ofs: authenticated: %s\n", ae);
		if(opfd == nil)
			error(sprint("ofs: fail: %s: %r\n", addr));
		user = ae;
	}
	pidc := chan[1] of int;
	if(mnt == nil)
		service(pidc, fildes(0), opfd, cdir, path, lag);
	else {
		if(mnt == "auto"){
			sname := oimport(opfd);
			if(sname == nil)
				error("ofs: fail: import\n");
			mnt = "/terms/" + sname;
			fprint(stderr, "ofs: importing %s\n", sname);
			cfd := create(mnt, OREAD, DMDIR|8r0555);	# in case it does not exist
			if(cfd == nil)
				fprint(stderr, "ofs: create %s: %r\n", mnt);
			notify = load Ofsnotify Ofsnotify->PATH;
			if(notify != nil)
				notify->init(sname);
		} else if(dorecover){
			recoveraddr = addr;
			recoveralg = alg;
			recoverkfile= kfile;
			recoverpath = path;
			opmux->recoverfn = recover;
		}
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("ofs: pipe: %r"));
		spawn service(pidc, pfds[0], opfd, cdir, path, lag);
		<- pidc;
		pfds[0] = nil;
		opfd = nil;
		if(mount(pfds[1], nil, mnt, MREPL|MCREATE, nil) < 0)
			error(sprint("ofs: mount: %r"));
		pfds[0] = nil;
	}
}

