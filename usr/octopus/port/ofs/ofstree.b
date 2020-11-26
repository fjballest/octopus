implement Ofstree;
include "sys.m";
	sys: Sys;
	fprint, OREAD, open, pwrite, pread, remove, sprint, pctl, millisec, DMDIR, write, nulldir, tokenize, fildes,
	QTDIR, FD, read, create, OWRITE, ORDWR, Dir, Qid: import sys;
include "names.m";
	names: Names;
	cleanname: import names;
include "string.m";
	str: String;
	splitstrl: import str;
include "styx.m";
	styx: Styx;
	unpackdir: import styx;
include "error.m";
	err: Error;
	stderr, panic: import err;
include "readdir.m";
	readdir: Readdir;
include "ofstree.m";


# Cachedir can be used to keep a map of names/serverqids
# to store within the directory ("dir/.ofs") when using a disk cache.
# this is untested; not yet used.

# BUG: we create the files as they are seen by stop, but for
# many of them, we don't know at that time if the files are
# files or directories. So, this must be changed to
# create the files really when we need them to keep data
# on them. Directories as necessary to keep the files there.

Cachefile: adt {
	name: string;
	qid: Qid;
};

Cachedir: adt {
	fname: string;
	map: list of Cachefile;
	get:	fn(path: string): ref Cachedir;
	find:	fn(c: self ref Cachedir, name: string): ref Qid;
	add:	fn(c: self ref Cachedir, name: string, q: Qid);
	del:	fn(c: self ref Cachedir, name: string);
	put:	fn(c: self ref Cachedir);
};

Cachedir.find(c: self ref Cachedir, name: string): ref Qid
{
	for(l := c.map; l != nil; l = tl l)
		if((hd l).name == name)
			return ref (hd l).qid;
	return nil;
}

Cachedir.add(c: self ref Cachedir, name: string, q: Qid)
{
	nmap : list of Cachefile;
	found := 0;
	for(l := c.map; l != nil; l = tl l)
		if((hd l).name == name){
			found = 1;
			nmap = Cachefile(name, q) :: nmap;
		} else
			nmap = hd l :: nmap;
	if(!found)
		c.map = Cachefile(name, q) :: c.map;
}

Cachedir.del(c: self ref Cachedir, name: string)
{
	nmap : list of Cachefile;
	for(l := c.map; l != nil; l = tl l)
		if((hd l).name != name)
			nmap = hd l :: nmap;
	c.map = nmap;
}

Cachedir.get(fname: string): ref Cachedir
{
	# BUG: should read only if qid changed

	fname += "/.ofs";
	fd := open(fname, OREAD);
	if(fd == nil)
		return ref Cachedir(fname, nil);
	buf := array[16*1024] of byte;
	tot := 0;
	for(;;){
		nr := read(fd, buf[tot:], len buf - tot);
		if(nr < 0)
			return ref Cachedir(fname, nil);
		if(nr == 0){
			buf = buf[0:tot];
			break;
		}
		if(tot > 64 * 1024 * 1024){
			fprint(stderr, "ofs: cachedir: file too large. fix me.\n");
			return nil;
		}
		if(tot == len buf){
			nbuf := array[2 * len buf] of byte;
			nbuf[0:] = buf;
			buf = nbuf;
		}
	}
	text := string buf;
	buf = nil;
	(n, items) := tokenize(text, " \n");
	nents := n/4;
	map : list of Cachefile;
	for(i := 0; i < nents; i++){
		name := hd items; items = tl items;
		path := big hd items; items = tl items;
		vers := int hd items; items = tl items;
		qt := int hd items; items = tl items;
		map = Cachefile(name, Qid(path, vers, qt)) :: map;
	}
	return ref Cachedir(fname, map);
}

Cachedir.put(c: self ref Cachedir)
{
	fd := create(c.fname, OWRITE, 8r664);
	if(fd == nil)
		return;
	for(l := c.map; l != nil; l = tl l){
		e := hd l;
		fprint(fd, "%s %bd %d %d\n", e.name, e.qid.path, e.qid.vers, e.qid.qtype);
	}
}

ncachedfiles := 0;

tab: array of ref Cfile;
fsdir: string;

init(msys: Sys, mstr: String, mstyx: Styx, merr: Error, n: Names, dir: string): string
{
	sys = msys;
	str = mstr;
	styx = mstyx;
	err = merr;
	names = n;
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		fsdir = nil;
	tab = array[211] of ref Cfile;	# use a prime number 
	if(dir != nil)
		fsdir = names->cleanname(dir);
	return nil;
}

hashfn(q: big, n: int): int
{
	h := int (q % big n);
	if(h < 0)
		h += n;
	return h;
}

Cfile.create(parent: ref Cfile, d: ref Sys->Dir): ref Cfile
{
	if(Cfile.find(d.qid.path) != nil){
		fprint(stderr, "fscreate: qid already exists: %bx\n", d.qid.path);
		return nil;
	}
	fh: ref Cfile;
	if(parent == nil)
		fh = ref Cfile(~0, ~0, nil, d, nil, 0, 0, 0, 0, nil, d.qid.path, Qid(big 0, 0, d.qid.qtype), 0, nil, nil, nil);
	else {
		if(parent.walk(d.name) != nil)
			return nil;
		fh = ref Cfile(~0, ~0, nil, d, nil, 0, 0, 0, 0, nil, parent.d.qid.path, Qid(big 0, 0, d.qid.qtype), 0, nil, nil, nil);
		fh.sibling = parent.child;
		parent.child = fh;
	}
	slot := hashfn(d.qid.path, len tab);
	fh.hash = tab[slot];
	tab[slot] = fh;
	ncachedfiles++;

	if(fsdir != nil && parent != nil){
		path := names->cleanname(fsdir + "/" + fh.getpath() );
		mode := 8r664;
		if(d.mode&DMDIR)
			mode = DMDIR|8r775;
		fd := sys->open(path, OREAD);
		if(fd == nil)
			fd = sys->create(path, OREAD, mode);
		if(debug)
			fprint(stderr, "cache: create %s\n", path);
		if(fd == nil)
			fprint(stderr, "cache: create %s: %r\n", path);
	}
	return fh;
}

Cfile.find(q: big): ref Cfile
{
	for(fh := tab[hashfn(q, len tab)]; fh != nil; fh = fh.hash)
		if(fh.d.qid.path == q)
			return fh;
	return nil;
}

Cfile.updatedirdata(f: self ref Cfile, data : array of byte)
{
	sons, l : list of  ref Dir;
	gonesons : list of big;
	tot := n:= 0;
	d : ref Dir;
	xd : Dir;
	fh: ref Cfile;

	if(len data == 0)
		return;
	f.dirreaded = 1;
	sons = nil;
	gonesons = nil;
	l = nil;
	d = nil;
	fh = nil;
	# 1. unpack.
	do {
		(n, xd) = unpackdir(data[tot:]);
		if(n >= 0){
			tot += n;
			sons = ref xd :: sons;
		}
	} while(n > 0 && tot < len data);

	# 2. update changed ones; record gone ones.
	gonesons = nil;
	for(fh = f.child; fh != nil; fh = fh.sibling){
		# search by name; qids might be faked
		for(l = sons; l != nil && (hd l).name != fh.d.name ; l = tl l)
				;
		if(l != nil){
			q := fh.d.qid.path;	# we invent our own qids
			fh.d = ref *(hd l);
			fh.serverqid = fh.d.qid;
			fh.d.qid.path = q;
		} else
			# must keep files just created (they may be not yet reported by the server)
			if(!fh.created)
				gonesons = fh.d.qid.path :: gonesons;
	}

	# 3. remove gone ones
	while(gonesons != nil){
		if(debug)
			fprint(stderr, "cache: readdir: invalidate %bx \n", hd gonesons);
		if(fsdir != nil){
			sf := Cfile.find(hd gonesons);
			path := names->cleanname(fsdir + "/" + sf.getpath());
			if(path != fsdir)
				removefsdir(fsdir + "/" + sf.getpath());
		}
		removeqid(hd gonesons);
		gonesons = tl gonesons;
	}

	# 4. add new ones
	for(l = sons; l != nil; l = tl l){
		d = hd l;
		sq := d.qid.path;
		for(fh = f.child; fh != nil && fh.serverqid.path != sq; fh = fh.sibling)
			;
		if(fh == nil){
			d.qid.path = ++qseq;
			fh = Cfile.create(f, d);
			if(fh == nil){
				# this happens for files bound twice or more in the same dir
				# the file is already cached, ignore.
				--qseq;
			} else {
				fh.serverqid =  Qid(sq, d.qid.vers, d.qid.qtype);
				if(debug)
					fprint(stderr, "cache: new: %s\n", fh.text());
			}
		}
	}
}

Cfile.getpath(fh: self ref Cfile): string
{
	if(fh == nil)
		panic("fsgetpath: nil fh");
	if(fh.d == nil)
		panic("fsgetpath: nil d");
	s : string;
	if(fh.parentqid == fh.d.qid.path)
		return "/";
	for(;;) {
		if(fh.d == nil)
			panic("fsgetpath:null dir");
		if(s == nil){
			if(fh.oldname != nil)
				s = fh.oldname;
			else
				s = fh.d.name;
		} else if(fh.parentqid == fh.d.qid.path)
			return "/" + s;
		else {
			if(fh.oldname != nil)
				s = fh.oldname + "/" + s;
			else
				s = fh.d.name + "/" + s;
		}
		fh = Cfile.find(fh.parentqid);
		if(fh == nil)
			panic("fsgetpath:parent not in table");
	}
	return nil;
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

qseq := big 16r6b60000000000000;

Cfile.walkorcreate(fh: self ref Cfile, name: string, d: ref Dir): (ref Cfile, int)
{
	newf := 0;
	f := fh.walk(name);
	if(f == nil){
		newf = 1;
		if(d == nil){
			d = ref *fh.d;
			d.qid.path = ++qseq;
			d.qid.qtype = QTDIR;
			d.qid.vers = 0;
			d.name = name;
		} else {
			d.qid.path = ++qseq;	# we use our own qids.
			d.name = name;		# even when d.qid is ok.
			if(d.mode&DMDIR)
				d.qid.qtype |= QTDIR;
		}
		f = Cfile.create(fh, d);
		if(f == nil)
			panic(sprint("walkorcreate: create: %s at %s q %bx\n", name, fh.d.name, d.qid.path));
		else
			if(debug)
				fprint(stderr, "cache: added: %s\n", f.text());
	}
	if(f == nil)
		panic(sprint("walkorcreate: nil f for name %s", name));
	return (f, newf);
}

Cfile.children(f: self ref Cfile, cnt, off: int) : list of Sys->Dir
{
	fh := f.child;
	while(off > 0 && fh != nil){
		off--;
		fh = fh.sibling;
	}
	l : list of Sys->Dir;
	l = nil;
	while(cnt > 0 && fh != nil){
		cnt--;
		l = *fh.d :: l;
		fh = fh.sibling;
	}
	# Kludge: keep the list in order
	# otherwise, offsets for childs are wrong. Should have
	# used an array of children instead.
	ll: list of Sys->Dir;
	for(; l != nil; l = tl l)
		ll = hd l :: ll;
	return ll;
}

removeqid(q: big): string
{
	prev: ref Cfile;

	# remove from hash table
	slot := hashfn(q, len tab);
	for(fh := tab[slot]; fh != nil; fh = fh.hash) {
		if(fh.d.qid.path == q)
			break;
		prev = fh;
	}
	if(fh == nil)
		return "file not found";
	if(prev == nil)
		tab[slot] = fh.hash;
	else
		prev.hash = fh.hash;
	fh.hash = nil;

	# remove from parent's children
	parent := Cfile.find(fh.parentqid);
	if(parent != nil) {
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

	# now remove any descendents
	sibling: ref Cfile;
	for(sfh := fh.child; sfh != nil; sfh = sibling) {
		sibling = sfh.sibling;
		sfh.parentqid = sfh.d.qid.path;		# make sure it doesn't disrupt things.
		removeqid(sfh.d.qid.path);
	}
	ncachedfiles--;
	return nil;
}

removefsdir(path: string)
{
	if(debug)
		fprint(stderr, "cache: remove %s\n", path);
	if(path[0:4] != "/tmp" && path[0:6] != "/cache")
		return;			# SAFETY FIRST
	(dirs, e) := readdir->init(path, Readdir->NONE);
	for(i := 0; i < e; i++)
		removefsdir(path + "/" + dirs[i].name);
	sys->remove(path);
}

Cfile.remove(f: self ref Cfile): string
{
	if(fsdir != nil){
		path := names->cleanname(fsdir + "/" + f.getpath());
		if(path != fsdir)
			removefsdir(fsdir + "/" + f.getpath());
	}
	return removeqid(f.d.qid.path);
}

applydir(d: ref Sys->Dir, onto: ref Sys->Dir): ref Sys->Dir
{
	if(d.name != nil)
		onto.name = d.name;
	if(d.uid != nil)
		onto.uid = d.uid;
	if(d.gid != nil)
		onto.gid = d.gid;
	if(d.muid != nil)
		onto.muid = d.muid;
	if(d.qid.vers != ~0)
		onto.qid.vers = d.qid.vers;
	if(d.qid.qtype != ~0)
		onto.qid.qtype = d.qid.qtype;
	if(d.qid.vers != ~0)
		onto.qid.vers = d.qid.vers;
	if(d.mode != ~0)
		onto.mode = d.mode;
	if(d.atime != ~0)
		onto.atime = d.atime;
	if(d.mtime != ~0)
		onto.mtime = d.mtime;
	if(d.length != ~big 0)
		onto.length = d.length;
	if(d.dtype != ~0)
		onto.dtype = d.dtype;
	if(d.dev != ~0)
		onto.dev = d.dev;
	return onto;
}

Cfile.wstat(fh : self ref Cfile, d: ref Sys->Dir): string
{
	q := fh.d.qid.path;
	# if renaming a file, check for duplicates
	if(d.name != nil && d.name != fh.d.name) {
		parent := Cfile.find(fh.parentqid);
		if(parent != nil && parent != fh && parent.walk(d.name) != nil)
			return "File already exists";
		fh.oldname = fh.d.name;
		parent.time = 0;	# invalidate
		fh.time = 0;		# invalidate
		if(fsdir != nil && d.uid != nil){
			nd := sys->nulldir;
			nd.name = d.name;
			sys->wstat(fsdir + "/" + fh.getpath(), nd);
		}
	}
	d = applydir(d, fh.d);
	if(fh.data != nil && d.length < big len fh.data)
	if((d.qid.qtype&QTDIR) == 0)
		fh.data = fh.data[0:int d.length];
	if(fsdir != nil && d.uid != nil){
		# we update cache attributes only to truncate files that are
		# shorter in the fs. No other wstat is propatagated to the cache.
		# It caches just data.
		cfd := sys->nulldir;
		(e, xd) := sys->stat(fsdir + "/" + fh.getpath());
		if(e >= 0 && xd.length > d.length){
			cfd.length = d.length;
			cfd.mode = d.mode;
			if(cfd.mode & DMDIR)
				cfd.mode |= 8r775;
			else
				cfd.mode |= 8r660;
			if(debug)
				fprint(stderr, "cache: wstat %s mode %x\n", fsdir + "/" + fh.getpath(), cfd.mode);
			sys->wstat(fsdir + "/" + fh.getpath(), cfd);
		}
	}
	fh.d = d;
	fh.d.qid.path = q;		# ensure the qid can't be changed
	return nil;
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

Cfile.pwrite(fh: self ref Cfile, data: array of byte, off: big): int
{
	if(fsdir != nil){
		path := fsdir + "/" + fh.getpath();
		if(fh.fsfd == nil){
			if(debug)
				fprint(stderr, "cache: open %s\n", path);
			fh.fsfd = open(path, ORDWR);
			if(fh.fsfd == nil){
				# perhaps we created a dir.
				# replace it with a file, now that we know.
				remove(path);
				fh.fsfd = create(path, ORDWR, 8664);
			}
		}
		if(fh.fsfd != nil)
			return pwrite(fh.fsfd, data, len data, off);
		else
			fprint(stderr, "cache: %s: %r\n", path);
	}
	return -1;
}

Cfile.pread(fh : self ref Cfile, cnt: int, off: big): array of byte
{
	if(fsdir == nil)
		return nil;
	if(fh.fsfd == nil){
		path := fsdir + "/" + fh.getpath();
		fh.fsfd = open(path, ORDWR);
		if(debug)
			fprint(stderr, "cache: open %s\n", path);
	}
	if(fh.fsfd == nil)
		return nil;
	data := array[cnt] of byte;
	nr := pread(fh.fsfd, data, len data, off);
	if(nr <= 0)
		return nil;
	return data[0:nr];
}

Cfile.text(fh: self ref Cfile): string
{
	if(fh == nil)
		return "nil file";
	return sprint(" \"%s\" %s\tc%d s%d sq=%s %d bytes\n",
		fh.getpath(), dir2text(fh.d), fh.created, fh.dirtyd,
		qid2text(fh.serverqid), len fh.data);
}

dir2text(d: ref Sys->Dir): string
{
	return sys->sprint("[\"%s\"  %s 8r%uo %bd]",
		d.uid, qid2text(d.qid), d.mode, d.length);
}

qid2text(q: Sys->Qid): string
{
	return sys->sprint("%.2ubx:%.2ux:%.2ux", q.path, q.vers, q.qtype);
}
