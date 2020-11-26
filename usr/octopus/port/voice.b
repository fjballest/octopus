#
# Voice output, portable part. Uses mvoice.m for the host-dependent
# implementation.

# May be used as a prototype for file systems that have one or two
# files as their interface, relying on underlying host commands.
# Or perhaps provide a basic common module for such tools.

implement Voice;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	fprint, sprint, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "styxservers.m";
	styxs: Styxservers;
	Styxserver, readbytes, readstr, Navigator, Fid: import styxs;
	nametree: Nametree;
	Tree: import nametree;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "netget.m";
	netget: Netget;
include "env.m";
	env: Env;
	getenv: import env;
include "string.m";
	str: String;
	splitl: import str;
include "io.m";
	io: Io;
	readdev: import io;
include "mvoice.m";
	mvoice: Mvoice;
	speak: import mvoice;

Voice: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Qroot, Qvoice, Qndb: con big iota;

debug := 0;
user: string;

newdir(name: string, perm: int, qid: big): Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.qid.path = qid;
	if(perm & DMDIR)
		d.qid.qtype = QTDIR;
	else
		d.qid.qtype = QTFILE;
	d.mode = perm;
	return d;
}


fsreq(srv: ref Styxserver, nil: ref Tree, req: ref Tmsg) : ref Rmsg
{
		pick m := req {
		Read =>
			(fid, e) := srv.canread(m);
			if(e != nil)
				return ref Rmsg.Error(m.tag, e);
			if(fid.qtype&QTDIR)
				return nil;
			if(fid.path != Qndb)
				return readstr(m, "");
			data := netget->ndb();
			return readstr(m, data);
		Write =>
			(fid, e) := srv.canwrite(m);
			if(e != nil || fid.path != Qvoice)
				return ref Rmsg.Error(m.tag, e);
			s := string m.data;
			if(s != nil && s != ""){
				(s1, nil) := splitl(s, "\n");
				if(s1 != nil && s1 != "")
					speak(s1);
			}
			return ref Rmsg.Write(m.tag, len m.data);
		Wstat =>
			return ref Rmsg.Wstat(m.tag);
		* =>
			return nil;
		}
}

fs(pidc: chan of int, fd: ref FD)
{
	styx->init();
	styxs->init(styx);
 	user = getenv("user");
	if(user == nil)
		user = readdev("/dev/user", "none");
	if(pidc != nil)
		pidc <-= pctl(FORKNS|NEWPGRP|NEWFD, list of {0,1,2,fd.fd});
	else
		pctl(NEWPGRP, nil);
	stderr = fildes(2);
	netget->announce("voice", "path /voice");
	(tree, navc) := nametree->start();
	nav := Navigator.new(navc);
	(reqc, srv) := Styxserver.new(fd, nav, Qroot);
	tree.create(Qroot, newdir(".", DMDIR|8r775, Qroot));
	tree.create(Qroot, newdir("speak", 8r660, Qvoice));
	tree.create(Qroot, newdir("ndb", 8r440, Qndb));
	for(;;) {
		req := <-reqc;
		if(req == nil)
			break;
		rep := fsreq(srv, tree, req);
		if(rep == nil)
			srv.default(req);
		else
			srv.reply(rep);
	}
	tree.quit();
	netget->terminate();
	kill(pctl(0, nil),"killgrp");	# be sure to quit
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxs = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	nametree = checkload(load Nametree Nametree->PATH, Nametree->PATH);
	nametree->init();
  	io = checkload(load Io Io->PATH, Io->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	netget = checkload(load Netget Netget->PATH, Netget->PATH);
	mvoice = checkload(load Mvoice Mvoice->PATH, Mvoice->PATH);
	str = checkload(load String String->PATH, String->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("voice [-abcd] [-m mnt]");
	mnt: string;
	flag := MREPL|MCREATE;
	while((opt := arg->opt()) != 0) {
		case opt{
		'b' =>
			flag = MBEFORE;
		'a' =>
			flag = MAFTER;
		'c' =>
			flag |= MCREATE;
		'm' =>
			mnt = arg->earg();
		'd' =>
			debug = 1;
			styxs->traceset(1);
		* =>
			usage();
		}
	}
	if(len arg->argv() != 0)
		usage();
	e := mvoice->init();
	if(e != nil)
		error("voice: "+e);
	if(mnt == nil)
		fs(nil, fildes(0));
	else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("voice: pipe: %r"));
		pidc := chan of int;
		spawn fs(pidc, pfds[0]);
		<-pidc;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("voice: mount: %r"));
		pfds[0] = nil;
	}
}
