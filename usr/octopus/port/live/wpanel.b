implement Wpanel;
include "mods.m";
mods, debug, win, tree: import dat;

Menu: import menus;
Cpointer, Tagwid, Taght, Inset, setcursor, drawtag,
getfont, readsnarf, cookclick, Arrow, Drag: import gui;

# Panel polymorphism support.


#  Panels are only drawn due to user interaction or updates made.
#  That happens always from the o/mero tree process.
#  Write and update (data/ctl) routines do not need to draw,
#  Once the whole tree is updated, we call draw for those that must
#  be redrawn.

panels:	list of Pimpl;
ctlc: chan of (ref Panel, list of string, chan of int);
datac: chan of (ref Panel, array of byte, chan of int);

init(d: Livedat, dir: string, ucc: chan of (ref Panel, list of string, chan of int),
	udc: chan of (ref Panel, array of byte, chan of int))
{
	dat = d;
	ctlc = ucc;
	datac = udc;
	initmods();
	fd := open(dir, OREAD);
	if(fd == nil)
		error(sprint("can't open %s: %r", dir));
	(dirs, n) := readdir->readall(fd, Readdir->NONE);
	if(n < 0)
		error(sprint("reading %s: %r", dir));
	panels = nil;
	for(i := 0; i < n; i++){
		nm := dirs[i].name;
		l := len nm;
		if(l > 7 && nm[0:3] == "owp" && nm[l-4:] == ".dis"){
			path := dir + "/" + nm;
			if(debug['P'])
				fprint(stderr, "loading %s\n", path);
			m := load Pimpl path;
			if(m == nil)
				fprint(stderr, "%s: %r\n", path);
			else if((e := m->init(d)) != nil)
				fprint(stderr, "%s: %s\n", path, e);
			else
				panels = m :: panels;
		}
	}
	if(debug['d'] || debug['P'])
		fprint(stderr, "%d panels loaded\n", len panels);
}

screenname(s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == ':')
			return 0;
	return 1;
}

addchild(fp: ref Panel, p: ref Panel)
{
	n := len fp.child;
	child := array[n + 1] of ref Panel;
	child[0:] = fp.child;
	child[n] = p;
	fp.child = child;
	p.parent = fp;
}


nullpanel: Panel;
Panel.new(n: string, fp: ref Panel): ref Panel
{
	pname := n;
	if(screenname(n))
		pname = "row:" + n;
	for(l := panels; l != nil; l = tl l){
		m := hd l;
		for(prefs := m->prefixes; prefs != nil; prefs = tl prefs){
			pl := len hd prefs;
			if(len pname > pl && pname[0:pl]  == hd prefs){
				p := ref nullpanel;
				p.impl = m;
				p.name = n;
				if(fp != nil){
					addchild(fp, p);
					p.path = names->rooted(fp.path, n);
					if(fp.flags&Ptag)
						p.depth = fp.depth + 1;
					else
						p.depth = fp.depth;
				}
				p.rowcol = Qatom;
				p.init();
				p.flags |= Predraw;
				if(debug['P'])
					fprint(stderr, "o/live: new %s\n", p.path);
				return p;
			}
		}
	}
	return nil;
}

Panel.text(p: self ref Panel): string
{
	flags := "";
	if(p.flags&Phide) flags += "Hi";
	if(p.flags&Playout) flags += "La";
	if(p.flags&Pedit) flags += "Ed";
	if(p.flags&Ptag) flags += "Tg";
	if(p.flags&Pmore) flags += "Mr";
	if(p.flags&Pdirty) flags += "Di";
	if(p.flags&Pdirties) flags += "Ds";
	if(p.flags&Pline) flags += "Ln";
	if(p.flags&Ptbl) flags += "Tb";
	if(p.flags&Predraw) flags += "Dr";
	if(p.flags&Pdead) flags += "De";
	if(p.flags&Pbusy) flags += "Bu";
	if(p.flags&Pshown)flags += "Sh";
	s := sprint("%s row=%d, flags %s\t%d childs %d shown", p.name, p.rowcol, flags, len p.child, p.nshown);
	return s;
}

Panel.fsctl(p: self ref Panel, s: string, async: int): int
{
	return p.fsctls(list of {s}, async);
}

Panel.fsctls(p: self ref Panel, l: list of string, async: int): int
{
	c: chan of int;
	if(!async)
		c = chan of int;
	ctlc <-= (p, l, c);
	if(!async)
		return <-c;
	return 0;
}

Panel.fsdata(p: self ref Panel, d: array of byte, async: int): int
{
	c: chan of int;
	if(!async)
		c = chan of int;
	datac <-= (p, d, c);
	if(!async)
		return <-c;
	return 0;
}

Panel.init(p: self ref Panel)
{
	if(p.impl == nil)
		panic("nil panel implementation");
	p.impl->pinit(p);
	p.flags |= Predraw;
}

Panel.term(p: self ref Panel)
{
	p.flags = Pdead;	# safety; and clear Pshown
	if(debug['P'])
		fprint(stderr, "o/live: gone %s\n", p.path);
	p.impl->pterm(p);
}

# Process control operation, during update.
# Data is guaranteed to be updated. This is the update for ctl.
Panel.ctl(p: self ref Panel, s: string)
{
	p.impl->pctl(p, s);
}

# update panel data, during update
Panel.update(p: self ref Panel, d: array of byte)
{
	p.impl->pupdate(p, d);
}

# For panels that require incremental changes.
# Currently text ins/del/edend events only.
Panel.event(p: self ref Panel, s: string)
{
	p.impl->pevent(p, s);
}

Panel.draw(p: self ref Panel)
{
	if(p.flags&Pshown)
		p.impl->pdraw(p);
}

Panel.mouse(p: self ref Panel, m: ref Cpointer, cm: chan of ref Cpointer)
{
	p.impl->pmouse(p, m, cm);
}

Panel.kbd(p: self ref Panel, r: int)
{
	p.impl->pkbd(p, r);
}

intag(p: ref Panel, xy: Point): int
{
	ht := Taght;
	if(p.flags&Pmore)
		ht += Taght;
	r := Rect(p.rect.min, (p.rect.min.x+Tagwid, p.rect.min.y+ht));
	return r.contains(xy);
}

nth(l: list of string, n: int): string
{
	for(i := 0; l != nil && i < n; i++)
		l = tl l;
	if(l != nil)
		return hd l;
	return nil;
}

