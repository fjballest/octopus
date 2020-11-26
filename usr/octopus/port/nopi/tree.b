implement Tree;
#
# Management of the file tree in the cache.
# metadata is kept in memory and a local directory
# is used to keep the on-disk cache for nopi.
# The structure of the cache on the disk reflects the
# file tree on the server. When the disk cache is not used,
# only metadata is cached.

# Locking must be provided by the caller.
# The cache allows files to be orphan, without
# being attached to the tree. 
# All qids are invented by the tree using qgen.
# The file descriptor used to read/write the cached files
# is always ORDWR and kept at Cfile.fd. It is open on demand
# and closed by the client upon clunks.
# Flags created, dirtyd, and dirtydata are used to coallesce
# multiple operations, and are maintained by the client
# (the tree does not know if an update is being made to reflect
# info obtained from the server or to make changes to it).

include "sys.m";
	sys: Sys;
	fprint, OREAD, open, pwrite, pread, remove, sprint,
	pctl, millisec, DMDIR, write, nulldir, tokenize, fildes,
	QTDIR, FD, read, create, OWRITE, ORDWR, Dir, Qid: import sys;
include "error.m";
	err: Error;
	stderr, panic: import err;
include "names.m";
	names: Names;
	cleanname: import names;
include "string.m";
	str: String;
	splitstrl: import str;
include "readdir.m";
	readdir: Readdir;
include "ssrv.m";
	Enotdir: import Ssrv;
include "tree.m";

Ctree: adt {
	root:	ref Cfile;
	fsdir:	string;
	qgen:	big;
	nfiles:	int;
	tab:	array of ref  Cfile;
	orphan:	list of ref  Cfile;

	hash:	fn(t: self ref Ctree, q: big): int;
	add:	fn(t: self ref Ctree, f: ref Cfile);
	find:	fn(t: self ref Ctree, q: big, del: int): ref Cfile;
	findorphan:	fn(t: self ref Ctree, p: string): ref Cfile;
	delorphan:	fn(t: self ref Ctree, o: ref Cfile);
	};


t: ref Ctree;

init(msys: Sys, mstr: String, merr: Error, n: Names, rd: Readdir)
{
	sys = msys;
	str = mstr;
	err = merr;
	names = n;
	readdir = rd;
}

newdir(path: string, q: big): ref  Cfile
{
	r := ref  nullfile;
	r.path = path;
	d := ref nulldir;
	d.name = basename(path);
	d.uid = d.gid = "sys";
	d.atime = d.mtime = now();
	d.qid = Qid(q, 0, QTDIR);
	r.d = d;
	t.add(r);
	return r;
}

nullfile: Cfile;
attach(q: big, dir: string): string
{
	if(dir != nil)
		dir = cleanname(dir);
	(rc, d)  := stat(fsdir);
	if(rc < 0)
		return sprint("%r");
	if(d.qid.qtype&QTDIR == 0)
		return Enotdir;
	t = ref Ctree(dir, big 0, 0, array[211] of ref Cfile, nil);
	r := newdir("/", q);
	r.parentqid = q;
	t.root = r;
	return nil;
}

Ctree.hash(t: self ref Ctree, q: big): int
{
	h := int (q % big len t.tab);
	if(h < 0)
		h += len t.tab;
	return h;
}

Ctree.add(t: self ref  Ctree, fh: ref Cfile)
{
	slot := t.hash(fh.d.qid.path);
	fh.hash = t.tab[slot];
	t.tab[slot] = fh;
	t.nfiles++;
}

Ctree.find(t: self ref Tree, q: big, del: int): ref Cfile
{
	slot := t.hash(q);
	prev: ref Cfile;
	for(fh := t.tab[slot]; fh != nil; fh = fh.hash) {
		if(fh.d.qid.path == q)
			break;
		prev = fh;
	}
	if(fh != nil && del){
		if(prev == nil)
			t.tab[slot] = fh.hash;
		else
			prev.hash = fh.hash;
		fh.hash = nil;
	}
	return fh;
}

Ctree.findorphan(t: self ref  Tree, p: string): ref Cfile
{
	for(l := t.orphan; l != nil; l = tl l)
		if((hd l).path == p)
			return hd l;
	return nil;
}

Ctree.delorphan(t: self ref  Tree, o: ref  Cfile)
{
	nl: list of ref  Cfile;
	for(; t.orphan != nil; t.orphan = tl t.orphan)
		if(hd t.orphan != o)
			nl = hd t.orphan::nl;
	t.orphan = nl;
}

Cfile.orphan(path: string): ref Cfile
{
	nf := t.findorphan(path);
	if(nf == nil){
		nf := newdir(path, ++qgen);
		nf.flags =  ONONE|Corphan;
		t.orphan = nf::t.orphan;
	}
	return nf;
}

Cfile.find(q: big); ref Cfile
{
	return t.find(q);
}

Cfile.read(fh : self ref Cfile, data: array of byte, off: big): int
{
	if(t.fsdir == nil)
		return -1;	# data not cached.
	if(fh.fd == nil){
		path := t.fsdir +  fh.path;
		fh.fd = open(path, ORDWR);
	}
	if(fh.fd == nil){
		if(debug)
			fprint(stderr, "cache: %s: %r\n", path);
		return -1;
	} else if(debug)
		fprint(stderr, "cache: open %s\n", path);
	return pread(fh.fd, data, len data, off);
}

Cfile.write(fh: self ref Cfile, data: array of byte, off: big): int
{
	if(t.fsdir == nil)
		return -1;	# data not cached.
	if(fh.fd == nil){
		path := t.fsdir + "/" + fh.getpath();
		fh.fd = open(path, ORDWR);
	}
	if(fh.fd == nil){
		if(debug)
			fprint(stderr, "cache: %s: %r\n", path);
		return -1;
	} else if(debug)
		fprint(stderr, "cache: open %s\n", path);
	return pwrite(fh.fd, data, len data, off);
}

removefsdir(path: string)
{
	if(debug)
		fprint(stderr, "cache: remove %s\n", path);
	if(debug && path[0:4] != "/tmp" && path[0:6] != "/cache"){
		fprint(stderr, "cache: wont remove outside /tmp or /cache\n");
		return;
	}
	(dirs, e) := readdir->init(path, Readdir->NONE);
	for(i := 0; i < e; i++)
		removefsdir(path + "/" + dirs[i].name);
	sys->remove(path);
}

removeqid(q: big): string
{
	# remove from hash, orphan, and parent (if any)
	fh := t.del(q);
	if(fh == nil)
		return "file not found";
	if(fh.flags&Corphan)
		t.delorphan(fh);
	parent := Cfile.find(fh.parentqid);
	if(parent != nil && parent != fh) {
		prev = nil;
		for(sfh := parent.child; sfh != nil; sfh = sfh.sibling) {
			if(sfh == fh)
				break;
			prev = sfh;
		}
		if(sfh == nil)
			panic("child not found in parent");
		if(prev == nil)
			parent.child = fh.sibling;
		else
			prev.sibling = fh.sibling;
	}
	fh.sibling = nil;

	sibling: ref Cfile;
	for(sfh := fh.child; sfh != nil; sfh = sibling) {
		sibling = sfh.sibling;
		sfh.parentqid = sfh.d.qid.path; #make its own root
		removeqid(sfh.d.qid.path);
	}
	fh.flags = Cdead; # debug
	return nil;
}

Cfile.remove(f: self ref Cfile): string
{
	if(t.fsdir != nil){
		path := names->cleanname(t.fsdir + "/" + f.path);
		if(path != t.fsdir && isprefix(t.fsdir, path))
			removefsdir(path);
	}
	return removeqid(f.d.qid.path);
}

applydir(d: ref Sys->Dir, onto: ref Sys->Dir, fsys: int): ref Sys->Dir
{
	if(d.name != nil)
		onto.name = d.name;
	if(d.length != ~big 0)
		onto.length = d.length;

	if(fsys)
		return onto;

	if(d.uid != nil)
		onto.uid = d.uid;
	if(d.gid != nil)
		onto.gid = d.gid;
	if(d.muid != nil)
		onto.muid = d.muid;
	if(d.qid.vers != ~0)
		onto.qid.vers = d.qid.vers;
	# qid.path is always kept.
	if(d.qid.qtype != ~0)
		onto.qid.qtype = d.qid.qtype;
	if(d.mode != ~0)
		onto.mode = d.mode;
	if(d.atime != ~0)
		onto.atime = d.atime;
	if(d.mtime != ~0)
		onto.mtime = d.mtime;
	return onto;
}

Cfile.wstat(fh : self ref Cfile, d: ref Sys->Dir): string
{
	if(t.fsdir != nil){
		nd := ref sys->nulldir;
		applydir(d, nd, 1);
		sys->wstat(t.fsdir + "/" + fh.path, *nd);
	}
	applydir(d, fh.d, 0);
	return nil;
}

Cfile.adopt(fh: self ref Cfile)
{
	els := names->elements(fh.path);
	if(hd els == "/")
		els = tl els;
	path := "";
	for(pf := t.root; els != nil && tl els != nil; els = tl els){
		f := pf.walk(hd els);
		if(f == nil){
			path += "/" + hd els;
			f = newdir(path, ++qgen);
			f.flags = CNONE;
			f.parentqid = pf.d.qid.path;
			f.sibling = pf.child;
			pf.child = f;
		}
		f.d.qid.qtype = QTDIR;
		pf = f;
	}
	fh.parentqid = pf.d.qid.path;
	fh.sibling = pf.child;
	pf.child = fh;
	fh.flags  &= ~Corphan;
}

Cfile.dirwrite(f: self ref Cfile, data : array of byte)
{
	tot := n:= 0;
	d: ref Dir;
	xd : Dir;
	fh: ref Cfile;

	f.flags  |= Cdata;

	# 1. unpack data.
	sons, l : list of  ref Dir;
	do {
		(n, xd) = unpackdir(data[tot:]);
		if(n >= 0){
			tot += n;
			sons = ref xd :: sons;
		}
	} while(n > 0 && tot < len data);

	# 2. update stat for known files; record gone ones.
	gone: list of big;
	for(fh = f.child; fh != nil; fh = fh.sibling){
		# search by name; we invent our own qids
		for(l = sons; l != nil && (hd l).name != fh.d.name ; l = tl l)
				;
		if(l != nil){
			q := fh.d.qid.path;	# we invent our own qids
			fh.d = ref *(hd l);
			fh.d.qid.path = q;
		} else {
			# must keep the ones we just created
			if((fh.flags&Ccreated) == 0)
				gone = fh.d.qid.path :: gone;
		}
	}

	# 3. remove gone files
	for(; gone != nil; gone = tl gone){
		if(debug)
			fprint(stderr, "cache: readdir: gone %bx \n", hd gone);
		if(t.fsdir != nil){
			sf := Cfile.find(hd gone);
			path := t.fsdir + "/" + sf.path;
			if(path != fsdir)
				removefsdir(path);
		}
		removeqid(hd gone);
	}

	# 4. add new ones
	for(l = sons; l != nil; l = tl l){
		d = hd l;
		for(fh = f.child; fh != nil && fh.name != d.name; fh = fh.sibling)
			;
		# a single name may show up multiple times, because of bind.
		# this is not to be considered an error.
		if(fh == nil && f.walk(d.name) == nil){
			fh = newdir(f.path + "/" + d.name, ++qseq);
			applydir(fh.d, d, 0);
			fh.parentqid = f.d.qid.path;
			fh.sibling = f.child;
			f.child = fh;
			if(debug)
				fprint(stderr, "cache: new: %s\n", fh.text());
		}
	}
}

Cfile.walk(fh: self ref Cfile, name: string): ref Cfile
{
	if(name == "..")
		return Cfile.find(fh.parentqid);
	for(fh = fh.child; fh != nil; fh = fh.sibling)
		if(fh.d.name == name)
			return fh;
	return nil;
}

Cfile.children(f: self ref Cfile) : array of ref Sys->Dir
{
	n := 0;
	for(fh := f.child; fh != nil; fh = fh.sibling)
		n++;
	a := array[n] of ref Dir;
	n = 0;
	for(fh = f.child; fh != nil; fh = fh.sibling)
		a[n++] = ref *hf.d;
	return a;
}


Cfile.dump(f: self ref Cfile, t: int, pref: string)
{
	tabs := "\t\t\t\t\t\t\t\t\t\t";
	s := "";
	if(pref != nil){
		s = pref + sprint("(%d files)\n", ncachedfiles);
		pref = nil;
	}
	ts := tabs[0:t];
	s += ts + f.text();
	a:= array of byte s;
	write(stderr, a, len a);
	for(fh := f.child; fh != nil; fh = fh.sibling)
		fh.dump(t+1, nil);
}

Cfile.text(fh: self ref Cfile): string
{
	if(fh == nil)
		return "nil file";
	return sprint(" \"%s\" %s\t%x %d bytes\n",
		fh.path, dir2text(fh.d), fh.flags, len fh.data);
}
