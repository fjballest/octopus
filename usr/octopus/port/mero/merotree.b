# File hierarchy handling code, and related tools for omero
#

implement Merotree;

include "sys.m";
	sys: Sys;
	millisec, sprint, QTFILE, DMDIR, DMEXCL, Qid, Dir, QTDIR, fprint: import sys;
include "styx.m";
include "styxservers.m";
	Styxserver, Eexists, Enotfound: import Styxservers;
include "daytime.m";
	daytime: Daytime;
	now: import daytime;
include "dat.m";
	dat: Dat;
	vgen, mnt, debug, appl, user, slash: import dat;
include "string.m";
	str: String;
include "names.m";
	names: Names;
	rooted, elements, dirname: import names;
include "error.m";
	err: Error;
	checkload, panic, stderr: import err;
include "lists.m";
	lists: Lists;
	reverse, concat: import lists;
include "tbl.m";
	tbl: Tbl;
	Table: import tbl;
include "mpanel.m";
	panels: Panels;
	Qdir, Qctl, Qdata, Qolive, Qedits: import Panels;
	Aappl, Panel, Repl, Trepl, Tappl, qid2ids, mkqid, Amax: import panels;
include "merocon.m";
	merocon: Merocon;
	post, hold, rlse: import merocon;
include "rand.m";
	rand: Rand;
include "blks.m";
	blks: Blks;
	Blk: import blks;
include "merop.m";
	merop: Merop;
	Msg: import merop;
include "merotree.m";

srv: ref Styxserver;
fstab: array of ref Fholder;

NOQID: con big ~0;
Aorder: con Amax;

Fholder: adt {
	parentqid:	big;
	d:	Sys->Dir;
	child:	cyclic ref Fholder;
	sibling:	cyclic ref Fholder;
	hash:	cyclic ref Fholder;
};


init(d: Dat): chan of ref Styxservers->Navop
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	srv = dat->srv;
	merop = dat->merop;
	blks = dat->blks;
	daytime = dat->daytime;
	panels = dat->panels;
	names = dat->names;
	lists = dat->lists;
	merocon = dat->merocon;
	rand = checkload(load Rand Rand->PATH, Rand->PATH);
	rand->init(millisec());
	fstab = array[101] of ref Fholder;
	c := chan of ref Styxservers->Navop;
	spawn navproc(c);
	vgen = 0;
	return c;
}

navproc(c: chan of ref Styxservers->Navop)
{
	while((m:= <-c) != nil){
		(q, reply) := (m.path, m.reply);
		pick rq := m {
		Stat =>
			fh := findfile(q);
			if(fh == nil)
				reply <-= (nil, Enotfound);
			else
				reply <-= (ref fh.d, nil);
		Walk =>
			sq := fwalk1(q, rq.name);
			if(sq == NOQID)
				reply <-= (nil, Enotfound);
			else {
				fh := findfile(sq);
				reply <-= (ref fh.d, nil);
			}
		Readdir =>
			fh := findfile(q);
			if(fh == nil)
				reply <-= (nil, Enotfound);
			else {
				(start, end) := (rq.offset, rq.offset + rq.count);
				fh = fh.child;
				for(i := 0; i < end && fh != nil; i++) {
					if(i >= start)
						reply <-= (ref fh.d, nil);
					fh = fh.sibling;
				}
				reply <-= (nil, nil);
			}
		* =>
			panic(sys->sprint("unknown op %d\n", tagof(m)));
		}
	}
}

pwalk(s: string):  (ref Panel, ref Repl)
{
	q := slash;
	if(len s > 0 && s[0] == '/')
		s=s[1:];
	for(els := elements(s); els != nil; els = tl els){
		q = fwalk1(q, hd els);
		if(q == NOQID)
			break;
	}
	if(q == NOQID)
		return (nil, nil);
	(pid, rid, nil) := qid2ids(q);
	return Panel.lookup(pid, rid);
}

pparent(r: ref Repl): (ref Panel, ref Repl)
{
	fh := findfile(r.dirq);
	if(fh == nil)
		return (nil, nil);
	(pid, rid, nil) := qid2ids(fh.parentqid);
	return Panel.lookup(pid, rid);
}

pchilds(r: ref Repl) : array of (ref Panel, ref Repl)
{
	fh := findfile(r.dirq);
	if(fh == nil)
		return nil;
	nchilds := 0;
	for(cfh := fh.child; cfh != nil; cfh = cfh.sibling)
		if(cfh.d.qid.qtype&QTDIR)
			nchilds++;
	childs := array[nchilds] of big;
	nchilds = 0;
	for(cfh = fh.child; cfh != nil; cfh = cfh.sibling)
		if(cfh.d.qid.qtype&QTDIR)
			childs[nchilds++] = cfh.d.qid.path;
	cl := array[nchilds] of (ref Panel, ref Repl);
	for(i := 0; i < nchilds; i++){
		(pid, rid, nil) := qid2ids(childs[i]);
		cl[i] = Panel.lookup(pid, rid);
	}
	return cl;
}

# returns everything if vers < 0. The format is:
# Must report updates for parents before their childs.
# Must also report the edit vers for the panel, for ins/del ops.
pchanges(p: ref Panel, r: ref Repl, vers: int): (list of ref Merop->Msg, int)
{
	pvers := r.dvers;
	if(pvers < r.cvers)
		pvers = r.cvers;
	if(pvers <= vers)
		return (nil, vers);
	if(debug)
		fprint(stderr, "\tpchanges %s d%d c%d e%d v%d\n",
			p.name, r.dvers, r.cvers, p.evers, vers);
	m := ref Msg.Update(r.path, p.evers, nil, nil, nil);
	if(r.cvers > vers)
		m.ctls = r.ctlstr(vers);
	if(r.dvers > vers){
		m.data = p.data;
		m.edits = p.edits;
	}
	childs := pchilds(r);
	l: list of ref Merop->Msg;
	l = m::nil;
	for(i := 0; i < len childs; i++){
		(cp, cr) := childs[i];
		(cl, cvers) := pchanges(cp, cr, vers);
		l = concat(l, cl);
		if(pvers < cvers)
			pvers = cvers;
	}
	return (l, pvers);
}

# See the comment at merocon.b:/^eventproc
pheldupd(p: ref  Panel, vers: int)
{
	vgen++;
	if(vgen <= 0)
		fprint(stderr, "o/mero: vgen overflow; use a big\n");
	_pheldupd(p, vers);
}
_pheldupd(p: ref Panel, vers: int)
{
	for(i := 0; i < len p.repl; i++){
		r := p.repl[i];
		if(r != nil){
			if(r.dvers > vers)
				r.dvers = vgen;
			if(r.cvers > vers){
				r.cvers = vgen;
				for(a := 0; a < len r.attrs; a++)
					if(r.attrs[a].vers > vers)
					r.attrs[a].vers = vgen;
			}
		}
	}
	if(p.repl[0] != nil){
		childs := pchilds(p.repl[0]);
		for(j := 0; j < len childs; j++){
			(cp, nil) := childs[j];
			if(cp != nil)
				_pheldupd(cp, vers);
		}
	}
}

pchanged(p: ref Panel)
{
	if(len p.repl == 0 || p.repl[0] == nil)	# can happen for screens
		return;
	e: string;
	d:= sys->nulldir;
	d.mtime = now();
	for(i := 0; i < len p.repl; i++){
		r := p.repl[i];
		if(r != nil){
			(pid, rid, nil) := qid2ids(r.dirq);
			if(!p.container){
				dataf := mkqid(pid, rid, Qdata);
				d.qid.vers = p.evers;
				d.length = big len p.data;
				fwstat(dataf, d); # ignore errors
			}
			if(p.editions){
				editsf := mkqid(pid, rid, Qedits);
				d.qid.vers = len p.edits;
				d.length = big len p.edits;
				fwstat(editsf, d);
			}
			d.qid.vers = r.cvers;
			d.length = big len p.ctlstr(r); # could cache this
			ctlf := mkqid(pid, rid, Qctl);
			if((e = fwstat(ctlf, d)) != nil)
				continue;	# panel being removed
			d.qid.vers = r.dvers;
			if(d.qid.vers < r.cvers)
				d.qid.vers = r.cvers;
			d.length = (sys->nulldir).length;
			if((e = fwstat(r.dirq, d)) != nil)
				continue;	# panel being removed
		}
	}
}

# order attribute: "order panel1name panel2name panel3name ..."
# This re-assigns replica positions to be unique, contiguous numbers,
# while keeping the order found, and reconstructs the order attribute.
neworder(dr: ref Repl)
{
	childs := pchilds(dr);
	s := "order ";
	old := dr.attrs[Aorder].v;
	for(i := 0; i < len childs; i++){
		for(j := i+1; j < len childs; j++)
			if(childs[j].t1.pos < childs[i].t1.pos){
				t := childs[i];
				childs[i] = childs[j];
				childs[j] = t;
			}
		childs[i].t1.pos = i;
		s += childs[i].t0.name + " ";
	}
	if(old != s){
		vers := ++vgen;
		dr.attrs[Aorder] = (s, vers);
		dr.cvers = vers;
	}
}

# Relocate replica r to be at pos ([0:n])
newreplpos(r: ref Repl, pos: int)
{
	# Renumber all the ones going after so that
	# we get the slot.
	(nil, dr) := pparent(r);
	childs := pchilds(dr);
	if(pos < 0)
		pos = len childs;
	for(i := 0; i < len childs; i++)
		if(childs[i].t1.pos >= pos){
			childs[i].t1.pos++;
		}
	r.pos = pos;
	neworder(dr);
}		

chpos(p: ref Panel, r: ref Repl, pos: int)
{
	if(r.pos == pos)	# nothing to do.
		return;
	newreplpos(r, pos);
	(dp, nil) := pparent(r);
	pchanged(dp);
	dp.vpost(p.pid, "update");
}

mkcol(p: ref Panel, r: ref Repl)
{
	if(!p.container)
		(p, r) = pparent(r);
	if(!p.container)
		panic("mkcol");
	while(r.attrs[Aappl].v != "layout"){
		(pp, rr) := pparent(r);
		if(rr.dirq == slash)
			break;
		if(rr.attrs[Aappl].v == "layout")
			break;
		p = pp;
		r = rr;
	}
	name := sprint("col:user.%d", rand->rand(10000));
	np := pcreate(p, r, name);
	np.ctl(nil, "layout");
}

mktree()
{
	p := Panel.new("col:root");
	r := p.newrepl("/", Trepl);
	fcreate(r.dirq, newdir(".", DMDIR|8r775, r.dirq));
	slash = r.dirq;
	q := mkqid(p.id, r.id, Qolive);
	fcreate(slash, newdir("olive", 8r660, q));
	p = Panel.new("row:apps");
	r = p.newrepl("/appl", Tappl);
	fcreate(slash, newdir("appl", DMDIR|8r775, r.dirq));
	appl = r.dirq;
}

mkscreen(dp: ref Panel)
{
	menu := array[] of {"New"};
	# dp.ctl(nil, "notag");
	ps := pcreate(dp, nil, "row:stats");
	ps.ctl(nil, "layout");
		pc := pcreate(ps, nil, "row:cmds");
		for(i := 0; i < len menu; i++)
			pcreate(pc, nil, "button:" + menu[i]);

	pw := pcreate(dp, nil, "row:wins");
	pw.ctl(nil, "layout");
		c1 := pcreate(pw, nil, "col:1");
		c1.ctl(nil, "layout");
		c2 := pcreate(pw, nil, "col:2");
		c2.ctl(nil, "layout");
}

Dent: adt {
	name:	string;
	mode:	int;
	qtype:	int;
};

dirents: array of Dent;

# creates a replica of p within dr, and its file tree
pcreaterepl(dr: ref Repl, p: ref Panel, sizes: array of int): ref Repl
{
	if(dirents == nil)
		dirents = array[] of {
			Dent("data", 8r660, Qdata),
			Dent("ctl", 8r660, Qctl),
			Dent("edits", 8r660, Qedits),
		};
	path := names->rooted(dr.path, p.name);
	r := p.newrepl(path, dr.tree);
	if(r == nil)
		panic("rcreate: newrepl");
	childs := pchilds(dr);
	r.pos = len childs;
	d := newdir(p.name, DMDIR|8r775, r.dirq);
	vers := r.cvers;
	if(vers < r.dvers)
		vers = r.dvers;
	d.qid.vers = vers;
	fcreate(dr.dirq, d);
	neworder(dr);
	dirvers := array[] of {vers, r.cvers, r.dvers};
	for(i := 0; i < len dirents; i++){
		if(p.container && dirents[i].qtype == Qdata)
			continue;
		if(!p.editions && dirents[i].qtype == Qedits)
			continue;
		q := mkqid(p.id, r.id, dirents[i].qtype);
		dir := newdir(dirents[i].name, dirents[i].mode, q);
		dir.qid.vers = dirvers[i];
		if(sizes != nil)
			dir.length = big sizes[i];
		fcreate(r.dirq, dir);
	}
	return r;
}

# Creates a panel and its tree at (dp, dr)
pcreate(dp: ref Panel, dr: ref Repl, name: string): ref Panel
{
	if(dr == nil)
		dr = dp.repl[0];
	d := dr.dirq;
	uname := name;
	if(d == slash)
		uname = "col:" + name;
	p := Panel.new(uname);
	if(p == nil)
		return nil;
	p.aid = dp.aid;		# inherit from parent
	p.pid = dp.pid;		# inherit from parent
	if(d == slash)
		p.name = name;
	for(i := 0; i < len dp.repl; i++)
		if((dr = dp.repl[i]) != nil){
			r := pcreaterepl(dr, p, nil);
			if(d == slash){
				p.ctl(r, "layout");
				mkscreen(p);
			} else if(d != appl){
				(drp, drr) := pparent(r);
				pchanged(drp);
				if(dr.tree == Trepl)
					post(p.pid, drp, drr, "update");
			}
		}
	return p;
}

# removes a panel including all its replicas when r is the 0-th replica
# only the replica r otherwise. 
# We put p on hold, to deliver just one close.
# If there's only one replica, the application is prepared to behave
# properly when the panel closes. However, if there are more replicas,
# the application won't be notified and we must  remove 
# the innermost non-layout panel containing p, possibly p itself. 
# Consider what happens when closing a text panel after copying
# an o/x column.
premove(p: ref Panel, r: ref Repl)
{
	hold(p);
	if(r.tree == Trepl && p.nrepl > 2)
		for(;;){
			(pp, rr) := pparent(r);
			if(rr.dirq == slash)
				break;
			if(rr.attrs[Aappl].v == "layout")
				break;
			p = pp;
			r = rr;
		}
	_premove(p, r);
	rlse(p);
}

_premove(p: ref Panel, rr: ref Repl)
{
	if(p.container){
		childs := pchilds(rr);
		for(i := 0; i < len childs; i++){
			(cp, cr) := childs[i];
			_premove(cp, cr);
		}
	}
	for(i := 0; i < len p.repl; i++)
		if((r := p.repl[i]) != nil && (r == rr || rr.id == 0)){
			(pp, pr) := pparent(r);
			fremove(r.dirq);	# removes childs as well
			neworder(pr);
			pchanged(pp);
			post(p.pid, p, r, "close");
		}
	if(rr.id == 0)
		p.close();
	else
		p.closerepl(rr);
}


# is f within d?
fwithin(d: big, f: big): int
{
	if(d == f)
		return 1;
	fh := findfile(d);
	if(fh == nil)
		return 0;
	for(cfh := fh.child; cfh != nil; cfh = cfh.sibling){
		if(cfh.d.qid.path == f)
			return 1;
		if(cfh.d.qid.qtype&QTDIR)
		if(fwithin(cfh.d.qid.path, f))
			return 1;
	}
	return 0;
}

movetarget(r: ref Repl, path: string, n: string): (ref Panel, ref Repl, string)
{
	dp: ref Panel;
	dr: ref Repl;

	(pp, pr) := pparent(r);
	if(pr.dirq == slash)
		return (nil, nil, "source is a screen tree");
	if(path == nil)
		(dp, dr) = (pp, pr);
	else {
		dq := fwalk(slash, path);
		if(dq == NOQID)
			return (nil, nil, "no such file: " + path);
		if(fwithin(r.dirq, dq))
			return (nil, nil, "read the GEB first");
		(dpid, drid, nil) := qid2ids(dq);
		(dp, dr) = Panel.lookup(dpid, drid);
		if(fwalk1(dr.dirq, n) != NOQID)
			return (nil, nil, Eexists);
	}
	if(dr.tree == Tappl || dr.dirq == slash)
		return (nil, nil, "target is not a screen tree");
	return (dp, dr, nil);
}

fixmovedrepl(p: ref Panel, r: ref Repl, spath, dpath: string)
{
	rel := names->relative(r.path, spath);
	r.path = rooted(dpath, rel);
	# It's new at its new location. We must forze o/lives
	# to re-read all the subtree.  vgen was already incrtd.
	for(i := 0; i < len r.attrs; i++)
		r.attrs[i].vers = vgen;
	r.dvers = r.cvers = vgen;
	pchanged(p);

	if(p.container){
		childs := pchilds(r);
		for(i = 0; i < len childs; i++){
			(cp, cr) := childs[i];
			fixmovedrepl(cp, cr, spath, dpath);
		}
	}
}

moveto(p: ref Panel, r: ref Repl, path: string, pos: int): string
{
	if(r.tree == Tappl && len p.repl > 1)
		r = p.repl[1];
	if(r.tree == Tappl)
		return "moveto: not from within /appl tree";
	(dp, dr, e) := movetarget(r, path, p.name);
	if(e != nil)
		return e;
	post(p.pid, p, r, "close");

	(pp, pr) := pparent(r);
	fdetach(r.dirq);
	neworder(pr);

	fattach(dr.dirq, r.dirq);
	childs := pchilds(dr);
	r.pos = len childs;
	neworder(dr);		# double-check
	newreplpos(r, pos);

	fixmovedrepl(p, r, pr.path, dr.path);

	pchanged(p);
	pchanged(dp);
	pchanged(pp);
	dp.vpost(p.pid, "update");
	return nil;
}

_copyto(nil: ref Panel, dr: ref Repl, p: ref Panel, r: ref Repl): ref Repl
{
	sizes := array[3] of int;
	sizes[0] = len p.data;
	sizes[1] = len p.ctlstr(p.repl[0]);
	sizes[2] = 0;
	nr := pcreaterepl(dr, p, sizes);
	if(p.container){
		childs := pchilds(r);
		for(i := 0; i < len childs; i++){
			(cp, cr) := childs[i];
			_copyto(p, nr, cp, cr);
		}
		nr.attrs[Aorder].v = r.attrs[Aorder].v;
	}
	return nr;
}

copyto(p: ref Panel, r: ref Repl, path: string, pos: int): string
{
	(dp, dr, e) := movetarget(r, path, p.name);
	if(e != nil)
		return e;
	nr := _copyto(dp, dr, p, r);
	newreplpos(nr, pos);
	pchanged(dp);
	pchanged(p);
	dp.vpost(p.pid, "update");
	return nil;
}

hashfn(q: big, n: int): int
{
	h := int (q % big n);
	if(h < 0)
		h += n;
	return h;
}

findfile(q: big): ref Fholder
{
	for(fh := fstab[hashfn(q, len fstab)]; fh != nil; fh = fh.hash)
		if(fh.d.qid.path == q)
			return fh;
	return nil;
}

fgetpath(q: big): string
{
	fh := findfile(q);
	if(fh == nil)
		return nil;
	if(fh.parentqid == fh.d.qid.path)
		return "/";
	s: string;
	for(;;) {
		if(s == nil)
			s = fh.d.name;
		else if(fh.parentqid == fh.d.qid.path)
			return "/" + s;
		else
			s = fh.d.name + "/" + s;
		fh = findfile(fh.parentqid);
		if(fh == nil)
			panic("fgetpath:parent not in table");
	}
	return nil;
}

fwalk(f: big, path: string): big
{
	els := elements(path);
	if(hd els != "/")
		panic("fwalk: relative path");
	for(els = tl els; els != nil && f != NOQID; els = tl els)
		f = fwalk1(f, hd els);
	return f;
}

fwalk1(q: big, name: string): big
{
	fh := findfile(q);
	if(fh == nil)
		return NOQID;
	if(name == "..")
		return fh.parentqid;
	for(fh = fh.child; fh != nil; fh = fh.sibling)
		if(fh.d.name == name)
			return fh.d.qid.path;
	return NOQID;
}


# detach f from parent. But keep on table. to move it around.
fdetach(f: big)
{
	fh := findfile(f);
	if(fh == nil)
		panic("fdetach: nil fh");
	parent := findfile(fh.parentqid);
	if(parent == nil)
		panic("fdetach: nil parent");
	_fdetach(fh, parent);
}

_fdetach(fh: ref Fholder, parent: ref Fholder)
{
	prev: ref Fholder;

	if(parent != nil) {
		prev = nil;
		for(sfh := parent.child; sfh != nil; sfh = sfh.sibling) {
			if(sfh == fh)
				break;
			prev = sfh;
		}
		if(sfh == nil)
			panic("fdetach: child not found in parent");
		if(prev == nil)
			parent.child = fh.sibling;
		else
			prev.sibling = fh.sibling;
	}
	fh.sibling = nil;
	fh.parentqid = NOQID;
}

fattach(d: big, f: big)
{
	parent := findfile(d);
	if(parent == nil)
		panic("fattach: no parent");
	fh := findfile(f);
	if(fh == nil)
		panic("fattach: no fh");
	fh.parentqid = d;
	# Attach at the end, so new panels show up last
	if(parent.child == nil)
		parent.child = fh;
	else {
		for(sf := parent.child; sf.sibling != nil; sf = sf.sibling)
			;
		sf.sibling = fh;
		fh.sibling = nil;
	}
}

fremove(q: big): string
{
	prev: ref Fholder;

	# remove from hash table
	slot := hashfn(q, len fstab);
	for(fh := fstab[slot]; fh != nil; fh = fh.hash) {
		if(fh.d.qid.path == q)
			break;
		prev = fh;
	}
	if(fh == nil)
		return Enotfound;
	if(prev == nil)
		fstab[slot] = fh.hash;
	else
		prev.hash = fh.hash;
	fh.hash = nil;

	# remove from parent's children
	parent := findfile(fh.parentqid);
	_fdetach(fh, parent);

	# now remove any descendents
	sibling: ref Fholder;
	for(sfh := fh.child; sfh != nil; sfh = sibling) {
		sibling = sfh.sibling;
		sfh.parentqid = sfh.d.qid.path;	# make sure it doesn't disrupt things.
		fremove(sfh.d.qid.path);
	}
	return nil;
}

fcreate(q: big, d: Sys->Dir): string
{
	if(findfile(d.qid.path) != nil)
		return Eexists;
	# allow creation of a root directory only if its parent is itself
	parent := findfile(q);
	if(parent == nil && d.qid.path != q)
		return Enotfound;
	fh: ref Fholder;
	if(parent == nil)
		fh = ref Fholder(q, d, nil, nil, nil);
	else {
		if(fwalk1(q, d.name) != NOQID)
			return Eexists;
		fh = ref Fholder(parent.d.qid.path, d, nil, nil, nil);
		# Attach at the end, so new panels show up last
		if(parent.child == nil)
			parent.child = fh;
		else {
			for(sf := parent.child; sf.sibling != nil; sf = sf.sibling)
				;
			sf.sibling = fh;
		}
	}
	fh.d.mtime = now();
	slot := hashfn(d.qid.path, len fstab);
	fh.hash = fstab[slot];
	fstab[slot] = fh;
	return nil;
}

tabs : con "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";

dumptree(fh: ref Fholder, t: int): int
{
	n := 1;
	q := fh.d.qid.path;
	fprint(stderr, "%s%08bx %d\t%s\n", tabs[0:t], q, fh.d.qid.vers, fgetpath(q));
	for(fh = fh.child; fh != nil; fh = fh.sibling)
		n += dumptree(fh, t+1);
	return n;
}

dumphash(): int
{
	n:= 0;
	for(i := 0; i < len fstab; i++)
		for(fh := fstab[i]; fh != nil; fh = fh.hash){
			n++;
			#q := fh.d.qid.path;
			# fprint(stderr, "%s%08bx\t%s\n", tabs[0:t], q, fgetpath(q));
		}
	return n;
}

dump()
{
	fh := findfile(slash);
	if(fh == nil)
		panic("file not in tree");
	n := dumptree(fh, 0);
	m := dumphash();
	fprint(stderr, "%d in tree %d in hash\n", n, m);
}

fwstat(q: big, d: Sys->Dir): string
{
	fh := findfile(q);
	if(fh == nil){
		if(debug)
			fprint(stderr, "fwstat: qid %08bx not found\n", q);
		return Enotfound;
	}
	d = applydir(d, fh.d);

	# We don't allow renames
	if(d.name != nil && d.name != fh.d.name)
		return "renames not allowed";
	fh.d = d;
	fh.d.qid.path = q;	# ensure the qid can't be changed
	return nil;
}

applydir(d: Sys->Dir, onto: Sys->Dir): Sys->Dir
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
