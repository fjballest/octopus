implement Layout;
include "mods.m";
mods, debug, win, tree: import dat;

Cpointer, maxpt, Tagwid, Taght, Inset, setcursor, cookclick, Arrow: import gui;
Qcol, Qrow, Qatom, Ptag, Phide, Pshown, Predraw, Playout, All,
Panel: import wpanel;

# This follows conventions from draw. Rectangles do not include their max points.
# Also, as any other heuristic affair, this module will always be work in progress.

init(d: Livedat)
{
	dat = d;
	initmods();
}

# add inner's size to compute column size
addcsz(psize, npsize: Point, addsep: int): Point
{
	if(addsep)
		psize.y += Inset;
	psize.y += npsize.y;
	if(psize.x < npsize.x)
		psize.x = npsize.x;
	return psize;
}
	
# add inner's size to compute row size
addrsz(psize, npsize: Point, addsep: int): Point
{
	if(addsep)
		psize.x += Inset;
	psize.x += npsize.x;
	if(psize.y < npsize.y)
		psize.y = npsize.y;
	return psize;
}

# round sizes to avoid tiny resizes
roundsz(size: Point): Point
{
	Grid: con 10;

	n := size.x%Grid;
	if(n > 0)
		size.x += Grid-n;
	n = size.y%Grid;
	if(n > 0)
		size.y += Grid-n;
	return size;
}


# Recursively compute p.size for all panels and
# determine p.minsz, p.maxsz for containers.
# Also, save previous rect in orect.
# auto requests automatic layout despite previous resizes made by the user.
size(p: ref Panel, auto: int)
{
	p.orect = p.rect;
	if(auto)
		p.resized = 0;
	if(p.resized)
		return;	# do not change size if set by the user.
	case p.rowcol {
	Qcol or Qrow =>
		if(p.flags&Ptag)
			p.size = p.maxsz = p.minsz = Point(Tagwid + Inset, Inset);
		else
			p.size = p.maxsz = p.minsz = Point(Inset, Inset);
		some := 0;
		for(i := 0; i < len p.child; i++){
			np := p.child[i];
			if(np.flags&Phide)
				continue;
			some++;
			size(np, auto);
			if(p.rowcol == Qcol){
				p.size = addcsz(p.size, np.size, some);
				p.minsz = addcsz(p.minsz, np.minsz, some);
				p.maxsz = addcsz(p.maxsz, np.maxsz, some);
			} else {
				p.size = addrsz(p.size, np.size, some);
				p.minsz = addrsz(p.minsz, np.minsz, some);
				p.maxsz = addrsz(p.maxsz, np.maxsz, some);
			}
		}
		if(p.flags&Playout)
			if(some == 0)
				p.maxsz = Point(All, All);
			else if(p.rowcol == Qrow)
				p.maxsz.x = All;
			else
				p.maxsz.y = All;
		p.size = p.size.add(Point(Inset, Inset));
		p.minsz = p.minsz.add(Point(Inset, Inset));
		p.maxsz = p.maxsz.add(Point(Inset, Inset));
		p.size = maxpt(p.size, Point(20, 10));
		p.minsz = maxpt(p.minsz, Point(20, 10));
		p.maxsz = maxpt(p.maxsz, Point(20, 10));
	Qatom =>
		p.size = maxpt(p.minsz, Point(Inset, Inset));
	}
	# avoid tiny resizes:
	p.size = roundsz(p.size);
	p.minsz = roundsz(p.minsz);
	p.maxsz = roundsz(p.maxsz);
	if(debug['L'] > 1)
		dumpsizes(p, "size");
}

packatom(p: ref Panel)
{
	if(p.resized || p.size.x < p.rect.dx())
		p.rect.max.x = p.rect.min.x + p.size.x;
	else
		p.rect.max.x = p.rect.min.x + p.rect.dx();
	if(p.resized || p.size.y < p.rect.dy())
		p.rect.max.y = p.rect.min.y + p.size.y;
	else
		p.rect.max.y = p.rect.min.y + p.rect.dy();
}

move(p: ref Panel, pt: Point)
{
	if(pt.eq((0,0)))
		return;
	p.rect = p.rect.addpt(pt);
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(!(np.flags&Phide))
			move(np, pt);
	}
}

#  Recursively layout the hierarchy to its minimum size.
#  Panel.rect enters with the rectangle available
#  for showing the file and its hierarchy. It leaves
#  the routine with the actual rectangle used or a null one
#  if there's not enough space to show it.
pack(p: ref Panel): int
{
	full := 0;
	case p.rowcol {
	Qcol or Qrow =>
		# r is always the avail rectangle.
		# max is the max. point used.
		r := p.rect.inset(Inset);
		if(p.flags&Ptag)
			r.min.x += Tagwid;
		max := r.min;
		some := 0;
		for(i := 0; i < len p.child; i++){
			np := p.child[i];
			if(np.flags&Phide)
				continue;
			if(np.resized)
				np.rect = Rect(r.min, r.min.add(np.size));
			else
				np.rect = r;
			full |= pack(np);
			(cr, nil) := np.rect.clip(r);
			np.rect = cr;
			if(!r.contains(np.rect.min)){
				# does not fit
				np.rect = Rect((0, 0), (0, 0));
				np.ctl("hide");
				full = 1;
				continue;
			}
			some++;
			max = maxpt(max, np.rect.max);
			if(p.rowcol == Qcol)
				r.min.y = np.rect.max.y + Inset;
			else
				r.min.x = np.rect.max.x + Inset;
		}
		if(p.resized)
			p.rect.max = p.rect.min.add(p.size);
		else
			p.rect.max = max.add(Point(Inset, Inset));
		if(!some)
			packatom(p);
	Qatom =>
		packatom(p);
	}
	if(debug['L'] > 1)
		dumpsizes(p, "pack");
	return full;
}

dumpsizes(p: ref Panel, s: string)
{
	rs := "";
	if(p.resized)
		rs = "RSZ";
	fprint(stderr, "%s\t%-20s:\t%03dx%03d" +
		"\t[%3d %3d %3d %3d]\tmin: %03dx%03d max: %03dx%03d %s\n",
		s, p.name, p.rect.dx(), p.rect.dy(),
		p.rect.min.x, p.rect.min.y,
		p.rect.max.x, p.rect.max.y,
		p.minsz.x, p.minsz.y,
		p.maxsz.x, p.maxsz.y, rs);
}

# determine spare space,
# the number of inner panels wanting more space, and
# the maximum inner panel size
findspare(p: ref Panel): (Point, Point, Point)
{
	nw := max := last := Point(0,0);
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(!(np.flags&Phide) && np.rect.dx() > 0){
			dx := np.rect.dx();
			if(dx > max.x)
				max.x = dx;
			dy := np.rect.dy();
			if(dy > max.y)
				max.y = dy;
			if(np.maxsz.x > np.size.x && !np.resized)
				nw.x++;
			if(np.maxsz.y > np.size.y && !np.resized)
				nw.y++;
			last = np.rect.max;
		}
	}
	# spare can be negative, when the space is not enough.
	spare := p.rect.max.sub(last);
	spare = spare.sub(Point(Inset, Inset));
	return (spare, nw, max);
}

# Use spare space to try to give inner panels
# equal minimun sizes and return the spare space left.
# By now, this is only implemented for rows because
# this is needed mostly to equalize layout columns.
equalize(p: ref Panel, spare, max: Point): Point
{
	if(p.rowcol != Qrow)
		return spare;
	offset := 0;
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(np.flags&Phide || np.rect.dx() == 0)
			continue;
		move(np, Point(offset, 0));
		dx := max.x - np.rect.dx();
		if(np.resized == 0)
		if(dx > 0 && spare.x > 0 && np.maxsz.x > np.size.x){
			incr := dx;
			if(dx > spare.x)
				incr = spare.x;
			np.rect.max.x += incr;
			np.size.x += incr;
			offset += incr;
			spare.x -= incr;
		}
		if(debug['L'] > 1)
			dumpsizes(np, "equ");
	}
	return spare;
}

# Resize tiny panels (whose max. sz fits on its share) to
# consume just what they require, but not more than that.
# return resulting spare and adjusted nw.
rsztiny(p: ref Panel, spare, nw: Point): (Point, Point)
{
	incr := Point(0, 0);
	if(nw.x != 0)
		incr.x = spare.x/nw.x;
	if(nw.y != 0)
		incr.y = spare.y/nw.y;

	# panels that want less space than its share
	# are give want they want, nothing more.
	# TODO: this should only happen if there's at least one wanting more.
	offset := 0;
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(np.flags&Phide || np.rect.dx() == 0)
			continue;
		if(p.rowcol == Qcol){
			move(np, Point(0, offset));
			dy := np.maxsz.y - np.size.y;
			if(np.resized == 0)
			if(dy > 0 && np.maxsz.y < np.rect.dy() + incr.y){
				np.rect.max.y += dy;
				np.size.y += dy;
				offset += dy;
				spare.y -= dy;
				nw.y--;
			}
		} else {
			move(np, Point(offset, 0));
			dx := np.maxsz.x - np.size.x;
			if(np.resized == 0)
			if(dx > 0 && np.maxsz.x < np.rect.dx() + incr.x){
				np.rect.max.x += dx;
				np.size.x += dx;
				offset += dx;
				spare.x -= dx;
				nw.x--;
			}
		}
		if(debug['L'] > 1)
			dumpsizes(np, "rszt");
	}
	return (spare, nw);
}

# Resize panels still wanting to grow by giving them
# equal shares of all spare space left.
rszlarge(p: ref Panel, spare, nw: Point)
{
	incr := Point(0, 0);
	if(nw.x != 0)
		incr.x = spare.x/nw.x;
	if(nw.y != 0)
		incr.y = spare.y/nw.y;

	offset := 0;
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(np.flags&Phide || np.rect.dx() == 0)
			continue;
		if(p.rowcol == Qcol){
			move(np, Point(0, offset));
			if(np.resized == 0)
			if(np.maxsz.y > np.size.y && spare.y > 0){
				np.rect.max.y += incr.y;
				np.size.y += incr.y;
				offset += incr.y;
			}
		} else {
			move(np, Point(offset, 0));
			if(np.resized == 0)
			if(np.maxsz.x > np.size.x && spare.x > 0){
				np.rect.max.x += incr.x;
				np.size.x += incr.x;
				offset += incr.x;
			}
		}
		if(debug['L'] > 1)
			dumpsizes(np, "rszl");
	}
}

#  Expands inner components to use all the space available.
expand(p: ref Panel)
{
	if(p.rowcol == Qatom){	# atoms do not expand
		if(!p.orect.eq(p.rect))
			p.flags |= Predraw;
		return;
	}

	(spare, nw, max) := findspare(p);
	spare = equalize(p, spare, max);
	(spare, nw) = rsztiny(p, spare, nw);
	rszlarge(p, spare, nw);

	# expand panels to use the avail width/height on rows/cols.
	# and expand inner panels according to the new sizes.
	# finally, flag for redrawing those resized and/or moved.
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(np.flags&Phide || np.rect.dx() == 0)
			continue;
		wants := 0;
		if(np.resized == 0)
		if(p.rowcol == Qcol){
			if(np.maxsz.x > np.size.x)
				wants = 1;
			if(np.rect.max.x < p.rect.max.x - Inset)
			if(np.rowcol == Qcol || np.rowcol == Qrow || wants)
				np.rect.max.x = p.rect.max.x - Inset;
		} else {
			if(np.maxsz.y > np.size.y)
				wants = 1;
			if(np.rect.max.y < p.rect.max.y - Inset)
			if(np.rowcol == Qcol || np.rowcol == Qrow || wants)
				np.rect.max.y = p.rect.max.y - Inset;
		}
		expand(np);
		if(!np.orect.eq(np.rect))
			np.flags |= Predraw;
	}
}

layout(p: ref Panel, auto: int): int
{
	p.rect = win.image.r;
	r := p.rect;
	size(p, auto);
	full := pack(p);
	p.rect = r;
	expand(p);
	return full;
}
