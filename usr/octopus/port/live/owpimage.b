implement Pimpl;
include "mods.m";
mods, debug, win, tree: import dat;


Cpointer, cols, panelback, maxpt, cookclick, drawtag, TEXT : import gui;
Ptag, Pedit, Pdead, intag, Predraw, All, Panel: import wpanel;
panelctl, panelkbd, panelmouse, tagmouse, Treeop, Tree: import wtree;

Icache: adt {
	data:	array of byte;
	sum:	int;
	i:	ref Image;

	alloc:	fn(d: array of byte): ref Icache;
	close:	fn(ic: self ref Icache);
};

Pimage: adt {
	ic:	ref Icache;
	off:	Point;	# x/y offset for page
	paging:	int;
};

panels: array of ref Pimage;
images: array of ref Icache;

init(d: Livedat): string
{
	prefixes = list of {"image:", "page:"};
	dat = d;
	initmods();
	panels = array[0] of ref Pimage;
	images = array[0] of ref Icache;
	return nil;
}

samedata(d1, d2: array of byte): int
{
	if(len d1 != len d2)
		return 0;
	for(i := 0; i < len d1; i++)
		if(d1[i] != d2[i])
			return 0;
	return 1;
}

Icache.alloc(d: array of byte): ref Icache
{
	dpy := win.display;
	sum := 0;
	for(i := 0; i < len d; i++)
		sum += int d[i];
	for(i = 0; i < len images ; i++)
		if((ic := images[i]) != nil)
		if(sum == ic.sum && samedata(ic.data, d))
			return ic;
	# not found in cache. install a new entry
	fname := sprint("/tmp/owinimg.%d", sys->pctl(0,nil));
	fd := create(fname, ORDWR|ORCLOSE, 8r644);
	if(fd == nil)
		return nil;
	if(write(fd, d, len d) != len d)
		return nil;
	sys->seek(fd, big 0, 0);
	img := dpy.readimage(fd);
	if(img == nil)
		return nil;
	ic = ref Icache(d, sum, img);
	for(i = 0; i < len images; i++)
		if(images[i] == nil){
			images[i] = ic;
			return ic;
		}
	nimages := array[len images + 1] of ref Icache;
	nimages[0:] = images;
	nimages[len images] = ic;
	images = nimages;
	return ic;
}

Icache.close(ic: self ref Icache)
{
	if(ic != nil){
		for(i := 0; i < len images; i++)
			if(images[i] == ic)
				images[i] = nil;
	}
	# Pimages referencing ic will keep their refs valid
}

pimpl(p: ref Panel): ref Pimage
{
	if(p.implid < 0 || p.implid > len panels || panels[p.implid] == nil)
		panic("image: bug: no impl");
	return panels[p.implid];
}

pinit(p: ref Panel)
{
	if(tree == nil)
		tree = dat->tree;
	for(i := 0; i < len panels; i++)
		if(panels[i] == nil)
			break;
	if(i == len panels){
		npanels := array[i+16] of ref Pimage;
		npanels[0:] = panels;
		panels = npanels;
	}
	p.implid = i;
	panels[i] = ref Pimage(nil, Point(0,0), 0);
	p.minsz = p.maxsz = Point(48, 48);
	p.flags |= Pedit;
	if(len p.name > 5 && p.name[0:6] == "page:"){
		panels[i].paging = 1;
		p.maxsz=Point(All, All);
	}
}

pterm(p: ref Panel)
{
	if(p.implid != -1){
		pimpl(p);	# check
		panels[p.implid] = nil;
		p.implid = -1;
	}
}

pctl(p: ref Panel, s: string)
{
	panelctl(tree, p, s);
}

newlayout()
{
	tree.opc <-= ref Treeop.Layout(nil, 0);
}

pupdate(p: ref Panel, d: array of byte)
{
	pi := pimpl(p);
	if(pi == nil)
		return;
	if(pi.ic != nil && samedata(pi.ic.data, d))
		return;
	ic := pi.ic;
	pi.ic =Icache.alloc(d);
	if(pi.ic == nil){
		pi.ic = ic;
		return;
	}
	oldr := Rect((0,0), (48,48));
	if(ic != nil && ic.i != nil)
		oldr = ic.i.r;
	ic.close();
	pi.off = Point(0,0);
	omin := p.minsz;
	if(pi.paging == 0){
		p.minsz.x = pi.ic.i.r.dx();
		p.minsz.y = pi.ic.i.r.dy();
		p.maxsz = p.minsz;
	}
	p.flags |= Predraw;
	if(!omin.eq(p.minsz))
		spawn newlayout();
}

pevent(nil: ref Panel, nil: string)
{
	# no ins/del events
}

pdraw(p: ref Panel)
{
	pi := pimpl(p);
	if(pi == nil)
		return;
	back := panelback(p);
	ic := pi.ic;
	win.image.draw(p.rect, back, nil, (0,0));
	if(ic != nil) {
		pt := Point(0,0);
		if(pi.paging)
			pt = pi.off;
		pt = ic.i.r.min.add(pt);
		if(pi.paging)
			win.image.draw(p.rect, back, nil, (0,0));
		win.image.draw(p.rect, ic.i, nil, pt);
	}
	if(p.flags&Ptag)
		drawtag(p);
}

ijump(p: ref Panel, pt: Point)
{
	pi := pimpl(p);
	if(pi == nil)
		return;
	if(pt.x < 0)
		pt.x = 0;
	if(pt.y < 0)
		pt.y = 0;
	dy := p.rect.dy();
	diy:= pi.ic.i.r.dy();
	dx := p.rect.dx();
	dix:= pi.ic.i.r.dx();
	pi.off.y = pt.y * diy / dy;
	pi.off.x = pt.x * dix / dx;
	if(pi.off.y < 0)
		pi.off.y = 0;
	if(diy <= dy)
		pi.off.y = 0;
	else if(pi.off.y > diy - dy)
		pi.off.y = diy - dy ;
	if(pi.off.x < 0)
		pi.off.x = 0;
	if(dix <= dx)
		pi.off.x = 0;
	else if(pi.off.x > dix - dx)
		pi.off.x = dix - dx;
}

pmouse(p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	if((p.flags&Ptag) && intag(p, m.xy)){
		tagmouse(tree, p, m, mc);
		return;
	}
	case m.buttons {
	4 =>
		m = <-mc;
		if(p.flags&Pdead)
			return;
		if(m.buttons == 0)
			p.fsctl(sprint("look %s", p.name), 1);
		else {
			while(m.buttons & 4){
				if(p.flags&Pdead)
					return;
				xy := m.xy.sub(p.rect.min);
				ijump(p, xy);
				pdraw(p);
				m = <-mc;
			}
			while(m.buttons != 0)
				m = <-mc;
		}
	2 =>
		if(cookclick(m, mc))
			p.fsctl(sprint("exec %s", p.name), 1);
	}
}

pkbd(p: ref Panel, r: int)
{
	panelkbd(nil, p, r);
}
