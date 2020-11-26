implement Pimpl;
include "mods.m";
mods, debug, win, tree: import dat;

Qrow, Qcol, Pmore, Phide, Ptag, Pshown, Predraw, Pdirties, Pinsist, Pfocus,
Playout, Pdirty, intag, Pjump, Panel: import wpanel;
Bback, Cpointer, Taght,
bord, drawtag, Tagwid, Inset, terminate, borderkind, lastxy, panelback: import gui;
panelctl, panelkbd, panelmouse, tagmouse, More, Max, Full, Tree: import wtree;

Prowcol: adt {
	nwins:	int;
};

panels: array of ref Prowcol;

pimpl(p: ref Panel): ref Prowcol
{
	if(p.implid < 0 || p.implid > len panels || panels[p.implid] == nil)
		panic("rowcol: bug: no impl");
	return panels[p.implid];
}

init(d: Livedat): string
{
	prefixes = list of {"row:", "col:"};
	dat = d;
	initmods();
	return nil;
}

pinit(p: ref Panel)
{
	if(tree == nil)
		tree = dat->tree;
	if(len p.name > 4 && p.name[0:4] == "row:")
		p.rowcol = Qrow;
	else
		p.rowcol = Qcol;
	for(i := 0; i < len panels; i++)
		if(panels[i] == nil)
			break;
	if(i == len panels){
		npanels := array[i+16] of ref Prowcol;
		npanels[0:] = panels;
		panels = npanels;
	}
	p.implid = i;
	panels[i] = ref Prowcol(0);
}

pterm(p: ref Panel)
{
	if(p.implid != -1){
		pimpl(p);	# check
		panels[p.implid] = nil;
		p.implid = -1;
	}
}

updatemoreflag(p: ref Panel)
{
	p.flags &= ~Pmore;
	for(i := 0; i < len p.child; i++)
		if(p.child[i].flags&Phide){
			p.flags |= Pmore;
			return;
		}
	pi := pimpl(p);
	pi.nwins = 0;
}

pctl(p: ref Panel, s: string)
{
	panelctl(tree, p, s);
}


pupdate(nil: ref Panel, nil: array of byte)
{
	# nothing to do for row/col
}

pevent(nil: ref Panel, nil: string)
{
	# no events for row/col
}

pdraw(p: ref Panel)
{
	if(!(p.flags&Pshown))
		return;
	k := borderkind(p);
	cback := panelback(p);
	has := (p.flags&Ptag);
	dirty := (p.flags&Pdirty);
	r := p.rect.inset(Inset);
	if(has)
		r.min.x += Tagwid;

	max := Point(0, 0);
	last := 0;
	focus := 0;
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		npr := np.rect;
		nr := npr;
		dirty |= np.flags&Pdirty;
		focus |= np.flags&Pfocus;
		if(np.flags&Phide)
			continue;
		if(npr.dx() == 0 || npr.dy() == 0) # did not have room. ignore.
			continue;
		#clear space unused by component.
		max = npr.max;
		if(debug['L'] > 1)
			fprint(stderr, "\tnpr [%d %d %d %d]\n",
			npr.min.x, npr.min.y, npr.max.x, npr.max.y);
		if(p.rowcol == Qcol){
			nr.min.x = npr.max.x;
			nr.max.x = r.max.x;
		} else {
			nr.min.y = npr.max.y;
			nr.max.y = r.max.y;
		}
		win.image.draw(nr, cback, nil, (0,0));
		if(last != 0){
			# clear separator from previous component
			nr = r;
			if(p.rowcol == Qcol){
				nr.min.y = last;
				nr.max.y = nr.min.y + Inset;
			} else {
				nr.min.x = last;
				nr.max.x = nr.min.x + Inset;
			}
			win.image.draw(nr, cback, nil, (0,0));
		}
		if(p.rowcol == Qcol)
			last = np.rect.max.y;
		else
			last = np.rect.max.x;
	}

	if(max.x != 0 || max.y != 0){
		# Clear unused space at end of components
		nr := r;
		if(p.rowcol == Qcol)
			nr.min.y = max.y;
		else
			nr.min.x = max.x;
		win.image.draw(nr, cback, nil, (0,0));
	} else {
		# no inner component. clear all space.
		win.image.draw(r, cback, nil, (0,0));
	}
	# blank space at left margin
	r = p.rect;
	r.max.x = r.min.x + Inset;
	if(has){
		r.min.y += Taght;
		if(p.flags&Pmore)
			r.min.y += Taght;
		r.max.y--;
		r.max.x += Tagwid;
		r.min.x++;
	}
	win.image.draw(r, bord[Bback][k], nil, (0,0));
	if(has){
		# there's an Inset wide rect. to the right of tag.
		r = p.rect;
		r.max.x = r.min.x + Inset + Tagwid;
		r.min.x += Tagwid;
		r.max.y = r.min.y + Taght;
		if(p.flags&Pmore)
			r.max.y += Taght;
		win.image.draw(r, bord[Bback][k], nil, (0,0));
	}

	# blank space at right margin
	r = p.rect;
	r.min.x = r.max.x - Inset;
	if(has){
		r.min.y++;
		r.max.y--;
		r.max.x--;
	}
	win.image.draw(r, bord[Bback][k], nil, (0,0));

	# blank space at top margin
	r = p.rect;
	r.max.y = r.min.y + Inset;
	r.max.x -= Inset;
	r.min.x += Inset;
	if(has){
		r.min.x += Tagwid;
		r.min.y++;
	}
	win.image.draw(r, bord[Bback][k], nil, (0,0));

	# blank space at bottom margin
	r = p.rect;
	r.min.y = r.max.y - Inset;
	r.max.x -= Inset;
	r.min.x += Inset;
	if(has){
		r.min.x += Tagwid;
		r.max.y--;
	}
	win.image.draw(r, bord[Bback][k], nil, (0,0));

	# border and tag
	bc := gui->cols[gui->BORD];
	if(p.flags&Playout)
		bc = gui->cols[gui->TEXT];
	if(focus)
		bc = gui->cols[gui->FBORD];
	win.image.border(p.rect, 1, bc, (0,0));
	if(has)
		drawtag(p);

}

pmouse(p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	if(p.flags&Ptag)
		tagmouse(tree, p, m, mc);
}

zoomto(p: ref Panel, ndir: string)
{
	tree.layout(tree.walk(ndir), 0);
	pt := p.rect.min.add((Tagwid/2, Taght/2));
	win.wmctl("ptr " + string pt.x + " " + string pt.y);
}

shl(p: ref Panel)
{
	# Take first in "order"
	# Out of tree, anyone could be moving things around.
	cc := p.child;
	if(len cc < 2)
		return;
	cp := cc[0];
	if(cp != nil)
		cp.fsctl(sprint("pos %d", len cc), 0);
}

shr(p: ref Panel)
{
	# Take last in "order"
	# Out of tree, anyone could be moving things around
	cc := p.child;
	if(len cc < 2)
		return;
	cp := cc[len cc - 1];
	if(cp != nil)
		cp.fsctl("pos 0", 0);
}

pkbd(p: ref Panel, r: int)
{
	Killchar:	con 16r08;

	case r {
	Keyboard->Up =>
		if(debug['E'])
			fprint(stderr, "o/live: rowcol up\n");
		if(intag(p, lastxy()))
			tree.size(p, Full);
		else
			shl(p);
		p.flags |= Pjump;
		tree.tags();
		tree.layout(nil, 0);
	Keyboard->Down =>
		if(debug['E'])
			fprint(stderr, "o/live: rowcol down\n");
		if(intag(p, lastxy()))
			tree.size(p, More);
		else
			shr(p);
		p.flags |= Pjump;
		tree.tags();
		tree.layout(nil, 0);
	Keyboard->Left =>
		if(debug['E'])
			fprint(stderr, "o/live: rowcol left\n");
		if(tree.slash == tree.dslash)	# top level
			return;
		ndir := tree.path(tree.dslash);
		zoomto(p, names->dirname(ndir));
	Keyboard->Right =>
		if(debug['E'])
			fprint(stderr, "o/live: rowcol right\n");
		if(len p.path <= len tree.dslash.path)
			return;
		dslash := tree.path(tree.dslash);
		ndir := tree.path(p);
		if(dslash != "/")
			ndir = ndir[len dslash:];
		els := names->elements(ndir[1:]);
		if(els == nil)
			return;
		if(dslash != "/")
			ndir = dslash + "/" + hd els;
		else
			ndir = "/" + hd els;
		zoomto(p, ndir);
	'\n' =>
		if(debug['E'])
			fprint(stderr, "o/live: rowcol nl\n");
		if(p == tree.dslash)
			zoomto(p, "/");
		else
			zoomto(p, tree.path(p));
	Keyboard->Del =>
		if(debug['E'])
			fprint(stderr, "o/live: rowcol del\n");
		p.fsctl("interrupt", 1);
	}
}
