#
# Multiplexed octopus connections.
# Provides a file tree that switches from one
# implementor to another without breaking the client name space.
#
# BUG:
# leads to a clone failed for /mnt/view in the o/x name space.
# Must trace and fix it.

implement Mux;

include "sys.m";
	sys: Sys;
	fildes, fprint, FD, OTRUNC, DMDIR, ORCLOSE, OREAD, ORDWR,
	Qid, print, pctl, create, mount, QTDIR, pread, open, sprint, NEWPGRP,
	FORKNS, NEWFD, MREPL, MBEFORE, MCREATE, MAFTER, pipe, 
	pwrite, remove, nulldir, fwstat, wstat, fstat, stat, Dir, write, sleep, millisec: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg, NOFID, IOHDRSZ, VERSION, MAXRPC,
	unpackdir, compatible, packdir, NOTAG: import styx;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "names.m";
	names: Names;
	dirname, cleanname, relative, isprefix, rooted: import names;

Mux: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

include "muxdat.m";
	dat: Muxdat;
	Qroot, NOQID, Fid, rebind, rootdir, brokenfs,
	bindrootdir, addfid, delfid, getfid, maybebroken,
	addqid, getqid, fixqid, delqid, renametree, debug, qgen: import dat;

slash:	ref Fid;
msize:	int;

terminate()
{
	if(debug)
		fprint(stderr, "mux: terminating\n");
	kill(pctl(0,nil), "killgrp");	# kill tmsgreader and any other
	exit;
}

fsversion(m: ref Tmsg.Version): ref Rmsg
{
	if(msize <= 0)
		msize = MAXRPC;
	(sz, nil) := compatible(m, msize, Styx->VERSION);
	if(sz < 256)
		return ref Rmsg.Error(m.tag, "message size too small");
	if(sz > 4096)
		sz = 4096;	# BUG
	msize = sz;
	return ref Rmsg.Version(m.tag, msize, Styx->VERSION);
}

fsattach(m: ref Tmsg.Attach): ref Rmsg
{
	slash = ref Fid(m.fid, nil, 0, -1, Qroot, rootdir);
	if(addfid(slash) < 0){
		slash = nil;
		return ref Rmsg.Error(m.tag, "fid already exists");
	}
	slash.qid = Qroot;
	slash.path = rootdir;
	q := addqid(rootdir);
	if(q != Qroot.path)
		panic("bug: first qid != Qroot");
	return ref Rmsg.Attach(m.tag, Qroot);
}

fsopen(m: ref Tmsg.Open): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	if(fid.fd != nil)
		return ref Rmsg.Error(m.tag, "fid already open");
	fid.fd = open(fid.path, m.mode);
	if(fid.fd == nil){
		e := sprint("%r");
		maybebroken(e);
		return ref Rmsg.Error(m.tag, e);
	}
	fid.omode = m.mode;
	return ref Rmsg.Open(m.tag, fid.qid, msize - IOHDRSZ);
}

fixdirqids(fid: ref Fid, b: array of byte)
{
	d: Dir;
	n := 0;
	for(o := 0; o < len b; o += n){
		(n, d) = unpackdir(b[o:]);
		if(n <= 0){
			if(n < 0 && debug)
				fprint(stderr, "fixdirqids: unpack: %r\n");
			break;
		}
		path := rooted(fid.path, d.name);
		d.qid = fixqid(path, d.qid);
		b[o:] = packdir(d);
		o += n;
	}
}

fsread(m: ref Tmsg.Read): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	if(fid.fd == nil)
		return ref Rmsg.Error(m.tag, "fid not open");
	if(m.count > msize)
		return ref Rmsg.Error(m.tag, "count too big");
	b := array[m.count] of byte;
	nr := pread(fid.fd, b, m.count, m.offset);
	if(nr < 0){
		e := sprint("%r");
		maybebroken(e);
		return ref Rmsg.Error(m.tag, e);
	}
	nb := b[0:nr];
	b = nil;
	if(fid.qid.qtype&QTDIR)
		fixdirqids(fid, nb);
	return ref Rmsg.Read(m.tag, nb);
}

fswrite(m: ref Tmsg.Write): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	if(fid.fd == nil)
		return ref Rmsg.Error(m.tag, "fid not open");
	if(len m.data > msize)
		return ref Rmsg.Error(m.tag, "count too big");
	nw := pwrite(fid.fd, m.data, len m.data, m.offset);
	if(nw < 0){
		e := sprint("%r");
		maybebroken(e);
		return ref Rmsg.Error(m.tag, e);
	} else
		return ref Rmsg.Write(m.tag, nw);
}

fsclunk(m: ref Tmsg.Clunk): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	delfid(fid);
	fid.fd = nil;
	return ref Rmsg.Clunk(m.tag);
}

fscreate(m: ref Tmsg.Create): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	if(fid.fd != nil)
		return ref Rmsg.Error(m.tag, "fid already open");
	npath := rooted(fid.path, m.name);
	if(npath == nil)
		return ref Rmsg.Error(m.tag, "bad name");
	fd := create(npath, m.mode, m.perm);
	if(fd == nil){
		e := sprint("create %s %x %o: %r", npath, m.mode, m.perm);
		maybebroken(e);
		return ref Rmsg.Error(m.tag, e);
	}
	fid.fd = fd;
	fid.path = npath;
	fid.qid = Qid(big 0, 0, 0);
	if(m.mode&DMDIR)
		fid.qid.qtype = QTDIR;
	fid.qid = fixqid(fid.path, fid.qid);
	fid.omode = m.mode;
	return ref Rmsg.Create(m.tag, fid.qid, msize - IOHDRSZ);
}

fsremove(m: ref Tmsg.Remove): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	path := fid.path;
	delfid(fid);
	if(remove(path) < 0){
		e := sprint("%r");
		maybebroken(e);
		return ref Rmsg.Error(m.tag, e);
	} else {
		delqid(fid.path);
		return ref Rmsg.Remove(m.tag);
	}
}

fswstat(m: ref Tmsg.Wstat): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	m.stat.qid = nulldir.qid;
	ec: int;
	if(fid.fd != nil)
		ec = fwstat(fid.fd, m.stat);
	else
		ec = wstat(fid.path, m.stat);
	if(ec < 0){
		e := sprint("%r");
		maybebroken(e);
		return ref Rmsg.Error(m.tag, e);
	} else {
		if(m.stat.name != nil)
			renametree(fid.path, m.stat.name);
		return ref Rmsg.Wstat(m.tag);
	}
}

fsstat(m: ref Tmsg.Stat): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	ec: int;
	d: Dir;
	if(fid.fd != nil)
		(ec,d) = fstat(fid.fd);
	else
		(ec,d) = stat(fid.path);
	if(ec < 0){
		if(debug)
			fprint(stderr, "stat: %s: %r\n", fid.path);
		e := sprint("%r");
		maybebroken(e);
		return ref Rmsg.Error(m.tag, sprint("%r"));
	}
	if(fid.path == rootdir)
		d.name = "/";
	d.qid = fid.qid = fixqid(fid.path, d.qid);
	return ref Rmsg.Stat(m.tag, d);
}

fswalk(m: ref Tmsg.Walk): ref Rmsg
{
	fid := getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, "bad fid");
	if(fid.broken)
		return ref Rmsg.Error(m.tag, "i/o error");
	if(fid.fd != nil)
		return ref Rmsg.Error(m.tag, "walk on a open fid");

	# Clone if needed
	oqid := fid.qid;
	opath:= fid.path;
	nfid: ref Fid;
	if(m.newfid != m.fid){
		nfid = ref Fid(m.newfid, nil, 0, -1, fid.qid, fid.path); 
		if(addfid(nfid) < 0)
			return ref Rmsg.Error(m.tag, "fid already in use");
		fid = nfid;
	}

	# Walk to m.names
	nqids := len m.names;
	if(nqids == 0)
		return ref Rmsg.Walk(m.tag, array[0] of Qid);
	wpaths := array[nqids] of string;
	wqids := array[nqids] of Qid;
	for(i := 0; i < nqids; i++){
		fid.path = rooted(fid.path, m.names[i]);
		fid.path = cleanname(fid.path);
		if(!isprefix(rootdir, fid.path))
			fid.path = rootdir;
		wpaths[i] = fid.path;
	}
	(ec, d) := stat(fid.path);
	if(ec < 0){
		if(debug)
			fprint(stderr, "walk: stat: %s: %r\n", fid.path);
		e := sprint("%r");
		maybebroken(e);
	}
	if(ec >= 0){	# walk worked. invent everything else.
		for(i = 0; i < nqids - 1; i++){
			q := getqid(wpaths[i]);
			if(q == NOQID)
				q = addqid(wpaths[i]);
			wqids[i] = Qid(q, 0, QTDIR);
		}
		fid.qid = wqids[nqids-1] = fixqid(fid.path, d.qid);
		return ref Rmsg.Walk(m.tag, wqids);
	}
	# Couldn't walk. restore fid and respond
	fid.qid = oqid;
	fid.path = opath;
	for(i = 0; i < nqids; i++){
		(ec, d) = stat(wpaths[i]);
		if(ec < 0){
			e := sprint("%r");
			maybebroken(e);
			if(i == 0){
				if(nfid != nil)
					delfid(nfid);
				return ref Rmsg.Error(m.tag, "file does not exist");
			} else
				return ref Rmsg.Walk(m.tag, wqids[0:i]);
		}
		wqids[i] = fixqid(wpaths[i], d.qid);
	}
	panic("can or can't walk?"); 
	return nil;
}

reqrdproc(fd: ref FD, reqc: chan of ref Tmsg)
{
	m: ref Tmsg;
	do {
		m = Tmsg.read(fd, msize);
		if(m != nil)
			pick mm := m {
			Readerror =>
				fprint(stderr, "mux: %s\n", mm.error);
				m = nil;
			}
		reqc <-= m;
	} while(m != nil);
}

fsreq(req: ref Tmsg) : ref Rmsg
{
	pick m := req {
	Version =>	return fsversion(m);
	Auth =>	return ref Rmsg.Error(m.tag, "no auth required");
	Attach =>	return fsattach(m);
	Flush =>	return ref Rmsg.Flush(m.tag);
	Walk =>	return fswalk(m);
	Open =>	return fsopen(m);
	Create =>	return fscreate(m);
	Read =>	return fsread(m);
	Write =>	return fswrite(m);
	Clunk =>	return fsclunk(m);
	Stat =>	return fsstat(m);
	Remove =>	return fsremove(m);
	Wstat =>	return fswstat(m);
	* =>	panic("bug"); return nil;
	}
}

canretry(req: ref Tmsg): int
{
	r := tagof(req);
	if(r == tagof(Tmsg.Auth) || r == tagof(Tmsg.Read) || r == tagof(Tmsg.Write))
		return 0;
	return 1;
}
	

srvproc(reqc: chan of ref Tmsg, cfd: ref FD)
{
	stderr = sys->fildes(2);
	for(;;){
		req := <-reqc;
		if(req == nil)
			break;
		if(debug)
			fprint(stderr, "<- %s\n", req.text());
		rebind();
		wasbroken := brokenfs;
		rep := fsreq(req);
		if(rep == nil)
			error("nil reply");
		if(!wasbroken && brokenfs){
			# BUG: Here, if we were not lucky and this thing did break,
			# we might call rebind and retry the rpc again, if we see that
			# there's no problem in doing so.
			if(canretry(req)){
				rebind();
				if(!brokenfs)
					rep = fsreq(req);
			}
		}
		if(debug)
			fprint(stderr, "-> %s\n", rep.text());
		b := rep.pack();
		nw := write(cfd, b, len b);
		if(nw != len b){
			fprint(stderr, "write: %r\n");
			break;
		}
	}
	terminate();
}

mux(pidc: chan of int, fd: ref FD)
{
	if(pidc != nil)
		pidc <-= pctl(FORKNS|NEWPGRP|NEWFD, list of {0,1,2,fd.fd});
	else
		pctl(NEWPGRP, nil);
	fd = sys->fildes(fd.fd);
	stderr = sys->fildes(2);
	reqc := chan of ref Tmsg;
	bindrootdir();
	spawn reqrdproc(fd, reqc);
	spawn srvproc(reqc, fd);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	names = checkload(load Names Names->PATH, Names->PATH); 
	dat = checkload(load Muxdat Muxdat->PATH, Muxdat->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("mux [-abcd] [-m mnt] name val [name val]...");
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
		* =>
			usage();
		}
	}
	args = arg->argv();
	argc := len args;
	if(argc == 0 || (argc%2) != 0)
		usage();
	styx->init();
	dat->init(sys, err, names, args);
	if(mnt == nil)
		mux(nil, fildes(0));
	else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("mux: pipe: %r"));
		pidc := chan of int;
		spawn mux(pidc, pfds[0]);
		<-pidc;
		pfds[0] = nil;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("mux: mount: %r"));
	}
}

