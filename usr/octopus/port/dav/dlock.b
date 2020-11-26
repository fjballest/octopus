implement Dlock;
include "sys.m";
	sys: Sys;
	open, OREAD, Dir, QTDIR, OWRITE, OTRUNC, FD,
	create, DMDIR, write, remove,
	stat, werrstr, announce, fprint, sprint: import sys;
include "draw.m";
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "string.m";
	str: String;
	toint, splitl, prefix, toupper, tolower: import str;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "daytime.m";
	daytime: Daytime;
	now, gmt: import daytime;
include "names.m";
	names: Names;
	cleanname, rooted: import names;
include "msgs.m";
	msgs: Msgs;
	Cok, Sok, Cbad, Sbad, Cperm, Cmulti, Smulti, Cnotfound,
	Cnotallow, Snotallow, Ccreated, Screated, Csto,
	Msg, Hdr: import msgs;
include "xml.m";
include "xmlutil.m";
	xmlutil: Xmlutil;
	Textname, Rootname, Tag, Attr: import xmlutil;
include "readdir.m";
	readdir: Readdir;
include "dat.m";
include "svc.m";
include "dlock.m";

Lck: adt {
	id:	int;
	time:	int;
	fname:	string;
	owner:	string;
	depth:	int;
	kind:	int;
};

locks: list of ref Lck;
lgen := 0;
period := Lease;

init(d: Dat)
{
	sys = d->sys;
	str = d->str;
	err = d->err;
	daytime = d->daytime;
	names = d->names;
	period = Lease;
}

# return something like e71d4fae-5dec-22d6-fea5-00a0c91e6be4
# (UUID) with the id embedded. We do not generate an actual UUID.
mklck(id: int): string
{
	a := now();
	b := a - id + len locks;
	c := big 16r0a0b0c0d0e0f - big b + big a;
	return sprint("%8.8x-%4.4x-%4.4x-%12.12bx", id, a, b, c);
}

lckid(lck: string): int
{
	if(len lck < 8)
		return -1;
	(n, nil) :=  toint(lck[0:8], 16);
	return n;
}

lastexpire:= 0;
expire()
{
	nlocks: list of ref Lck;
	t := now();
	if(t - lastexpire < period/2)
		return;
	for(; locks != nil; locks = tl locks){
		l := hd locks;
		if(l.time > t)
			nlocks = l::nlocks;
		else if(debug)
			fprint(stderr, "dav: expire: %s\n", l.fname);
	}
	locks = nlocks;
}

locked(fname: string, depth: int, excl: list of string): int
{
	expire();
	kind := Lfree;
	lids: list of int;
	for(; excl != nil; excl = tl excl)
		lids = lckid(hd excl)::lids;
Loop:	for(lcks := locks; lcks != nil; lcks = tl lcks){
		l := hd lcks;
		for(el := lids; el != nil; el = tl el)
			if(hd el == l.id)
				continue Loop;
		if(l.depth && names->isprefix(l.fname, fname))
			kind |= l.kind;
		else if(depth && names->isprefix(fname, l.fname))
			kind |= l.kind;
		else if(l.fname == fname)
			kind |= l.kind;
	}
	if(kind != Lfree && kind != Lread)
		kind = Lwrite;	# because |= above
	return kind;
}

canlock(fname, owner: string, depth, kind: int): string
{
	if(kind != Lread && kind != Lwrite){
		fprint(stderr, "dav: lock: kind %d\n", kind);
		return nil;
	}
	old := locked(fname, depth, nil);
	if(kind == Lwrite && old != Lfree)
		return nil;
	if(kind == Lread && old == Lwrite)
		return nil;
	t := now();
	locks = ref Lck(++lgen, t+period, fname, owner, depth, kind)::locks;
	if(debug)
		fprint(stderr, "dav: locked: %s: id %d\n", fname, lgen);
	return mklck(lgen);
}

unlock(lck: string)
{
	id := lckid(lck);
	nlocks: list of ref Lck;
	for(; locks != nil; locks = tl locks){
		l := hd locks;
		if(l.id != id)
			nlocks = l::nlocks;
		else if(debug)
			fprint(stderr, "dav: unlock: %s\n", l.fname);
	}
	locks = nlocks;
}

rmlocks(fname: string)
{
	nlocks: list of ref Lck;
	for(; locks != nil; locks = tl locks){
		l := hd locks;
		if(names->isprefix(fname, l.fname) == 0)
			nlocks = l::nlocks;
		else if(debug)
			fprint(stderr, "dav: rmlock: %s\n", l.fname);
	}
	locks = nlocks;
}

renew(lck: string): (string, string)
{
	id := lckid(lck);
	for(lcks := locks; lcks != nil; lcks = tl lcks){
		l := hd lcks;
		if(l.id == id){
			l.time = now() + period;
			return (lck, l.owner);
		}
	}
	return (nil, nil);
}




