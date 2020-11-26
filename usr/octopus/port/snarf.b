#
# Shared networked clipboard.
# Binds itself above /chan to intercept
# I/O to snarf. /dev still points to local snarf, untouched.

# When written into, updates /mnt/snarf/buffer
# and posts a snarf event to /mnt/ports
# When it receives a snarf event from /mnt/ports, it reads /mnt/snarf/buffer
# and updates the local snarf.

implement Snarf;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, DMEXCL, OREAD, FD,
	OTRUNC, OWRITE, ORCLOSE, FORKFD, remove, write, 
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
	Styxserver, readbytes, readstr, Eexists, Enotfound, Navigator, Fid: import styxs;
	nametree: Nametree;
	Tree: import nametree;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "env.m";
	env: Env;
	getenv: import env;
include "io.m";
	io: Io;
	readdev: import io;

Snarf: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Qroot, Qsnarf: con big iota;
debug := 0;
user: string;
sfd: ref FD;	# fd to '#^/snarf'
ssfd: ref FD;	# fd to /mnt/snarf/buffer
srv: ref Styxserver;

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

post()
{
	fd := open("/mnt/ports/post", OWRITE);
	if(fd != nil)
		fprint(fd, "/mnt/snarf/buffer\n");
}

sync(): int
{
	if(debug)
		fprint(stderr, "o/snarf: sync\n");
	ns := readdev("/mnt/snarf/buffer", nil);
	if(ns == nil)
		ns = "";
	os := readdev("/chan/snarf", nil);
	if(ns != os){
		fd2 := open("/chan/snarf", OWRITE|OTRUNC);
		if(fd2 == nil){
			fprint(stderr, "o/snarf: /chan/snarf: %r\n");
			return -1;
		}
		fprint(fd2, "%s", ns);
		fd2 = nil;
	}
	return 0;
}

rsync()
{
	if(debug)
		fprint(stderr, "o/snarf: rsync\n");
	ns := readdev("/chan/snarf", nil);
	if(ns != nil){
		fd := open("/mnt/snarf/buffer", OWRITE|OTRUNC);
		if(fd != nil)
			fprint(fd, "%s", ns);
		fd = nil;
	}
}

syncproc()
{
	sn := getenv("sysname");
	
	fname := sprint("/mnt/ports/snarf.%s.%d", sn, pctl(0, nil));
	fd := create(fname, ORDWR|ORCLOSE, 8r664);
	if(fd == nil)
		error(sprint("o/snarf: %s: %r\n", fname));
	fprint(fd, "/mnt/snarf/buffer\n");
	sync();
	buf := array[100] of byte;
	for(;;){
		nr := read(fd, buf, len buf);
		if(nr < 0){
			fprint(stderr, "o/snarf: port read: %r\n");
			break;
		}
		if(nr == 0){
			fprint(stderr, "o/snarf: port eof\n");
			break;
		}
		if(sync() < 0)
			break;
	}
	fd = nil;
	remove(fname);
}

fsreq(srv: ref Styxserver, req: ref Tmsg) : ref Rmsg
{
	pick m := req {
	Open =>
		(fid, mode, file, e) := srv.canopen(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.qtype&QTDIR)
			return nil;
		if(mode == OREAD){
			# if copy was performed from the host OS
			# /mnt/snarf/buffer is out of date. fix it.
			spawn rsync();
			sfd = open("/chan/snarf", OREAD);
			ssfd = nil;
		} else {
			sfd = open("/chan/snarf", OWRITE);
			ssfd = open("/mnt/snarf/buffer", OWRITE|OTRUNC);
		}
		if(sfd == nil){
			ssfd = nil;
			return ref Rmsg.Error(m.tag, sprint("%r"));
		}
		fid.open(mode, file.qid);
		return ref Rmsg.Open(m.tag, file.qid, srv.iounit());
	Read =>
		(fid, e) := srv.canread(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.qtype&QTDIR)
			return nil;
		buf := array[m.count] of byte;
		nr := read(sfd, buf, len buf);
		if(nr < 0)
			return ref Rmsg.Error(m.tag, sprint("%r"));
		return ref Rmsg.Read(m.tag, buf[0:nr]);
	Write =>
		(nil, e) := srv.canwrite(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		nw := write(sfd, m.data, len m.data);
		if(ssfd != nil)
			write(ssfd, m.data, len m.data);
		return ref Rmsg.Write(m.tag, nw);
	Clunk =>
		fid := srv.getfid(m.fid);
		if(fid == nil)
			return ref Rmsg.Error(m.tag, "bad fid");
		if(fid.path == Qsnarf && fid.isopen){
			sfd = nil;
			if(ssfd != nil){
				ssfd = nil;
				post();
			}
		}
		srv.delfid(fid);
		return ref Rmsg.Clunk(m.tag);
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
	fd = fildes(fd.fd);
	stderr = fildes(2);				# lost by pctl
	spawn syncproc();
	(tree, navc) := nametree->start();
	nav := Navigator.new(navc);
	(reqc, s) := Styxserver.new(fd, nav, Qroot);
	srv = s;
	tree.create(Qroot, newdir(".", DMDIR|8r555, Qroot));
	tree.create(Qroot, newdir("snarf", 8r660, Qsnarf));
	for(;;) {
		req := <-reqc;
		if(req == nil)
			break;
		rep := fsreq(srv, req);
		if(rep == nil)
			srv.default(req);
		else
			srv.reply(rep);
	}
	tree.quit();
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
 	env = checkload(load Env Env->PATH, Env->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("o/snarf [-abcd] [-m mnt]");
	mnt: string;
	flag := MBEFORE;
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
	args = arg->argv();
	if(len args != 0)
		usage();
	if(mnt == nil)
		mnt = "/chan";
	pfds := array[2] of ref FD;
	if(pipe(pfds) < 0)
		error(sprint("o/snarf: pipe: %r"));
	pidc := chan of int;
	spawn fs(pidc, pfds[0]);
	<-pidc;
	pfds[0] = nil;
	if(mount(pfds[1], nil, mnt, flag, nil) < 0)
		error(sprint("o/snarf: mount: %r"));
}
