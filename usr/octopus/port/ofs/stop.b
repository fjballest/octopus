#
# Translation from styx to op for ofs.
# Either use the Cache or Op to operate on remote files.
#
# semantics:
#	dir (+initial data) fetched/checked upon walk
#	directories fully read.
#	dir hierarchies leading to files/dirs are created (faked) on demand.
#	files read on demand (after data read on first get)
#	creates deferred until first write, but for "mkdirs".
#	writethrough:
#		data pushed for write at 0; and partially filled puts
#	delayed write:
#		data pushed with full puts.
#
# All files with open fids are alive in the cache.
# Op's fds correspond to cached files. This means that a clunk is
# likely to clunk an op fd. Read and Write modes would use different fds.
#
# A coherency lag of N ms can be set. In this case,
# files checked out not more than Nms ago are considered
# up to date. For directories, this is tricky, because we must
# still read directories for which we got just metadata, and not data.
# in particular, directories invented during a walk.
#
# Each close in a file being written signals an end-of-put (clunk)
# in the server. However, this does not make any distinction between different
# client processes updating the same file in the server (which is reasonable, because
# in that case there would be races in any case).
#
# Regarding tags, the client sends its own tags (styx)
# and we invent Op tags as needed.

implement Stop;

include "sys.m";
	sys: Sys;
	fprint, sprint, pctl, millisec, DMDIR, write, nulldir, tokenize, fildes,
	QTDIR, FD, Dir, Qid: import sys;
include "names.m";
	names: Names;
	cleanname: import names;
include "string.m";
	str: String;
	splitstrl: import str;
include "styx.m";
	styx: Styx;
	unpackdir: import styx;
include "styxservers.m";
	Enotfound, Eexists: import Styxservers;
include "op.m";
	OSTAT, NOTAG, NOFD, MAXDATA, OCREATE, ODATA, OMORE, Tmsg, Rmsg: import Op;
include "opmux.m";
	opmux: Opmux;
include "error.m";
	err: Error;
	stderr, panic: import err;
include "stop.m";
include "ofstree.m";
	ofstree: Ofstree;
	Cfile: import ofstree;

# To put a limit on the number of processes that we might spawn
# mainly because of Tputs for huge files.
# This module has Xfids built-in, in the future, it should use xproc(2)
# instead.

Nprocs: con 30;

Xop: adt {
	fun:	ref fn(x: Xop);
	tag:	int;		# styx tag for client; op tag for xproc
	f:	ref Cfile;
	path:	string;
	d:	ref Dir;
	data:	array of byte;
	n:	int;
	o:	big;
	rc:	chan of ref Crep;
};

cfsreqc: chan of (ref Creq, chan of ref Crep);
xcfsreqc: chan of Xop;
xcfsendc: chan of int;
xcfsflushc: chan of (int, int, chan of ref Crep);
donec: chan of ref Cfile;
coherencylag := 0;

maxwaiting := 0;
maxheld := 0;

init(s: Styx, m: Opmux, dir: string, lag: int): string
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	names = load Names Names->PATH;
	str = load String String->PATH;
	opmux = m;
	ofstree = load Ofstree Ofstree->PATH;
	if(sys == nil || names == nil || str == nil || opmux == nil || ofstree == nil)
		return "load failed in cache";
		styx = s;
	coherencylag = lag;
	cfsreqc = chan of (ref Creq, chan of ref Crep);
	xcfsreqc = chan[5] of Xop;
	xcfsendc= chan of int;
	xcfsflushc= chan of (int, int, chan of ref Crep);
	donec = chan[5] of ref Cfile;
	e := ofstree->init(sys, str, styx, err, names, dir);
	ofstree->debug = debug;
	if(e != nil)
		return e;
	spawn cfsproc();
	spawn xcfsproc();
	return nil;
}

term()
{
	cfsreqc <-= (nil, nil);
}

Creq.text(r: self ref Creq): string
{
	s := sprint("t%d q%bx", r.tag, r.qid);
	pick rr := r {
	Dump =>
		s += " dump";
	Remove =>
		s += " remove";
	Stat =>
		s += " stat";
	Sync =>
		s += " sync";
	Validate =>
		s += " validate [" + rr.path + "]";
	Walk1 =>
		s += " walk1 [" + rr.name + "]";
	Readdir =>
		s += sprint(" readdir c%d o%bd", rr.cnt, rr.off);
	Pread =>
		s += sprint(" pread c%d o%bd", rr.cnt, rr.off);
	Pwrite =>
		s += sprint(" pwrite [%3.3s...] c%d o%bd", string rr.data, len rr.data, rr.off);
	Wstat =>
		s += " wstat";
	Create =>
		s += " create [" + rr.d.name + "]";
	Flush =>
		s += sprint(" flush %d", rr.oldtag);
	}
	return s;
}

Crep.text(r: self ref Crep): string
{
	s := "";
	pick rr := r {
	Remove =>
		s += " remove";
	Stat =>
		s += " stat";
		if(rr.d != nil)
			s += sprint(" [%s] q%bx:%d", rr.d.name, rr.d.qid.path, rr.d.qid.vers);
	Sync =>
		s += " sync";
	Validate =>
		s += " validate";
		if(rr.d != nil)
			s += sprint(" [%s] q%bx:%d", rr.d.name, rr.d.qid.path, rr.d.qid.vers);
	Walk1 =>
		s += " walk1";
		if(rr.d != nil)
			s += sprint(" [%s] q%bx:%d", rr.d.name, rr.d.qid.path, rr.d.qid.vers);
	Readdir =>
		s += sprint(" readdir n%d", len rr.sons);
	Pread =>
		s += sprint(" pread [%3.3s...] c%d", string rr.data, len rr.data);
	Pwrite =>
		s += sprint(" pwrite c%d", rr.count);
	Wstat =>
		s += " wstat";
		if(rr.d != nil)
			s += sprint(" [%s] q%bx:%d", rr.d.name, rr.d.qid.path, rr.d.qid.vers);
	Create =>
		s += " create";
		if(rr.d != nil)
			s += sprint(" [%s] q%bx:%d", rr.d.name, rr.d.qid.path, rr.d.qid.vers);
	Flush =>
		s += sprint(" flush");
	}
	if(r.err != nil)
		s += " errstr=" + r.err;
	return s;
}

crepcs: list of chan of ref Crep;
getcrepc(): chan of ref Crep
{
	if(crepcs == nil)
		return chan of ref Crep;
	else {
		c := hd crepcs;
		crepcs = tl crepcs;
		return c;
	}
}
putcrepc(c: chan of ref Crep)
{
	crepcs = c::crepcs;
}

cacherpc(r: ref Creq) : ref Crep
{
	c := getcrepc();
	if(debug)
		fprint(stderr, "<c %d\t%s\n", millisec(), r.text());
	cfsreqc <-= (r, c);
	rep := <-c;
	putcrepc(c);
	if(debug)
		fprint(stderr, "c> %d\tt%d %s\n", millisec(), r.tag, rep.text());
	return rep;
}

dump()
{
	cacherpc(ref Creq.Dump(0, big 0));
}

validate(tag: int, qid: big, name: string): (ref Dir, string)
{
	r := cacherpc(ref Creq.Validate(tag, qid, name));
	pick rr := r {
	Validate =>
		return (rr.d, rr.err);
	}
	panic("validatebug");
	return (nil, nil);
}

create(tag: int, qid: big, d: ref Sys->Dir): (ref Sys->Dir, string)
{
	r := cacherpc(ref Creq.Create(tag, qid, ref *d));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, ""));
		r = cacherpc(ref Creq.Create(tag, qid, ref *d));
	}
	pick rr := r {
	Create =>
		return (rr.d, rr.err);
	}
	panic("createbug");
	return (nil, nil);
}

remove(tag: int, qid: big) : string
{
	r := cacherpc(ref Creq.Remove(tag, qid));
	pick rr := r {
	Remove =>
		return rr.err;
	}
	panic("removebug");
	return nil;
}

walk1(tag: int, qid: big, elem: string): (ref Sys->Dir, string)
{
	r := cacherpc(ref Creq.Walk1(tag, qid, elem));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, elem));
		r = cacherpc(ref Creq.Walk1(tag, qid, elem));
	}
	pick rr := r {
	Walk1 =>
		return (rr.d, rr.err);
	}
	panic("walk1bug");
	return (nil, nil);
}

readdir(tag: int, qid: big, cnt: int, off: int): (list of Sys->Dir, string)
{
	r := cacherpc(ref Creq.Readdir(tag, qid, cnt, big off));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, ""));
		r = cacherpc(ref Creq.Readdir(tag, qid, cnt, big off));
	}
	pick rr := r {
	Readdir =>
		return (rr.sons, rr.err);
	}
	panic("readdirbug");
	return (nil, nil);
}

pread(tag: int, qid: big, cnt: int, off: big): (array of byte, string)
{
	r := cacherpc(ref Creq.Pread(tag, qid, cnt, off));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, ""));
		r = cacherpc(ref Creq.Pread(tag, qid, cnt, off));
	}
	pick rr := r {
	Pread =>
		return (rr.data, rr.err);
	}
	panic("preadbug");
	return (nil, nil);
}

pwrite(tag: int, qid: big, data: array of byte, off: big) : (int, string)
{
	r := cacherpc(ref Creq.Pwrite(tag, qid, data, off));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, ""));
		r = cacherpc(ref Creq.Pwrite(tag, qid, data, off));
	}
	pick rr := r {
	Pwrite =>
		return (rr.count, rr.err);
	}
	panic("pwritebug");
	return (0, nil);
}

stat(tag: int, qid: big): (ref Sys->Dir, string)
{
	r := cacherpc(ref Creq.Stat(tag, qid));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, ""));
		r = cacherpc(ref Creq.Stat(tag, qid));
	}
	pick rr := r {
	Stat =>
		return (rr.d, rr.err);
	}
	panic("statbug");
	return (nil, nil);
}

wstat(tag: int, qid: big, d: ref Sys->Dir): (ref Sys->Dir, string)
{
	r := cacherpc(ref Creq.Wstat(tag, qid, ref *d));
	if(r.err == "invalid"){
		cacherpc(ref Creq.Validate(tag, qid, ""));
		r = cacherpc(ref Creq.Wstat(tag, qid, ref *d));
	}
	pick rr := r {
	Wstat =>
		return (rr.d, rr.err);
	}
	panic("wstatbug");
	return (nil, nil);
}

flush(tag: int, old: int): string
{
	r := cacherpc(ref Creq.Flush(tag, big 0, old));
	pick rr := r {
	Flush =>
		return rr.err;
	}
	panic("flushbug");
	return nil;
}

sync(tag: int, qid: big): string
{
	r := cacherpc(ref Creq.Sync(tag, qid));
	pick rr := r {
	Sync =>
		return rr.err;
	}
	panic("syncbug");
	return nil;
}

opfname(d, n: string) : string
{
	path: string;
	if(n == "" || n == "/")
		path = d;
	else if(d == "/")
		path = n;
	else
		path = d + "/" + n;
	path = cleanname(path);

	return path;
}

Wlist: type list of (ref Cfile, ref Creq, chan of ref Crep);

waitingop(l: Wlist, rf: ref Cfile): (Wlist, ref Creq, chan of ref Crep)
{
	rr: ref Creq;
	rrc: chan of ref Crep;

	rl : Wlist;
	for(; l != nil; l = tl l){
		(f, r, rc) := hd l;
		if(f == rf && rr == nil)
			(rr, rrc) = (r, rc);
		else
			rl = (f, r, rc) :: rl;
	}
	return (rl, rr, rrc);
}

dumpwaiting(l: Wlist)
{
	fprint(stderr, "\tcache: waiting:\n");
	for(; l != nil; l = tl l){
		(f, r, nil) := hd l;
		fprint(stderr, "\t\t%s: %s\n", f.d.name, r.text());
	}
}

# Main cache mux
# Requests are either being processed here, or spawned in auxiliary
# processes speaking op (and going through the opmux),
# or waiting for other requests to clear a file from being busy.

cfsproc()
{
	waiting: Wlist;

	rootd := ref nulldir;
	rootd.name = "/";
	rootd.uid = rootd.gid = rootd.muid = "sys";
	rootd.qid = Qid(big 0, 0, QTDIR);
	root := Cfile.create(nil, rootd);
	if(root == nil)
		panic("cache: can't create root");
	if(debug)
		fprint(stderr, "cache: new: %s\n", root.text());
	readyfile: ref Cfile;
Loop:
	for(;;){
		r: ref Creq;
		rc: chan of ref Crep;
		r = nil; rc = nil;
		# Attend first pending ops on a file that was busy.
		if(len waiting > maxwaiting)
			maxwaiting  = len waiting;
		if(readyfile != nil){
			(waiting, r, rc) = waitingop(waiting, readyfile);
			if(r != nil && debug)
				fprint(stderr, "\tcache: readyop: %s\n", r.text());
		}
		if(debug)
			dumpwaiting(waiting);
		if(r == nil){
			readyfile = nil;
			alt {
			(r, rc) = <-cfsreqc =>
				;
			f := <-donec =>
				f.busy = 0;
				readyfile = f;
				if(debug)
					fprint(stderr, "\tcache: %s ready\n", f.d.name);
				continue Loop;
			}
		}
		if(r == nil){
			if(debug) fprint(stderr, "mcache: stop\n");
			break;
		}
		f := Cfile.find(r.qid);
		if(f != nil && f.d == nil)
			panic(sprint("cache: nil dir for file 16r%bx", r.qid));
		pick rr := r {
		Flush =>
			# If the request was not async, it's already "flushed".
			# But it's the Xproc the one who knows if it was or not.
			xcfsflushc <-= (r.tag, rr.oldtag, rc);
		Validate =>
			if(f == nil){
				rc <-= ref Crep.Validate("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}

			# 1. Create a fake dir hierarchy for all but the last component.
			(nels, els) := tokenize(rr.path, "/");
			wf := f;
			for(i := 0 ; i < nels -1; i++){	# find or create a fake entry
				(wf, nil) = wf.walkorcreate(hd els, nil);
				if(wf != nil && wf.busy){
					if(debug) fprint(stderr, "\tcache: busy\n");
					waiting = (wf, r, rc) :: waiting;
					continue Loop;
				}
				els = tl els;
			}
			f = wf;

			# 2. try to validate the last component.
			# els could be nil (e.g., for "/"), or for a pure clone
			sf: ref Cfile;
			if(els == nil)
				sf = f;
			else {
				if(f == nil)
					panic("mcache validate bug");
				sf = f.walk(hd els);
			}
			# sf is either nil, or points to the file (and maybe sf == f)
			if(sf  != nil && sf.busy){
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (sf, r, rc) :: waiting;
				continue;
			}
			now := millisec();
			# This optimization does not seem to work in some cases
			if(0)
			if(sf == nil && f != sf && f.dirreaded && now - f.time < coherencylag){
				rc <-= ref Crep.Validate("file does not exist", nil);
				continue;
			}
			if(sf != nil && now - sf.time < coherencylag){
				rc <-= ref Crep.Validate(nil, ref *sf.d);
				continue;
			}
			# don't know. Ask the caller for help. Put the file on hold.
			isnew := 0;
			if(sf == nil){
				# BUG: This is a problem. The cache should create the file
				# only when necessary to keep cached data. Otherwise, we
				# create the file here as a directory and it might later be a file,
				# Things are fixed when the cache finds out the problem, but
				# it would be better to make it right from the start.
				(sf, isnew) = f.walkorcreate(hd els, nil);
			}
			if(sf.busy){
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (sf, r, rc) :: waiting;
				continue;
			}
			sf.busy = 1;
			path := sf.getpath();
			xcfsreqc <-= Xop(xgetandvalidate, r.tag, sf, path,
				nil, nil, isnew, big 0, rc);
		Create =>
			if(f == nil){
				rc <-= ref Crep.Create("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			(f,nil) = f.walkorcreate(rr.d.name, rr.d);
			if(f.busy){
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			f.data = array[0] of byte;
			f.created = f.dirtyd = 1;
			if(f.d.qid.qtype&QTDIR){
				f.busy = 1;
				path := f.getpath();
				xcfsreqc <-= Xop(xputandcreate, r.tag, f, path,
					rr.d, nil, 0, big 0, rc);
			} else
				rc <-= ref Crep.Create(nil, ref *f.d);
		Remove =>
			if(f == nil){
				rc <-= ref Crep.Remove("invalid");
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			f.busy = 1;
			path := f.getpath();
			xcfsreqc <-= Xop(xdelandremove, r.tag, f, path,
				nil, nil, 0, big 0, rc);
		Walk1 =>
			if(f == nil){
				rc <-= ref Crep.Walk1("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			f = f.walk(rr.name);
			if(f != nil && f.busy){
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			if(f == nil){
				# if this error ever happens, try to (re)validate this file
				rc <-= ref Crep.Walk1("invalid", nil);
			} else
				rc <-= ref Crep.Walk1(nil, ref *f.d);
		Readdir =>
			if(f == nil){
				rc <-= ref Crep.Readdir("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			rc <-= ref Crep.Readdir(nil, f.children(rr.cnt, int rr.off));
		Pread =>
			if(f == nil){
				rc <-= ref Crep.Pread("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			# we cache prefixes only, and don't believe that files
			# reporting zero length are indeed empty.
			if(rr.off >= f.d.length && f.d.length > big 0)
				rc <-= ref Crep.Pread(nil, array[0] of byte);
			else if(rr.off < big len f.data){
				n := int rr.off + rr.cnt;
				if(n >  len f.data)
					n = len f.data;
				rc <-= ref Crep.Pread(nil, f.data[int rr.off:n]);
			} else if(!(f.d.qid.qtype&QTDIR) && (cdata := f.pread(rr.cnt, rr.off)) != nil)
				rc <-= ref Crep.Pread(nil, cdata);
			else {
				path := f.getpath();
				f.busy = 1;
				xcfsreqc <-= Xop(xgetandread, r.tag, f, path,
					nil, nil, rr.cnt, rr.off, rc);
			}
		Pwrite =>
			# This is write-through (perhaps asynchronously)
			if(f == nil){
				rc <-= ref Crep.Pwrite("invalid", -1);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			if(rr.off <= big len f.data){
				if(int rr.off + len rr.data > MAXCACHED){
					f.data = f.data[0:int rr.off];
				} else {
					off := int rr.off;
					ndata := array[off + len rr.data] of byte;
					ndata[0:] = f.data[0:off];
					ndata[off:] = rr.data;
					f.data = ndata;
					if(f.d.length < big len f.data)
						f.d.length = big len f.data;
				}
			}
			f.pwrite(rr.data, rr.off);
			path := f.getpath();
			f.busy = 1;
			# keep this condition in sync with async in putandwrite()
			l := len f.d.name;
			if((rr.off != big 0 && (l > 4 && (f.d.name[l-4:l] == ".dis" || f.d.name[l-4:l] == ".sbl"))) ||
			   (len rr.data == 8192 && !f.created &&  rr.off != big 0))
				rc <-= ref Crep.Pwrite(nil, len rr.data);
			xcfsreqc <-= Xop(xputandwrite, r.tag, f, path,
				nil, rr.data, 0, rr.off, rc);
		Stat =>
			if(f == nil){
				rc <-= ref Crep.Stat("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			rc <-= ref Crep.Stat(nil, ref *f.d);
		Wstat =>
			if(f == nil){
				rc <-= ref Crep.Wstat("invalid", nil);
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			truncate := (f.d.length != big 0 && rr.d.length == big 0);
			if(truncate){
				f.data = array[0] of byte;
				f.created = 1;			# to truncate it
			}
			f.dirtyd  = 1;
			f.busy = 1;
			path := f.getpath();
			xcfsreqc <-= Xop(xputandwstat, r.tag, f, path,
				rr.d, nil, 0, big 0, rc);
		Sync =>
			if(f == nil){
				rc <-= ref Crep.Sync("invalid");
				continue;
			} else if(f.busy) {
				if(debug) fprint(stderr, "\tcache: busy\n");
				waiting = (f, r, rc) :: waiting;
				continue;
			}
			path := f.getpath();
			f.busy = 1;
			xcfsreqc <-= Xop(xputandsync, r.tag, f, path,
				nil, nil, 0, big 0, rc);
		Dump =>
			root.dump(0, "cfs tab:\n");
			fprint(stderr, "cache: %d max busy, %d max held\n", maxwaiting, maxheld);
			rc <-= ref Crep.Dump(nil);
		}
	}
}

# Op tags. Used by xcfsproc to assign them and by deltag to reuse them.
taggen := 0;

newtag(): int
{
	t := taggen++;
	if(taggen == NOTAG){
		fprint(stderr, "ofs: op tag wrap\n");
		taggen = 0;
	}
	return t;
}

deltag(tags: list of (int, int), otag: int): list of (int, int)
{
	if(otag == NOTAG)
		return tags;
	nl: list of (int, int);
	nl = nil;
	for(; tags != nil; tags = tl tags){
		(tg, otg) := hd tags;
		if(otg != otag)
			nl = (tg, otg)::nl;
	}
	if(len nl == 0)
		taggen = 0;
	else if  (otag == taggen-1)
		taggen = otag;
	return nl;
}

findtag(tags: list of (int, int), tag: int): int
{
	for(; tags != nil; tags = tl tags){
		(tg, otg) := hd tags;
		if(tg == tag)
			return otg;
	}
	return NOTAG;
}

xcfsproc()
{
	pending: list of Xop;
	procs: list of chan of Xop;
	nprocs := 0;
	idlec := chan of (chan of Xop, int);
	tags: list of (int, int);
	tags = nil;
	pending = nil;
	procs = nil;
	for(;;){
		alt {
		(nil, old, rc) := <- xcfsflushc =>
			# see if any proc is using old as tag.
			# Assume it's op rpc is not done and flush it.
			# Should it complete before the flush, the server would
			# receive a flush for an unseen tag (a nop).
			# When the server replies to the flushed request we'll reply to the client.
			otag := findtag(tags, old);
			if(otag != NOTAG)
				opmux->rpc(ref Tmsg.Flush(taggen++, otag));
			rc <-= ref Crep.Flush(nil);
		x := <-xcfsreqc =>
			if(x.fun== nil)
				exit;
			xc: chan of Xop;
			if(procs != nil){
				xc = hd procs;
				procs = tl procs;
			} else if(nprocs < Nprocs) {
				nprocs++;
				xc = chan of Xop;
				spawn xproc(xc, idlec);
			} else
				xc = nil;

			if(xc != nil){
				otag := newtag();
				tags = (x.tag, otag):: tags;
				x.tag = otag;
				xc <-= x;
			} else {
				pending = x :: pending;
				if(len pending > maxheld)
					maxheld = len pending;
				if(debug)
					fprint(stderr, "o/ofs: %d procs, op held\n", nprocs);
			}

		(xc, otag) := <-idlec =>
			tags = deltag(tags, otag);
			if(pending != nil){
				x := hd pending;
				pending = tl pending;
				if(debug)
					fprint(stderr, "o/ofs: held op released\n");
				otag = newtag();
				tags = (x.tag, otag):: tags;
				x.tag = otag;
				xc <-= x;
			} else
				procs = xc::procs;
		}
	}
}

xproc(xc: chan of Xop, idlec: chan of (chan of Xop, int))
{
	for(;;){
		x := <-xc;
		x.fun(x);
		idlec <-= (xc, x.tag);
	}
}

# BUG: Doing a ls -ld on a file that has NOT read permission will make Tget fail
# because we ask for data as well, and oxport would report a permission denied while trying to
# open the file for reading. This must be changed. If OSTAT|ODATA is asked to oxport,
# and only stat could be retrieved, only stat should be reported back, with just OSTAT in the
# reply. Of course, this means that there are problems reading file data, and the client may issue
# a Tget(ODATA) should it want to learn the cause (or probably assume just a permission denied).
get(tag: int, path: string, fd: int, mode: int, cnt: int, off: big): (int, ref Dir, array of byte, string)
{
	data := array[0] of byte;
	d : ref Dir;

	nm := 1;
	if(mode&ODATA){
		while(nm < MAXNMSGS && off + big (Op->MAXDATA*nm) < big MAXCACHED)
			nm++;
		if(nm > 1 || off < big MAXCACHED)
			cnt = MAXDATA;
	}
	req := ref Tmsg.Get(tag, path, fd, mode, nm, off, cnt);
	repc := opmux->rpc(req);
	nmsgs := nm;
	d = nil;
	for(;;){
		rep := <- repc;
		pick r := rep {
		Error =>
			return (Op->NOFD, nil, nil, r.ename);
		Get =>
			if((r.mode&OSTAT) != 0){
				d = ref r.stat;
				if((d.qid.qtype&QTDIR) != 0)
					nmsgs = 0;
			}
			if((r.mode &ODATA) != 0){
				ndata := array[len data + len r.data] of byte;
				ndata[0:] = data;
				ndata[len data:] = r.data;
				data = ndata;
			}
			if(--nmsgs == 0 || (r.mode&OMORE) == 0)	# last message
				return(r.fd, d, data, nil);
		* =>
			panic("get0bug");
		}
	}
	panic("get0bug");
	return (Op->NOFD, nil, nil, "bug");
}

xgetandvalidate(x: Xop)
{
	getandvalidate(x.tag, x.f, x.path, x.n, x.rc);
}
getandvalidate(tag: int, f: ref Cfile, path: string, isnew: int, rc: chan of ref Crep)
{
	(fd, d, data, e) := get(tag, path, f.oprdfd, OSTAT|ODATA|OMORE, MAXDATA, big 0);
	f.oprdfd = fd;
	if(e != nil || d == nil){
		f.remove();
		rc <-= ref Crep.Validate(e, nil);
	}
	else {
		if(isnew)
			f.serverqid = d.qid;
		else {
			if(f.serverqid.path != d.qid.path || f.serverqid.vers != d.qid.vers)
			if(!f.created)
				f.data = array[0] of byte;
			f.serverqid = d.qid;
		}
		f.wstat(d);
		if(d.qid.qtype&QTDIR){
			f.dirreaded = 1;
			f.updatedirdata(data);
		} else {
			f.pwrite(data, big 0);
			if(!f.dirtyd && !f.created)
				f.data = data;
		}
		f.d.qid.vers = d.qid.vers;
		f.time = millisec();
		rc <-= ref Crep.Validate(nil, ref *f.d);
	}
	donec <-= f;
}

xgetandread(x: Xop)
{
	getandread(x.tag, x.f, x.path, x.n, x.o, x.rc);
}
getandread(tag: int, f: ref Cfile, path: string, cnt: int, off: big, rc: chan of ref Crep)
{
	(fd, nil, data, e) := get(tag, path, f.oprdfd, ODATA|OMORE, cnt, off);
	f.oprdfd = fd;
	if(e != nil){
		# fsremove(fstab, f.d.qid.path); should?
		rc <-= ref Crep.Pread(e, nil);
	} else {
		if(f.d.length != big 0){		# files with zero-length are probably streams.
			f.pwrite(data, off);	# do not cache.
			odata := f.data;
			o := int off;
			if(o <= len odata){
				if(o + len data > MAXCACHED)
					f.data = odata[0:o];
				else {
					ndata := array[o + len data] of byte;
					ndata[0:] = odata[0:o];
					ndata[o:] = data;
					f.data = ndata;
					if(f.d.length < big len f.data)
						f.d.length = big len f.data;
				}
			}
		}
		f.time = millisec();
		rc <-= ref Crep.Pread(nil, data);
	}
	donec <-= f;
}

# BUG: Too many args; put does it all.
put(tag: int, path: string, opfd: int, d: ref Dir, data: array of byte, off: big, mkit, more: int) : (int, int, int, string)
{
	if(d == nil && data == nil && opfd == Op->NOFD)
		return (NOFD, 0, 0, nil);
	flag := 0;
	if(d != nil)
		flag |= OSTAT;
	if(data != nil && (!mkit || (d.qid.qtype&QTDIR) == 0))
		flag |= ODATA;
	if(mkit)
		flag |= OCREATE;
	if(more)
		flag |= OMORE;
	if(data == nil)
		data = array[0] of byte;
	tot := 0;
	rfd := NOFD;
	mtime := 0;
	for(;;){
		nw := len data[tot:];
		if(nw > MAXDATA)
			nw = MAXDATA;
		if(d == nil)
			d = ref nulldir;
		rc := opmux->rpc(ref Tmsg.Put(tag, path, opfd, flag, *d, off, data[tot:tot+nw]));
		vers := 0;
		r := <- rc;
		pick rr := r {
		Put =>
			if(rr.count != nw)
				return (NOFD, 0, 0, "short write");
			vers = rr.qid.vers;
			rfd = rr.fd;
			mtime = rr.mtime;
		Error =>
			return (NOFD, 0, 0, rr.ename);
		* =>
			panic("putbug");
		}
		tot += nw;
		if(tot == len data)
			return (rfd, vers, mtime, nil);
		flag &= ~(OSTAT|OCREATE);
	}
	panic("putbug");
	return (NOFD, 0, 0, "putbug");
}

xputandcreate(x: Xop)
{
	putandcreate(x.tag, x.f, x.path, x.d, x.rc);
}
putandcreate(tag: int, f: ref Cfile, path: string, d: ref Dir, rc: chan of ref Crep)
{
	(fd, vers, mtime, e) := put(tag, path, f.opwrfd, f.d, nil, big 0, 1, 1);
	f.opwrfd = fd;
	if(e != nil){
		f.remove();
		rc <-= ref Crep.Create(e, nil);
	} else {
		f.created = f.dirtyd = 0;
		f.wstat(d);
		if(vers != 0 || mtime != 0){
			f.serverqid.vers = vers;
			f.d.qid.vers = vers;
			f.d.mtime = mtime;
		}
		f.time = millisec();
		rc <-= ref Crep.Create(nil, ref *f.d);
	}
	donec <-= f;
}

xputandwrite(x: Xop)
{
	putandwrite(x.tag, x.f, x.path, x.data, x.o, x.rc);
}
putandwrite(tag: int, f: ref Cfile, path: string, data: array of byte, off: big, rc: chan of ref Crep)
{
	async := (len data == 8192 && !f.created &&  off != big 0); #  (off % big (4*8192)) != big 0);
	l := len f.d.name;
	if(off != big 0 && (l > 4 && (f.d.name[l-4:l] == ".dis" || f.d.name[l-4:l] == ".sbl")))
		async = 1;
	d: ref Dir;
	if(f.dirtyd)
		d = f.d;
	f.dirtyd = 0;
	mkit := f.created;
	f.created = 0;
	if(async)
		donec <-= f;
	(fd, vers, mtime, e) := put(tag, path, f.opwrfd, d, data, off, mkit, 1);
	f.opwrfd = fd;
	if(e != nil){
		f.remove();
		if(!async)
			rc <-= ref Crep.Pwrite(e, len data);
		else
			fprint(stderr, "\n*** ofs: delayed write error ***\n\n");
	} else {
		if(!async){
			f.serverqid.vers = vers;
			f.d.qid.vers = vers;
			f.d.mtime= mtime;
			f.time = millisec();
			rc <-= ref Crep.Pwrite(nil, len data);
		} else {
			# Race, but safer this way.
			f.d.qid.vers = vers;
			if(mtime)
				f.d.mtime = mtime;
		}
	}
	if(!async)
		donec <-= f;
}

xputandwstat(x: Xop)
{
	putandwstat(x.tag, x.f, x.path, x.d, x.rc);
}
putandwstat(tag: int, f: ref Cfile, path: string, d: ref Dir, rc: chan of ref Crep)
{
	mkit := f.created;
	f.created = 0;
	f.dirtyd = 0;
	(fd, vers, mtime, e) := put(tag, path, f.opwrfd, d, nil, big 0, mkit, 1);
	f.opwrfd = fd;
	if(e != nil){
		f.remove();
		rc <-= ref Crep.Wstat(e, nil);
	} else {
		f.serverqid.vers = vers;
		f.wstat(d);
		f.d.mtime = mtime;
		f.time = millisec();
		rc <-= ref Crep.Wstat(nil, ref *f.d);
	}
	donec <-= f;
}

xputandsync(x: Xop)
{
	putandsync(x.tag, x.f, x.path, x.rc);
}
putandsync(tag: int, f: ref Cfile, path: string, rc: chan of ref Crep)
{
	mkit := f.created;
	f.created = 0;
	d: ref Dir;
	if(f.dirtyd)
		d = ref *f.d;
	f.dirtyd = 0;
	f.oldname = nil;
	f.fsfd = nil;
	rc <-= ref Crep.Sync(nil);
	(fd, vers, mtime, e) := put(tag, path, f.opwrfd, d, nil, big 0, mkit, 0);
	f.opwrfd = fd;
	if(f.oprdfd != NOFD){
		(fd, nil, nil, nil) = get(tag, path, f.oprdfd, OSTAT, 0, big 0);
		f.oprdfd = fd;
	}
	if(e != nil)
		f.remove();
	else {
		f.serverqid.vers = vers;
		if(vers != 0)
			f.d.qid.vers = vers;
		if(mtime != 0)
			f.d.mtime  = mtime;
		f.time = millisec();
	}
	donec <-= f;
}

xdelandremove(x: Xop)
{
	delandremove(x.tag, x.f, x.path, x.rc);
}
delandremove(tag: int, f: ref Cfile, path: string, rc: chan of ref Crep)
{
	oprc := opmux->rpc(ref Tmsg.Remove(2*tag, path));
	opr := <-oprc;
	e: string;
	pick oprr := opr {
	Remove =>
		f.remove();
	Error =>
		e = oprr.ename;
	}
	rc <-= ref Crep.Remove(e);
	if(f.oprdfd != NOFD){
		(fd, nil, nil, nil) := get(tag, path, f.oprdfd, OSTAT, 0, big 0);
		f.oprdfd = fd;
	}
	if(f.opwrfd != NOFD){
		(fd, nil, nil, nil) := put(tag, path, f.opwrfd, nil, nil, big 0, 0, 0);
		f.opwrfd = fd;
	}
	donec <-= f;
}
