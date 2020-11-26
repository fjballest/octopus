#
# Event ports. used by o/mero among other things
# Events are strings posted by a single write to "/post".
# To listen for events, create a file and write a regex(2) on it.
# any event posted is matched against the regex, and served as a
# reply to read (offset ignored) if it matches.

implement Ports;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, DMEXCL, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
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
include "daytime.m";
	daytime: Daytime;
	now: import daytime;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "tbl.m";
	tbl: Tbl;
	Table: import tbl;
include "string.m";
	str: String;
	splitl, splitr: import str;
include "env.m";
	env: Env;
	getenv: import env;
include "regex.m";
	regex: Regex;
	Re: import regex;
include "io.m";
	io: Io;
	readdev: import io;

Ports: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Nevs:	con 128;	# max nb. of buffered events in queue. We drop events when full.
Tmout:	con 60;	# after so many seconds of dropping events the file is removed.

File: adt {
	path:	big;
	name:	string;
	evq:	array of string;
	evhd:	int;
	evtl:	int;
	data:	array of byte;
	re:	Re;
	req:	ref Tmsg.Read;
	orclose:	int;
	multi:	int;
	atime:	int;

	new:	fn(q: big, name: string, n: int, orclose: int): ref File;
	read:	fn(f: self ref File, m: ref Tmsg.Read);
	post:	fn(f: self ref File, s: string): int;
	abort:	fn(f: self ref File);
	flush:	fn(tag: int);
};

files: ref Table[ref File];	# indexed by qid.

Qroot, Qpost, Qrecv: con big iota;
qgen:= Qrecv;
debug := 0;
user: string;
nevs := Nevs;
unsent: ref File;
srv: ref Styxserver;

File.new(q: big, name: string, n: int, orclose: int): ref File
{
	return ref File(q, name, array[n] of string, 0, 0, nil, nil, nil, orclose, 0, now());
}

File.abort(f: self ref File)
{
	if(f.req != nil)
		srv.reply(ref Rmsg.Error(f.req.tag, "file was removed"));
	f.req = nil;
	f.data = nil;
}

File.flush(tag: int)
{
	for(i := 0; i < len files.items; i++)
		for(l := files.items[i]; l != nil; l = tl l){
			(nil, f) := hd l;
			if(f.req != nil && f.req.tag == tag){
				srv.reply(ref Rmsg.Error(f.req.tag, "flushed"));
				f.req = nil;
				f.data = nil;
				return;
			}
		}
}

nxt(i: int): int
{
	return (i+1) % nevs;
}

File.read(f: self ref File, m: ref Tmsg.Read)
{
	f.atime = now();
	if(f.req != nil){
		srv.reply(ref Rmsg.Error(m.tag, "concurrent read"));
		return;
	}
	m.offset = big 0;
	if(f.data == nil && f.evq[f.evhd] != nil){
		data := "";
		tot := 0;
		do {
			tot += len array of byte f.evq[f.evhd];
			if(tot > m.count)
				break;
			data += f.evq[f.evhd];
			f.evq[f.evhd] = nil;
			f.evhd = nxt(f.evhd);
		} while(f.multi && f.evq[f.evhd] != nil);
		f.data = array of byte data;
		data = nil;
	} 
	if(f.data != nil){
		r := readbytes(m, f.data);
		f.data = f.data[len r.data:];
		if(len f.data == 0)
			f.data = nil;
		srv.reply(r);
	} else 
		f.req = m;
}

File.post(f: self ref File, ev: string): int
{
	if(f.re == nil)	# not programmed
		return 0;
	r := regex->execute(f.re, ev);
	if(r == nil)
		return 0;	# no match
	if(f.req != nil){
		srv.reply(readstr(f.req, ev));
		f.req = nil;
	} else {
		f.evq[f.evtl] = ev;
		f.evtl = nxt(f.evtl);
		if(f.evtl == f.evhd){
			f.evhd = nxt(f.evhd);	# event lost
			if(now() - f.atime > Tmout)
				return -1;
		}
	}
	return 1;
}

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

eventwrite(tree: ref Tree, m: ref Tmsg.Write, fid: ref Fid): ref Rmsg
{
	msg := "";
	if(fid.data != nil){
		msg += string fid.data;
		fid.data = nil;
	}
	msg += string m.data;
	while(len msg > 0){
		(ctl, rmsg) := splitl(msg, "\n");
		if(len rmsg == 0){
			# partial control request. save.
			fid.data = array of byte ctl;
			break;
		}
		ctl += "\n";
		msg = rmsg[1:];
		oldl : list of ref File;
		posted := 0;
		for(i := 0; i < len files.items; i++)
			for(l := files.items[i]; l != nil; l = tl l){
				f := (hd l).t1;
				if(f != unsent){
					pc := f.post(ctl);
					if(pc < 0)
						oldl = f :: oldl;
					posted |= pc;
				}
			}
		if(!posted && unsent != nil)
			unsent.post(msg);
		for(; oldl != nil; oldl = tl oldl){
			f := hd oldl;
			tree.remove(f.path);
			files.del(int f.path);
		}
	}
	return ref Rmsg.Write(m.tag, len m.data);
}

fsreq(srv: ref Styxserver, tree: ref Tree, req: ref Tmsg) : ref Rmsg
{
	pick m := req {
	Create =>
		(fid, mode, d, e) := srv.cancreate(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag,  e);
		if(mode&DMDIR)
			return ref Rmsg.Error(m.tag, "can't create directories");
		if(d.name == "post")
			return ref Rmsg.Error(m.tag, Eexists);
		f := File.new(++qgen, d.name, nevs, (mode&ORCLOSE));
		d.qid = Qid(qgen, 0, 0);
		d.atime = d.mtime = now();
		d.mode |= DMEXCL;
		e = tree.create(Qroot, *d);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		fid.open(mode, d.qid);
		files.add(int fid.path, f);
		if(d.name == "unsent"){
			unsent = f;
			(f.re, nil) = regex->compile(".*", 0);
		}
		return ref Rmsg.Create(m.tag, d.qid, srv.iounit());
	Remove =>
		(fid, nil, e) := srv.canremove(m);
		srv.delfid(fid);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.path == Qpost)
			return ref Rmsg.Error(m.tag, "permission denied");
		e = tree.remove(fid.path);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		f := files.del(int fid.path);
		if(f != nil){
			f.abort();
			if(f == unsent)
				unsent = nil;
		}
		return ref Rmsg.Remove(m.tag);
	Read =>
		(fid, e) := srv.canread(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.qtype&QTDIR){
			srv.default(req);
			return nil;
		}
		if(fid.path < Qrecv)
			panic("reading from the wrong file");
		f := files.find(int fid.path);
		if(f == nil)
			return ref Rmsg.Error(m.tag, Enotfound);
		f.read(m);
	Write =>
		(fid, e) := srv.canwrite(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.path == Qpost)
			return eventwrite(tree, m, fid);
		else {
			f := files.find(int fid.path);
			if(f == nil)
				return ref Rmsg.Error(m.tag, Enotfound);
			s := string m.data;
			if(s == "multi" || s == "multi\n")
				f.multi = 1;
			else {
				(f.re, e) = regex->compile(string m.data, 0);
				if(e != nil)
					return ref Rmsg.Error(m.tag, e);
			}
			return ref Rmsg.Write(m.tag, len m.data);
		}
	Clunk =>
		fid := srv.getfid(m.fid);
		if(fid == nil)
			return ref Rmsg.Error(m.tag, "bad fid");
		if(fid.path >= Qpost){
			f := files.find(int fid.path);
			if(f != nil && f.orclose){
				f.abort();
				tree.remove(fid.path);
				files.del(int fid.path);
			}
		}
		srv.delfid(fid);
		return ref Rmsg.Clunk(m.tag);
	Flush =>
		File.flush(m.oldtag);
		return ref Rmsg.Flush(m.tag);
	}
	return nil;
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
	stderr = fildes(2);				# lost by pctl
	(tree, navc) := nametree->start();
	nav := Navigator.new(navc);
	(reqc, s) := Styxserver.new(fd, nav, Qroot);
	srv = s;
	tree.create(Qroot, newdir(".", DMDIR|8r775, Qroot));
	tree.create(Qroot, newdir("post", 8r220, Qpost));
	nullfile: ref File;
	files = Table[ref File].new(103, nullfile);
	for(;;) {
		req := <-reqc;
		if(req == nil)
			break;
		rep := fsreq(srv, tree, req);
		if(rep == nil) {
			if(tagof(req) != tagof(Tmsg.Read))
				# read replies are async (events)
				srv.default(req);
		} else
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
	str = checkload(load String String->PATH, String->PATH);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxs = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	nametree = checkload(load Nametree Nametree->PATH, Nametree->PATH);
	nametree->init();
 	daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	tbl = checkload(load Tbl Tbl->PATH, Tbl->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	regex = checkload(load Regex Regex->PATH, Regex->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("o/ports [-abcd] [-q n] [-m mnt]");
	mnt := "/mnt/ports";
	flag := MREPL|MCREATE;
	while((opt := arg->opt()) != 0) {
		case opt{
		'b' =>
			flag = MBEFORE;
		'a' =>
			flag = MAFTER;
		'c' =>
			flag |= MCREATE;
		'i' =>
			mnt = nil;
		'm' =>
			mnt = arg->earg();
		'd' =>
			debug = 1;
			styxs->traceset(1);
		'q' =>
			nevs = int arg->earg();
			nevs ++;
			if(nevs < 3)
				nevs = 3;
			if(nevs > 10000)
				nevs = 10000;
		* =>
			usage();
		}
	}
	args = arg->argv();
	if(len args != 0)
		usage();
	if(mnt == nil)
		fs(nil, fildes(0));
	else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("o/ports: pipe: %r"));
		pidc := chan of int;
		spawn fs(pidc, pfds[0]);
		<-pidc;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("o/ports: mount: %r"));
		pfds[0] = nil;
	}
}
