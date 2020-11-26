implement Cache;

# Cache handling for Nop import.
#
# This module keeps the logic for the cache. The file tree is kept
# in tree.b.
# Procedures called by client processes may be kept
# blocked while the file is busy and/or while speaking Nop.
# They send requests to the cache, and speak Nop
# when the file was "notcached" or  "invalid" and also when
# the request modifies the file, to keep the server up to date.

# The Styx Fid keeps track of the Nop fd and/or the cache fd
# used to implement the styx file descriptor.

# Invalid entries, open (because OTRUNC), create, write, and wstat keep
# the file busy until a Done request is issued.
# Updates sent to the cache not resulting from a busy file should use
# ONONE as the lease; other updates should use OREAD/OWRITE depending
# on the lease implied by the request made to the server.

# Requests on busy files are deferred but take priority over external requests.
# Other errors are actual errors.

include "sys.m";
	sys: Sys;
	fprint, mount, pipe, fildes, FD, MCREATE, sprint,
	MREPL, NEWPGRP, FORKNS, Connection, NEWFD,
	open, pctl, dial, OREAD, ORDWR, OWRITE: import sys;
include "nop.m";
	nop: Nop;
include "error.m";
	err: Error;
	panic, checkload, stderr, error, kill: import err;
include "blks.m";
	blks: Blks;
	Blk: import Blks;
include "tree.m";
	tree: Tree;
	Ctree, Cfile: import tree;
include "lists.m";
	lists: Lists;
	append: import lists;
include "nopmux.m";
	nopmux: Nopmux;
	All, get: import nopmux;

include "cache.m";

reqc: chan of ref Creq;
rootqid: big;

Einval: con "invalid";
Enotcached: con "notcached";

init(s: Sys, l: Lists, e: Err, n: Nop, b: Blks, t: Tree, m: Nopmux)
{
	sys = s;
	err = e;
	nop = n;
	blks = b;
	tree = t;
	lists = l;
	nopmux = m;
}

attach(fd: ref Sys->FD, cdir: string): string
{
	rootqid := opmux->attach();
	e := tree->attach(rootqid, cdir);
	if(e != nil)
		return e;
	reqc = chan of ref Creq;
	spawn invalproc();
	spawn cacheproc();
	return nil;
}

root(): big
{
	return rootqid;
}

# Cache procedures.
#	op():	op made the caller process.
#	cop():	the part of op made by the cache.

cacheop(req: ref Creq): ref Crep
{
	rc := chan of ref Crep;
	req.rc = rc;
	reqc <-= req;
	return <-rc;
}

children(q: big): array of ref Dir
{
	rep := cacheop(ref Creq.Children(q, nil));
	dirs:= array[0] of ref Dir;
	case rep.err {
	Einval or Enotcached =>
		(nil, d, data, err) := get(rep.cf.path, NOFD, ONONE, All, big 0);
		# to avoid races we supply the data ourselves, now that it is
		# valid.
		if(err == nil){
			cf.dirwrite(data);
			dirs = cf.children();
		}
		reqc <-= ref Creq.Udate(q, nil, d, nil, big 0, err, OREAD);
	* =>
		dirs = rep.dirs;
	}
	return dirs;
}

cchildren(r: ref Creq.Chilren, cf: ref Cfile)
{
	(cf, err) := reqfile(req, 0, 0);
	dirs := cf.children();
	if(!cf.dirreaded){
		cf.busy++;
		r.rc  <-= ref Crep.Error("invalid", cf);
	} else
		r.rc <-= ref Crep.Children(nil, cf, dirs);
}

parent(q: big): ref Dir
{
	rep := cacheop(ref Creq.Parent(q, nil));
	if(rep.err != nil)
		panic("cache: parent: " + rep.err);
	return rep.dir;
}

cparent(r: ref Creq.Parent, cf: ref Cfile)
{
	pf := Cfile.find(cf.parentqid, 0);
	r.rc <-= ref Crep.Parent(nil, cf, ref *pf.d);
}

stat(q: big): (ref Dir, string)
{
	d: ref  Dir;
	err: string;
	rep := cacheop(ref Creq.Stat(q, nil));
	case rep.err {
	Enotcached =>
		(nil, d, nil, err) = get(rep.cf.path, NOFD, ONONE, 0, big 0);
	Einval =>
		data: array of byte;
		(nil, d, data, err) = get(rep.cf.path, NOFD, ONONE, All, big 0);
		reqc <-= ref Creq.Update(q, nil, d, data, big 0, err, OREAD);
	"" =>
		pick r := rep {Stat => d = r.dir; }
	* =>
		err = rep.err;
	}
	return (d, err);
}

cstat(r: ref Creq.Stat, cf: ref Cfile)
{
	r.rc <-= ref Crep.Stat(nil, cf, ref *cf.d);
}

walk(q: big, els: array of string, fetch: int): (ref Dir, string)
{
	d: ref Dir;
	err: string;
	rep := cacheop(ref Creq.Walk(q, nil, els, fetch));
	case rep.err {
	Enotcached =>
		q = rep.cf.d.qid.path;
		(nil, d, nil, err) = get(rep.cf.path, NOFD, ONONE, 0, big 0);
		reqc <-= Creq.Update(q, nil, d, nil, big 0, err, ONONE);
	Einval =>
		data: array of byte;
		q = rep.cf.d.qid.path;
		(nil, d, data, err) = get(rep.cf.path, NOFD, ONONE, All, big 0);
		reqc <-= ref Creq.Update(q, nil, d, data, big 0, err, OREAD);
	"" =>
		pick r := rep {Walk => d = r.dir; }
	* =>
		err = rep.err;
	}
	return (d, err);
}

cwalk(r: ref  Creq.Walk, cf: ref Cfile)
{
	nf: ref Cfile;
	lf := cf;
	for(i := 0; i < len r.els; i++){
		if((lf.d.qid.qtype&QTDIR) == 0){
			r.rc <-= ref Crep.Error(Enotdir, lf);
			return;
		}
		nf = lf.walk(r.els[i]);
		if(nf == nil)
			break;
		lf = nf;
	}
	if(nf == nil)
		if((lf.flags&Clease) != ONONE && lf.flags&Cread || r.fetch == 0){
			r.rc <-= ref Crep.Error(Enotfound, lf);
			return;
		} else {
			path := cf.path;
			for(i = 0; i < len r.els; i++)
				path += "/" + r.els[i];
			nf = Cfile.orphan(path);
			if(notcached(lf.d) == 0)
				nf.d.qid.qtype |= QTCACHE;
		}
	if(nf.flags&Cbusy)
		nf.reqs = append(nf.reqs, r);
	else if((nf.flags&Clease) == ONONE){
		nf.flags |= Cbusy;
		r.rc <-= ref Crep.Error(Einval, nf);
	} else if(notcached(nf.d))
		r.rc <-= ref Crep.Error(Enotcached, nf);
	else
		r.rc <-= ref Crep.Walk(nil, nf, ref *nf.d);
}

create(q: big, fid: ref Ssrv->Fid, d: ref Dir, mode: int): (ref Dir, string)
{
	d: ref Dir;
	err: string;
	omode := mode&3;
	if(mode&ORCLOSE)
		omode |= OREMOVEC;
	omode |= OCREATE;
	rep := cacheop(ref Creq.Create(q, nil, fid, d));
	a:= array[0] of byte;
	case rep.err {
	Enotcached =>
		q = rep.cf.d.qid.path;
		(fid.ofd, d, err) = put(rep.cf.path, NOFD, omode, d, a, big 0, 0);
		reqc <-= ref Creq.Update(q, nil, d, nil, big 0, err, ONONE);
	Einval =>
		q := rep.cf.d.qid.path;
		(fid.ofd, d, err) = put(rep.cf.path, NOFD, omode, d, a, big 0, 0);
		reqc <-= ref Creq.Update(q, nil, d, nil, big 0, err, OWRITE);
	"" =>
		pick r := rep {Create => d = r.dir; }
	* =>
		err = rep.err;
	}
	return (d, err);
}

ccreate(r: ref Creq.Create, cf: ref Cfile)
{
	err: string;
	nf := cf.walk(r.d.name);
	if(nf == nil){
		nf = Cfile.orphan(cf.path + "/" + r.d.name);
		if(notcached(cf.d) == 0)
			nf.d.qid.qtype |= QTCACHE;
		if(r.dir.mode&DMDIR){
			nf.d.mode |= DMDIR;
			nf.d.qid.qtype |= QTDIR;
		}
	}
	if(notcached(cf.d) || notcached(nf.d))
		err = Enotcached;
	else if((cf.flags&Clease) != OWRITE || (nf.flags&Clease) != OWRITE){
		nf.flags |= Cbusy;
		err = Einval;
	} else if(nf.qid.qtype&QTDIR && (r.dir.mode&DMDIR) == 0)
		err = Eisdir;
	else if((nf.qid.qtype&QTDIR) == 0 && r.dir.mode&DMDIR)
		err = Enotdir;
	else {
		r.d.length = big 0;
		nf.wstat(r.d);
		nf.flags |= Ccreated|Cdirtyd|Cdata;
		cf.nawrites = 0;
	}
	r.rc <-= ref Crep.Create(err, nf, ref *nf.d);
}

open(q: big, fid: ref Ssrv->Fid, mode: int): (ref Dir, string)
{
	d: ref Dir;
	err: string;
	a: array of byte;
	rep := cacheop(ref Creq.Open(q, nil, fid, mode, nil));
	lmode := omode := mode&OMODE;
	omode |= mode&(OTRUNC|ORCLOSE);
	if(lmode != OREAD)
		lmode = OWRITE;
	case rep.err {
	Enotcached  =>
		cnt := 0;
		if(rep.cf.d.qtype&QTDIR)
			cnt = All;
		(fid.ofd, d, a, err) = get(rep.cf.path, NOFD, omode, cnt, big 0);
		if(rep.cf.d.qtype&QTDIR)
			reqc <-= Creq.Update(q,nil,d,a,big 0,err,ONONE);
	Einval =>
		path := rep.cf.path;
		if((mode&OMODE) == OREAD)
			(fid.ofd, d, a, err) = get(path,NOFD,omode,All,big 0);
		else {
			d = rep.cf.d;
			(fid.ofd, d, err) = put(path,NOFD,omode,d,a,big 0,0);
		}
		reqc <-= ref Creq.Update(q, nil, d, a, big 0, err, lmode);
	"" =>
		pick r := rep {Open => d = r.dir; }
	* =>
		err = rep.err;
	}
	return (d, err);
}

copen(r: ref  Creq.Open, cf: ref Cfile)
{
	err: string;
	if(r.mode != OREAD && (cf.flags&Clease) == OREAD){
		cf.flags  |= Cbusy;
		err =Einval;
		if(r.mode&OTRUNC)
			r.fid.nawrites = 1;
	} else if(cf.d.qid.qtype&QTDIR && mode != OREAD)
		err =Eperm;
	else if(!openok(r.fid.uname, r.mode, cf.d.mode, cf.d.uid, cf.d.gid))
		err =Eperm;
	else if(r.mode&OTRUNC){
		d := nulldir;
		d.length = big 0;
		cf.wstat(d);
		cf.nawrites = 0;
		cf.flags |= Ccreated|Cdirtyd|Cdata;
	}
	r.rc <-= ref Crep.Open(err, cf, ref *cf.d);
}

readbytes(a: array of byte, cnt: int, off: big): array of byte
{
	if(off >= len a)
		return array[0] of byte;
	a = a[int off:];
	if(len a > cnt)
		a=a[0:cnt];
	return a;
}

read(q: big, fid: ref Ssrv->Fid, cnt: int, off: big): (array of byte, string)
{
	d: ref Dir;
	a: array of byte;
	err: string;
	rep := cacheop(ref Creq.Read(q, nil, a, off);
	case rep.err {
	Enotcached =>
		(fid.ofd, d, a, err) = get(rep.cf.path, fid.ofd, ONONE, cnt, off);
		reqc <-= Creq.Update(q, nil, d, nil, big 0, err, ONONE);
	Einval =>
		(fid.ofd, d, a, err) = get(rep.cf.path, fid.ofd, ONONE, All, big 0);
		reqc <-= Creq.Update(q, nil, d, a, off, err, OREAD);
		a = readbytes(a, cnt, off);
	"" =>
		pick r := rep { Read=> a = rep.data; }
	* =>
		err = rep.err;
	}
	return (a, err);
}

cread(r: ref Creq.Read, cf: ref Cfile)
{
	if((cf.flags&Cdata) == 0){
		cf.flags |= Cbusy;
		r.rc <-= ref Crep.Error(Einval, cf);
	} else {
		data := array[r.cnt] of byte;
		if(cf.read(data, r.off) < 0)
			r.rc <-= ref Crep.Error(Enotcached, cf);
		else
			r.rc <-= ref Crep.Read(nil, cf, data);
	}
}

cfchanges(f: ref Cfile): (int, ref Dir)
{
	m := 0;
	d: ref Dir;
	if(f.flags&Ccreated)
		m |= OCREATE;
	if(f.flags&Cdirtyd)
		d = h.dir;
	f.flags &= ~(Created|Cdirtyd);
	return (m, d);
}

# Could be clever in write and coallesce multiple async writes if they are
# sequential and not too big.
write(q: big, fid: ref Ssrv->Fid, a: array of byte, off: big): (int, string)
{
	err: string;
	nr := len a;
	rep := cacheop(ref Creq.Write(q, nil, a, off);
	case rep.err {
	Enotcached or Einval =>
		(m, d) := cfchanges(rep.cf);
		(fid.ofd, d, err) = put(rep.cf.path, fid.ofd, m|ONONE, d, a, off, 0);
		lmode = ONONE;
		if(rep.err == Einval)
			lmode = OWRITE;
		else
			a = nil;
		reqc <-= Creq.Update(q, nil, d, a, off, err, lmode);
	"" =>
		(m, d) := cfchanges(rep.cf);
		async := cf.nawrites < 1 * 1024 * 1024; 
		put(rep.cf.path, fid.ofd, m|ONONE, d, a, off, async);
		if(async)
			cf.nawrites += len a;
		else
			cf.nawrites = 0;
		reqc <-= ref Creq.Done(q, nil);
	* =>
		err = rep.err;
	}
	if(err != nil)
		nr = -1;
	return (nr, err);
}

cwrite(r: ref Creq.Write, cf: ref Cfile)
{
	if((cf.flags&Clease) != OWRITE){
		cf.flags |= Cbusy;
		r.rc <-= ref Crep.Error(Einval, cf);
	} else {
		nw := cf.write(r.data, r.off);
		cf.flags |= Cbusy;
		if(nw < len data)
			r.rc <-= ref Crep.Error(Enotcached, cf);
		else
			r.rc <-= ref Crep.Write(nil, cf, nw);
	}
}

clunk(q: big, fid: ref Ssrv->Fid)
{
	rep := cacheop(ref Creq.Clunk(q, nil, fid));
	cf.fd = nil;
	(m, d) := cfchanges(rep.cf);
	if(m != 0 || d != nil)
		put(rep.cf.path, fid.ofd, m|ONONE, d, nil, big 0, 1);
	if(fid.ofd != NOFD)
		opmux->clunk(fid.ofd);
	fid.ofd = NOFD;
	creq <-= ref Creq.Done(q, nil);
	if(fid.omode&ORCLOSE)
		remove(q);
}

cclunk(r: ref  Creq.Clunk, cf: ref Cfile)
{
	cf.fd = nil;
	cf.flags |= Cbusy;
	r.rc <-= ref Crep.Clunk(nil, cf);
}

remove(q: big): string
{
	# only remove (clunk is called appart).
	# note that the cache does not check the lease for writing
	# it would be a race anyway, thus, why bother.
	rep := cacheop(ref Creq.Remove(q, nil));
	case rep.err {
	Enotcached =>
		return opmux->remove(rep.cf.path, 0);
	"" =>
		# Cfile should have checked permissions.
		return opmux->remove(rep.cf.path, 1);
	* =>
		return rep.err;
	}
}

cremove(r: ref Creq.Stat, cf: ref Cfile)
{
	if(cf.child != nil)
		r.rc <-= ref Crep.Error(Enotempty, nil);
	else
		r.rc <-= ref Crep.Remove(cf.remove(), cf);
	# the adt will exist with its path ok until the caller
	# releases the reference.
}

cfpath(cf: ref Cfile): string
{
	if(cf.oldname != nil)
		return rooted(dirname(cf.path), cf.oldname);
	else
		return cf.path;
}

wstat(q: big, d: ref Dir): string
{
	rep := cacheop(ref Creq.Wstat(q, nil, d));
	err: string;
	case rep.err {
	Enotcached or Einval =>
		(nil, d, err) = put(cfpath(rep.cf), fid.ofd, ONONE, d, nil, big 0, 0);
		lmode := ONONE;
		if(rep.err == Einval)
			lmode = OWRITE;
		reqc <-= Creq.Update(q, nil, d, nil, big 0, err, lmode);
	"" =>
	* =>
		err = rep.err;
	}
	cf.oldname = nil;
	return err;
}

cwstat(r: ref  Creq.Wstat, cf: ref Cfile)
{
	df := Cfile.find(cf.parentqid, 0);
	cf.oldname = nil;
	if(r.dir.name != nil){
		if(df.walk(r.dir.name) != nil)
			r.rc <-= ref Crep.Error(Eexists, cf);
		cf.oldname = cf.d.name;
	}
	if(df.flags&Cbusy)
		df.reqs = append(df.reqs, r)
	else if((cf.flags&Clease) != OWRITE) || !notcached(df.d) && (df.flags&Clease) != OWRITE){
		cf.flags |= Cbusy;
		r.rc <-= ref  Crep.Wstat(Einval, cf, nil);
	} else {
		err := cf.wstat(r.dir);
		if(err)
			r.rc <-= ref Crep.Error(err, cf);
		else {
			cf.flags |= Cdirtyd;
			r.rc <-= ref  Crep.Wstat(nil, cf);
		}
	}
}

notcached(d: ref Dir): int
{
	if((d.qid.qtype&(QTAPPEND|QTEXCL)) != 0)
		return 1;
	if(d.name == "ctl" || d.name == "clone")
		return 0;
	return (d.qid.qtype&QTCACHE) == 0;
}

reqfile(r: ref Creq, lchk, cchk: int): (ref Cfile, string)
{
	cf := Cfile.find(r.q, 0);
	if(cf == nil)
		panic("cache: file not found");
	if(cf.flags&Cbusy){
		cf.reqs = append(cf.reqs, r);
		return (nil, nil);
	}
	if((cf.flags&Clease) != ONONE)
	if(now() - cf.ltime > Lmax && (cf.flags&(Ccreated|Cdirtyd)) == 0)
		cf.flags = (cf.flags&~Clease) | ONONE;
	if(lchk && (cf.flags&Clease) == ONONE){
		cf.flags |= Cbusy;
		return (cf, Einval);
	}
	if(cchk && (notcached(cf.d) || now - cf.ltime > Lmax))
		return (cf, Enotcached);
	return (cf, nil);
}

cacheproc()
{
	pending: list of ref Creq;
	req: ref Creq;
	for(;;){
		if(pending != nil){
			req = hd pending;
			pending = tl pending;
		} else
			req = <-reqc;
		cf: ref Cfile;
		err: string;
		if(req.rc == nil)
			req.rc = chan[1] of ref Crep;
		pick req {
		Open or Stat or Read or Write or Wstat =>
			(cf, err) = reqfile(req, 1, 1);
		Children or Parent or Walk or Create =>
			(cf, err) = reqfile(req, 0, 0);
		Clunk or Remove =>
			(cf, err) = reqfile(req, 0, 1);
		Update or Inval or Done=>
			cf = Cfile.find(req.q, 0);
		}
		if(cf == nil)
			continue;
		if(err != nil){
			req.rc <-= ref Crep.Error(err, cf);
			continue;
		}
		cachereq(req);
		pick r := req {
		Children =>	children(r, cf);
		Parent =>	cparent(r, cf);
		Stat =>	cstat(r, cf);
		Remove =>	cremove(r, cf);
		Walk =>	cwalk(r, cf);
		Open =>	copen(r, cf);
		Create =>	ccreate(r, cf);
		Read =>	cread(r, cf);
		Write =>	cwrite(r, cf);
		Wstat =>	cwstat(r, cf);
		Clunk =>	cclunk(r, cf);
		Inval =>	cinval(r, cf);
		Update =>	pending = concat(pending, cupdate(r, cf));
		Done =>	pending = concat(pending, cdone(r, cf));
		}
	}
}

invalproc()
{
	for(;;){
		r := nopmux->inval();
		(np, pl) := tokenize(r.paths, "\n");
		for(;pl != nil; pl = tl pl){
			(nels, els)  := tokenize(hd pl, "/");
			pa := array[nels] of string;
			for(i := 0; i < nels; i++){
				pa[i] = hd els;
				els = tl els;
			}
			cacheop(ref Creq.Inval(rootqid, nil, pa);
		}
	}
}

# Update our cache wrt data retrieved from the server
# (perhaps just an error indication)
# wstat must handle clone: If update returns a qid other than the one known
# for the file, the file is the result of a clone and should be added to a cloned
# file list outside of the tree.
# if the file was created by walk and is not attached to the tree, we must invent
# fake directories in the path to the file, by calling attach on the file.
cupdate(r: ref  Creq.Update, cf: ref Cfile): list of ref Creq
{
	if(r.lease != ONONE){
		if((cf.flags&Cbusy) == 0)
			fprint(stderr, "%s: file not busy?\n", cf.path);
		c.flags &= ~Cbusy;
	} else if(cf.flags&Cbusy)
		fprint(stderr, "%s: update on busy file\n", cf.path);
	if(r.err != nil){
		cf.remove();
		return;
	}
	if(cf.flags&Corphan)
		cf.adopt();
	if(r.lease != ONONE)
		if((cf.flags&Clease) == ONONE || r.lease == OWRITE){
			cf.lease = r.lease;
			cf.ltime = now();
		}
	if(r.dir != nil)
		cf.wstat(ref *r.dir);
	if(r.data != nil)
		cf.write(r.data, r.off);
	if((cf.flags&Cbusy) == 0){
		reqs := cf.reqs;
		cf.reqs = nil;
		return reqs;
	} else
		return nil;
}

cdone(nil: ref Creq.Done, cf: ref Cfile): list of ref Creq
{
	if(cf != nil){
		cf.flags &= ~Cbusy;
		reqs := cf.reqs;
		cf.reqs = nil;
		return reqs;
	}
	return nil;
}

# Invalidate leases as requested from the server
cinval(r: ref Creq, cf: ref Cfile)
{
	for(i = 0; cf != nil && i < len r.path; i++)
		cf = cf.walk(r.path[i]);
	if(cf != nil){
		if(cf.flags&Cbusy){
			cf.reqs = append(cf.reqs, r);
			return;
		}
		cf.flags =(cf.flags&~Clease)|ONONE;
	}
	r.rc <-= ref Crep.Inval(nil);
}
