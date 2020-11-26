# This module handles data for panels, including attributes.
# It is not responsible for maintaining the tree and does not update qid.vers fields.
# that's done by the file server code, in mero.b, with help from merotree.

# The main panel logic is kept here. We load all mero panel modules found,
# and link to their impl. Updating of data/ctl, and panel type checking is performed
# by delegation to panel implementations loaded. Common attributes and data handling
# is managed here.

implement Panels;
include "sys.m";
	sys: Sys;
	sprint, open, OREAD, fprint: import sys;
include "styx.m";
include "styxservers.m";
	Styxserver: import Styxservers;
include "daytime.m";
include "lists.m";
include "dat.m";
	dat: Dat;
	vgen, mnt, debug, appl, slash: import dat;
include "string.m";
	str: String;
	splitl, take, drop: import str;
include "names.m";
	names: Names;
	dirname: import names;
include "error.m";
	err: Error;
	kill, checkload, error, panic, stderr: import err;
include "readdir.m";
	readdir: Readdir;
include "tbl.m";
	tbl: Tbl;
	Table: import tbl;
include "blks.m";
include "merop.m";
include "merotree.m";
include "merocon.m";
	merocon: Merocon;
	post: import merocon;
include "mpanel.m";

panels : ref Table[ref Panel];

pgen := 0;	# Panel id generator, for qids and hash values

Impl: adt {
	prefs: list of string;
	mod: Pimpl;
};

impls: list of ref Impl;

dupwarn(prefs: list of string)
{
	for(pl := prefs; pl != nil; pl = tl pl){
		x := findimpl(hd pl);
		if(x != nil)
			fprint(stderr, "o/mero: dup panel implementation: %s\n", hd pl);
	}
}

init(d: Dat, dir: string)
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	names = dat->names;
	merocon = dat->merocon;
	tbl = dat->tbl;
	readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	np: ref Panel;
	panels = Table[ref Panel].new(101, np);
	fd := open(dir, OREAD);
	if(fd == nil)
		error(sprint("can't open %s: %r", dir));
	(dirs, n) := readdir->readall(fd, Readdir->NONE);
	if(n < 0)
		error(sprint("reading %s: %r", dir));
	impls = nil;
	for(i := 0; i < n; i++){
		nm := dirs[i].name;
		l := len nm;
		prefs: list of string;
		if(l > 7 && nm[0:3] == "omp" && nm[l-4:] == ".dis"){
			path := dir + "/" + nm;
			if(debug)
				fprint(stderr, "loading %s\n", path);
			m := load Pimpl path;
			if(m == nil)
				fprint(stderr, "%s: %r\n", path);
			else if((prefs = m->init(d)) == nil)
				fprint(stderr, "%s: panel init failed\n", path);
			else {
				dupwarn(prefs);
				impls = ref Impl(prefs, m) :: impls;
			}
		}
	}
	if(debug)
		fprint(stderr, "%d panels loaded\n", len impls);
}

dump()
{
	fprint(stderr, "o/mero panels:\n");
	for(i := 0; i < len panels.items; i++){
		for(pl := panels.items[i]; pl != nil; pl = tl pl){
			(nil, p) := hd pl;
			fprint(stderr, "%s\n", p.text());
		}
	}
}

# debugging
Panel.text(p: self ref Panel): string
{
	if(p == nil)
		return "<nil>\n";
	s := sprint("panel %d:\tcontainer=%d", p.id, p.container);
	for(i := 0; i < len p.repl; i++)
		if((r := p.repl[i]) != nil)
			s += sprint("\n    r%d:\tdv%d cv%d\t appl=%d path='%s'",
				r.id, r.dvers, r.cvers, r.tree, r.path);
	return s;
}

Panel.ok(p: self ref Panel)
{
	if(p.impl == nil)
		panic("no impl");
	if(len p.repl > 0 && p.repl[0] == nil)
		panic("null repl 0");
	for(i := 0; i < len p.repl; i++)
		if(p.repl[i] != nil&& p.repl[i].id != i)
			panic("bad repl index");
}

findimpl(name: string): ref Impl
{
	for(pl := impls; pl != nil; pl = tl pl){
		impl := hd pl;
		for(nl := impl.prefs; nl != nil; nl = tl nl){
			pref := hd nl;
			l := len pref;
			if(len name >= l && name[0:l] == pref)
				return impl;
		}
	}
	return nil;
}

nullpanel: Panel;
Panel.new(name: string): ref Panel
{
	i := findimpl(name);
	if(i == nil){
		if(debug)
			fprint(stderr, "o/mero: bad panel type %s\n", name);
		return nil;
	}
	p := ref nullpanel;
	p.id = pgen++;
	p.name = name;
	p.impl = i.mod;
	p.impl->pinit(p);
	if(panels.add(p.id, p) < 0)
		panic("dup panel id");
	if(debug)
		fprint(stderr, "o/mero: new panel %s\n", p.name);
	return p;
}

Panel.lookup(id: int, rid: int): (ref Panel, ref Repl)
{
	p := panels.find(id);
	r : ref Repl;
	if(p != nil){
		p.ok();
		if(rid >= 0 && rid <len p.repl)
			r = p.repl[rid];
	}
	return (p, r);
}

# Qids are made of <panelid><replnb><type>. (32, 16, and 8 bits)
# They are assigned by Panel.newrepl as replicas are being created.
mkqid(id, rid, t: int): big
{
	q := big id;
	q <<= 24;
	q |= big ((rid&16rFFFF)<<8);
	q |= big (t&16rFF);
	return q;
}

qid2ids(q: big): (int, int, int)
{
	t := int (q & big 16rFF);
	q >>= 8;
	rid := int (q & big 16rFFFF);
	q >>= 16;
	id := int (q & big 16rFFFFFFFF);
	return (id, rid, t);
}

Panel.newrepl(p: self ref Panel, path: string, t: int): ref Repl
{
	l := len p.repl;

	p.ok();
	for(i := 0; i < l; i++)
		if(p.repl[i] == nil)
			break;
	if(i == l){
		nr := array[l+3] of ref Repl;
		nr[0:] = p.repl;
		p.repl = nr;
	}
	q := mkqid(p.id, i, Qdir);
	vers := ++vgen;
	if(vers <= 0)
		fprint(stderr, "o/mero: vgen overflow\n");
	attrs := array[] of { ("notag", vers), ("show", vers), ("appl 0 -1", vers)};
	r := ref Repl(i, 0, 0, 0, t, path, q, attrs);
	p.nrepl++;
	p.repl[i] = r;
	if(r.id == 0){
		p.impl->rinit(p, r);
	} else {
		r.attrs = array[len p.repl[0].attrs] of Attr;
		r.attrs[0:] = p.repl[0].attrs;
	}
	for(i = 0; i < len r.attrs; i++)
		r.attrs[i].vers = vers;
	r.cvers = r.dvers = vers;
	return r;
}

Panel.close(p: self ref Panel)
{
	if(debug)
		fprint(stderr, "o/mero: close panel %s\n", p.name);
	for(i := 1; i < len p.repl; i++)
		if((r := p.repl[i]) != nil)
			p.closerepl(r);
	if(p.repl[0] != nil)
		p.closerepl(p.repl[0]);
	x := panels.del(p.id);
	if(x != p)
		panic("Panel.close: bug");
}

Panel.closerepl(p: self ref Panel, r: ref Repl)
{
	p.ok();
	if(p.repl[r.id] != r)
		panic("Panel.closerepl: bug");
	p.repl[r.id] = nil;
	p.nrepl--;
	if(r.id != 0 && p.nrepl == 1)
		p.post("close");
}

Panel.post(p: self ref Panel, s: string)
{
	post(p.pid, p, p.repl[0], s);
}

Panel.vpost(p: self ref Panel, pid: int, s: string)
{
	for(i := 0; i < len p.repl; i++)
		if(p.repl[i] != nil && p.repl[i].tree == Trepl)
			post(pid, p, p.repl[i], s);
}

Panel.put(p: self ref Panel, data: array of byte, off: big): (int, string)
{
	if(data == nil){
		p.data = array[0] of byte;
		return (-1, "null data");
	}
	o := int off;
	max := o + len data;
	if(max > 64 * 1024 * 1024)
		return (-1, "max data size exceeded");
	if(max > len p.data){
		ndata := array[max] of byte;
		ndata[0:] = p.data;
		ndata[o:] = data;
		p.data = ndata;
	} else if(len p.data == 0)
		p.data = data;
	else
		p.data[o:] = data;
	return (len data, nil);
}

Panel.newvers(p: self ref Panel)
{
	++vgen;
	if(vgen <= 0)
		fprint(stderr, "o/mero: vgen overflow; use a big\n");
	p.evers++;
	for(i := 0; i < len p.repl; i++){
		r := p.repl[i];
		if(r != nil)
			r.dvers = vgen;
	}
}

Panel.newdata(p: self ref Panel): string
{
	e := p.impl->newdata(p);
	if(e != nil){
		p.data = array[0] of byte;
		p.edits = "";
	}
	return e;
}

# ins may contain spaces in its argument, and requires careful
# processing here.
mkinsargs(ctl: string): list of string
{
	tag, vers, pos: string;

	ctl = drop(ctl, " \t");
	if(len ctl < 3)		# ins
		return nil;
	if(ctl[0:3] != "ins")
		return nil;
	ctl = ctl[3:];

	ctl = drop(ctl, " \t");
	(tag, ctl) = splitl(ctl, " \t");	# tag
	if (len tag == 0)
		return nil;

	ctl = drop(ctl, " \t");
	(vers, ctl) = splitl(ctl, " \t");	# vers
	if (len vers == 0)
		return nil;

	ctl = drop(ctl, " \t");
	(pos, ctl) = splitl(ctl, " \t");	# pos
	if (len pos == 0)
		return nil;

	if(len ctl == 0 || (ctl[0] != ' ' && ctl[0] != '\t'))
		return nil;
	return list of {"ins", tag, vers, pos, ctl[1:] };
}

Panel.ctl(p: self ref Panel, r: ref Repl, ctl: string): (int, string, string)
{
	if(r == nil)
		r = p.repl[0];
	(nargs, args) := sys->tokenize(ctl, " \t\n");
	if(nargs < 0 || args == nil)
		return (0, "no ctl", nil);
	if(hd args == "ins")
		args = mkinsargs(ctl);
	(n, e, c) := p.impl->ctl(p, r, args);
	if(e == nil || e != "not mine")
		return (n, e, c);
	i := -1;
	argl := global := 1;
	case hd args {
	"interrupt" =>
		if(p.pid != -1)
			kill(p.pid, "killgrp");
	"tag" or "notag" =>
		i = Atag;
	"show" or "hide" =>
		i = Ashow; global = 0;
	"layout" =>
		i = Aappl; global = 0;
	"appl" =>
		argl = 3;
		i = Aappl; global = 0;
	* =>
		return (0, "no such attribute", nil);
	}
	if(nargs != argl)
		return (0, sprint("%d arguments needed", argl -1), nil);
	if(i == Aappl && argl == 3){
		p.aid = int hd tl args;
		p.pid = int hd tl tl args;
	}
	return p.setattr(r, i, global, ctl);
}

# Even the same replica that caused the ctl must get the update for global attrs,
# otherwise, other viewers showing the same replica won't be updated.
Panel.setattr(p: self ref Panel, r: ref Repl, id, glob: int, v: string): (int, string, string)
{
	r.attrs[id].v = v;
	vers := ++vgen;
	if(vgen <= 0)
		fprint(stderr, "o/mero: vgen overflow; use a big\n");
	p.repl[0].attrs[id] = (r.attrs[id].v, vers);
	p.repl[0].cvers = vers;
	if(r.id == 0 || glob){
		r.attrs[id].vers = vers;
		for(rn := 0; rn < len p.repl; rn++)
			if((pr := p.repl[rn]) != nil){
				pr.attrs[id] = p.repl[0].attrs[id];
				pr.cvers = vers;
			}
		return (1, nil, nil);
	} else
		return (0, nil, nil);

}

chkargs(ctl: list of string, argl: list of (string, int)): string
{
	l := len ctl;
	for(; argl != nil; argl = tl argl)
		if((hd argl).t0 == hd ctl)
			if((hd argl).t1 == 0 || l == (hd argl).t1)
				return nil;
			else
				return sprint("%d args needed", l-1);
	return "not mine";
}


Repl.ctlstr(r: self ref Repl, vers: int): string
{
	s := "";
	for(i := 0; i < len r.attrs; i++)
		if(r.attrs[i].v != nil)
		if(vers == -1 || r.attrs[i].vers > vers)
			s += r.attrs[i].v + "\n";
	return s;
}

# Attributes == actual attributes + copytos
Panel.ctlstr(p: self ref Panel, r: ref Repl): string
{
	p.ok();
	s := r.ctlstr(-1);
	if(r.id == 0)
		for(i := 0; i < len p.repl; i++)
			if(p.repl[i] != nil && p.repl[i].tree != Tappl){
				path := dirname(p.repl[i].path);
				path = path[1:];	# remove '/'
				s += sprint("copyto %s\n", path);
			}
	return s;
}


escape(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == '\n')
			s[i] = 1;
	return s;
}

unescape(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == 1)
			s[i] = '\n';
	return s;
}
