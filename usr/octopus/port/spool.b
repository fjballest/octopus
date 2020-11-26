#
# File spooler. To build file systems that accept
# files to be given to underlying host commands.

# BUGS: This needs improvements:
#	-> listen to endc to detect when the file has been processed, and remove it.
#	-> accept general ctl requests via ctl, and pass them to the underlying spooler
#		module.
#	-> create FILE.status stream file, which reports (via read) any message sent
#		through endc until receiving nil, in which case it reports eof.


implement Spool;
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
include "daytime.m";
	daytime: Daytime;
	now: import daytime;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "tbl.m";
	tbl: Tbl;
	Table: import tbl;
include "netget.m";
	netget: Netget;
include "string.m";
	str: String;
	splitr: import str;
include "env.m";
	env: Env;
	getenv: import env;
include "spooler.m";
	spooler: Spooler;
	Sfile: import spooler;
include "io.m";
	io: Io;
	readdev: import io;

Spool: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

File: adt {
	name:	string;
	path:	string;
	fd:	ref FD;
	vers:	int;
	sf:	ref Sfile;
};

files: ref Table[ref File];	# indexed by qid.

Qroot, Qctl, Qndb: con big iota;
qgen:= Qndb;
debug := 0;
user: string;
argv0 := "spool";
readstarts := 0;		# reading a file starts the spooler as well

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

fsreq(srv: ref Styxserver, tree: ref Tree, req: ref Tmsg) : ref Rmsg
{
	pick m := req {
	Create =>
		(fid, mode, d, e) := srv.cancreate(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag,  e);
		if(mode&DMDIR)
			return ref Rmsg.Error(m.tag, "can't handle directories");
		fpath := sprint("/tmp/%s.%d.%s", argv0, int qgen, d.name);
		f := ref File(d.name, fpath, nil, 0, nil);
		f.fd = create(f.path, OWRITE, 8r664);
		if(f.fd == nil)
			return ref Rmsg.Error(m.tag, sprint("tmpfile: %r"));
		d.qid = Qid(++qgen, 0, 0);
		d.atime = d.mtime = now();
		e = tree.create(Qroot, *d);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		fid.open(mode, d.qid);
		files.add(int fid.path, f);
		return ref Rmsg.Create(m.tag, d.qid, srv.iounit());
	Remove =>
		(fid, nil, e) := srv.canremove(m);
		srv.delfid(fid);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.path == Qctl || fid.path == Qndb)
			return ref Rmsg.Error(m.tag, "permission denied");
		e = tree.remove(fid.path);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		f := files.del(int fid.path);
		if(f != nil && f.sf != nil)
			f.sf.stop(); 
		return ref Rmsg.Remove(m.tag);
	Read =>
		(fid, e) := srv.canread(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.qtype&QTDIR)
			return nil;
		data := "";
		case fid.path {
		Qctl =>
			data = spooler->status() + "\n";
		Qndb =>
			data = netget->ndb() + "\n";
		}
		return readstr(m, data);
	Write =>
		(fid, e) := srv.canwrite(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.path == Qctl || fid.path == Qndb)
			return ref Rmsg.Error(m.tag, "permission denied");
		f := files.find(int fid.path);
		if(f.fd == nil)
			f.fd = open(f.path, OWRITE);
		if(f == nil || f.fd == nil)
			return ref Rmsg.Error(m.tag, "file not found");
		nw := pwrite(f.fd, m.data, len m.data, m.offset);
		if(nw < 0)
			return ref Rmsg.Error(m.tag, sprint("%r"));
		f.vers++;
		return ref Rmsg.Write(m.tag, nw);
	Clunk =>
		fid := srv.getfid(m.fid);
		if(fid == nil)
			return ref Rmsg.Error(m.tag, "bad fid");
		if(fid.path != Qctl && fid.path != Qroot && fid.path != Qndb){
			f := files.find(int fid.path);
			if(f != nil && f.fd != nil && f.vers > 0 && fid.isopen){
				if(fid.mode == OWRITE || fid.mode == ORDWR || readstarts){
					f.fd = nil; #close it for windows
					(f.sf, nil) = Sfile.start(f.path, nil);
				}
				# BUG: should listen through endc (nil above)
				# and remove the file or report diagnostics
				# sent through it.
			}
		}
		srv.delfid(fid);
		return ref Rmsg.Clunk(m.tag);
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
	netget->announce(argv0, sprint("path /%s", argv0));
	(tree, navc) := nametree->start();
	nav := Navigator.new(navc);
	(reqc, srv) := Styxserver.new(fd, nav, Qroot);
	tree.create(Qroot, newdir(".", DMDIR|8r775, Qroot));
	tree.create(Qroot, newdir("ctl", 8r444, Qctl));
	tree.create(Qroot, newdir("ndb", 8r444, Qndb));
	nullfile: ref File;
	files = Table[ref File].new(103, nullfile);
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
	str = checkload(load String String->PATH, String->PATH);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxs = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	nametree = checkload(load Nametree Nametree->PATH, Nametree->PATH);
	nametree->init();
 	daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	tbl = checkload(load Tbl Tbl->PATH, Tbl->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	netget = checkload(load Netget Netget->PATH, Netget->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("spool [-abcdr] [-m mnt] module");
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
		'r' =>
			readstarts = 1;
		* =>
			usage();
		}
	}
	args = arg->argv();
	if(len args < 1)
		usage();
	argv0 = hd args;
	(nil, s2) := splitr(argv0, "/");
	if(s2 != nil && s2 != "")
		argv0 = s2;
	dis := "/dis/" + (hd args) + ".dis";
	spooler = checkload(load Spooler dis, dis);
	spooler->init(tl args);
	spooler->debug = debug;
	if(mnt == nil)
		fs(nil, fildes(0));
	else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("%s: pipe: %r", argv0));
		pidc := chan of int;
		spawn fs(pidc, pfds[0]);
		<-pidc;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("%s: mount: %r", argv0));
		pfds[0] = nil;
	}
}
