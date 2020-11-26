implement Muxdat;
include "sys.m";
	sys: Sys;
	fildes, fprint, FD, OTRUNC, DMDIR, ORCLOSE, OREAD, ORDWR,
	Qid, print, pctl, create, mount, QTDIR, pread, open, sprint,
	pwrite, remove, nulldir, fwstat, wstat, fstat, stat, Dir, write, sleep, millisec: import sys;
include "draw.m";
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "query.m";
	query: Query;
include "hash.m";
	hash: Hash;
	HashVal, HashNode, HashTable: import hash;
include "names.m";
	names: Names;
	dirname, cleanname, relative, isprefix, rooted: import names;
include "muxdat.m";

include "tbl.m";
	tbl: Tbl;
	Table: import tbl;


attrs: list of string;
qids: ref HashTable;		# qid.path table, indexed by file name
fids:	ref Table[ref Fid];	# fid table, indexed by qid.
metaattrs := 0;			# uses $user in attrs
last := 0;

member(l: list of string, s: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

init(s: Sys, e: Error, n: Names, args: list of string)
{
	sys = s; err = e; names = n;
	query = checkload(load Query Query->PATH, Query->PATH); 
	hash = checkload(load Hash Hash->PATH, Hash->PATH);
	tbl = checkload(load Tbl Tbl->PATH, Tbl->PATH);
	rootdir = Empty;
	nullfid: ref Fid;
	fids = Table[ref Fid].new(103, nullfid);
	qids = hash->new(103);	# use a prime number
	attrs = args;
	if(member(attrs, "$user"))
		metaattrs = 1;
	last = millisec();
}

bindrootdir()
{
	(fspaths, e) := query->lookup(attrs);
	if(debug && e != nil)
		fprint(stderr, "mux: query: %s\n", e);
	while(fspaths != nil){
		rootdir = hd fspaths;
		(se, nil) := stat(rootdir);
		if(se >= 0)
			break;
		if(debug)
			fprint(stderr, "mux: binding %s: %r\n", rootdir);
		fspaths = tl fspaths;
	}
	if(fspaths == nil)
		rootdir = Empty;
	if(debug)
		fprint(stderr, "mux: rootdir bound to %s\n", rootdir);
}

rebindfids(old, new: string, brk: int)
{
	for(i := 0; i < len fids.items; i++){
		for(l := fids.items[i]; l != nil; l = tl l){
			(nil, fid) := hd l;
			wasbroken := fid.broken;
			if(fid.fd != nil)	# could keep OREAD fids, perhaps.
				fid.broken |= brk;
			if(fid.broken){
				if(debug && !wasbroken)
					fprint(stderr, "rebindfids: broken fid %s\n", fid.path);
				continue;
			}
			if(isprefix(old, fid.path) || fid.path == old){
				opath := fid.path;
				rel := relative(fid.path, old);
				fid.path = rooted(new, rel);
				if(brk)
					fid.qid.vers++;	# force
				if(debug)
					fprint(stderr, "rebindfid: %s\t->\t%s\n", opath, fid.path);
			}
		}
	}
}

rebindqids(old, new: string)
{
	for(paths := qids.all(); paths != nil; paths = tl paths){
		nd := hd paths;
		p := nd.key;
		v := nd.val;
		if(isprefix(old, p) || old == p){
			opath := p;
			rel := relative(p, old);
			npath := rooted(new, rel);
			qids.insert(npath, *v);
			qids.delete(p);
			if(debug)
				fprint(stderr, "rebindqid: %s\t->\t%s\n", opath, npath);
		}
	}
}

maybebroken(nil: string)
{
	if(brokenfs != 0)
		return;
	(e, nil) := stat(rootdir);
	if(e < 0)
		brokenfs = 1;
}

rootdirmatches(): int
{
	(fspaths, e) := query->lookup(attrs);
	if(debug && e != nil)
		fprint(stderr, "mux: query: %s\n", e);
	while(fspaths != nil){
		if(rootdir == hd fspaths)
			return 1;
		fspaths = tl fspaths;
	}
	return 0;
}

rebind()
{
	if(rootdir != Empty && !brokenfs && !metaattrs)
		return;
	old := rootdir;
	if(brokenfs || rootdir == Empty)
		bindrootdir();
	else {
		now := millisec();
		if(now - last < 60 * 1000)
			return;
		last = now;
		if(!rootdirmatches())
			bindrootdir();
	}
	if(rootdir == Empty && old == rootdir)	# nothing can be done
		return;

	# update our pahts, and break fids already open
	rebindfids(old, rootdir, 1);
	rebindqids(old, rootdir);
	brokenfs = 0;
}

renametree(old: string, nname: string)
{
	odir := dirname(old);
	new := rooted(odir, nname);
	if(debug)
		fprint(stderr, "renametree: from %s to %s\n", old, new);
	rebindfids(old, new, 0);
	rebindqids(old, new);
}

addfid(fid: ref Fid): int
{
	return fids.add(fid.fid, fid);
}

delfid(fid: ref Fid)
{
	fids.del(fid.fid);
}

getfid(f: int): ref Fid
{
	return fids.find(f);
}

addqid(path: string): big
{
	q := qgen++;
	qids.insert(path, HashVal(q, 0.0, nil));
	return big q;
}

getqid(path: string): big
{
	v := qids.find(path);
	if(v == nil)
		return NOQID; 
	return big v.i;
}

delqid(path: string)
{
	qids.delete(path);
}

# We must ensure that when a qid changes in the server,
# at least the version changes for the client. Otherwise,
# very bad things may hapen if, for example, the client
# is using the qids to build a cache of binary file images.
# This is taken straight from Plan B's bns.

fixqid(path: string, sq: Qid): Qid
{
	q := getqid(path);
	if(q == NOQID)
		q = addqid(path);
	sq.vers = ((int sq.path)^sq.vers);
	sq.path = q;
	return sq;
}

