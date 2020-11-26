implement Pimpl;
include "mods.m";
mods, debug, win, tree: import dat;

Cpointer, cols, panelback, maxpt, cookclick, drawtag, SET, CLEAR,
HIGH, BORD, TEXT : import gui;
Ptag, Predraw, Pdead, Pedit, Panel: import wpanel;
panelctl, panelkbd, panelmouse, tagmouse, Tree: import wtree;

Pgauge: adt {
	pcent:	int;
	grect:	Rect;
};

panels: array of ref Pgauge;

pimpl(p: ref Panel): ref Pgauge
{
	if(p.implid < 0 || p.implid > len panels || panels[p.implid] == nil)
		panic("gauge: bug: no impl");
	return panels[p.implid];
}


init(d: Livedat): string
{
	prefixes = list of {"gauge:", "slider:"};
	dat = d;
	initmods();
	return nil;
}


pinit(p: ref Panel)
{
	if(tree == nil)
		tree = dat->tree;
	for(i := 0; i < len panels; i++)
		if(panels[i] == nil)
			break;
	if(i == len panels){
		npanels := array[i+16] of ref Pgauge;
		npanels[0:] = panels;
		panels = npanels;
	}
	p.implid = i;
	panels[i] = ref Pgauge(50, Rect((0,0), (120, 20)));
	p.minsz = p.maxsz = Point(120, 20);
	if(p.name[0:7] == "slider:")
		p.flags |= Pedit;
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

pupdate(p: ref Panel, d: array of byte)
{
	s := string d;
	pi := pimpl(p);
	if(pi == nil)
		return;
	npcent := int s;
	if(npcent > 100)
		npcent = 100;
	if(npcent < 0)
		npcent = 0;
	if(npcent != pi.pcent){
		pi.pcent = npcent;
		p.flags |= Predraw;
	}
}

pevent(nil: ref Panel, nil: string)
{
	# no events
}

pdraw(p: ref Panel)
{
	pi := pimpl(p);
	if(pi == nil)
		return;
	set := p.rect;
	loff := set;
	loff.max.x = loff.min.x + 4;
	roff := set;
	roff.min.x = roff.max.x - 4;
	set.min.x += 4;
	set.max.x -= 4;
	if(p.rect.dy() > p.minsz.y){
		dy := p.rect.dy() - p.minsz.y;
		set.min.y += dy/2;
		set.max.y -= dy/2;
	}
	clear := set;
	line  := set;
	pi.grect = set;
	dx := int (set.dx() * pi.pcent / 100);
	clear.min.x = set.max.x = line.max.x = set.min.x + dx;
	line.min.x = line.max.x++ - 1;
	c := Point(line.min.x, (line.max.y+line.min.y)/2);
	cr := Rect((c.x-2, c.y-4), (c.x+4, c.y+4));
	back := panelback(p);

	# draw back rects at left/right (to clear drag tag when 0%/100%)
	win.image.draw(loff, back, nil, (0,0));
	win.image.draw(roff, back, nil, (0,0));
	win.image.draw(set, cols[SET], nil, (0,0));
	win.image.draw(clear,  back, nil, (0,0));
	win.image.draw(line,  cols[BORD], nil, (0,0));
	# draw drag tag only for sliders
	if(p.flags&Pedit)
		win.image.draw(cr, cols[BORD], nil, (0,0));
	win.image.border(pi.grect, 1, cols[BORD], (0,0));
	if(p.flags&Ptag)
		drawtag(p);
}

pmouse(p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	if(panelmouse(tree, p, m, mc))
		return;
	pi := pimpl(p);
	if(pi == nil)
		return;
	oval := nval := pi.pcent;
	if((p.flags&Pedit) && m.buttons == 1){
		do {
			if(p.flags&Pdead)
				return;
			if(m.xy.x < pi.grect.min.x)
				m.xy.x = pi.grect.min.x;
			if(m.xy.x > pi.grect.max.x)
				m.xy.x = pi.grect.max.x;
			d := m.xy.sub(pi.grect.min);
			dx := pi.grect.dx();
			nval = d.x * 100 / dx;
			if(nval != pi.pcent){
				pi.pcent = nval;
				pdraw(p);
			}
			m = <-mc;
		} while(m.buttons&1);
		while(m.buttons != 0)
			m = <-mc;
	}
	if(nval != oval)
		spawn psync(p); # release the mouse
}

pkbd(p: ref Panel, r: int)
{
	panelkbd(nil, p, r);
}

psync(p: ref Panel)
{
	pi := pimpl(p);
	if(pi == nil)
		return;
	if(p.flags&Pedit){
		d := array of byte sprint("%d\n", pi.pcent);
		p.fsdata(d, 1);
	}
}
