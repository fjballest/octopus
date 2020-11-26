#
# Text drawing for owptext.b

# This draws more than needed, there's a lot that can be optimized
# in that respect; should it be needed.

# A frame is created by a call to Frame.new()
# Nothing can be done to it before calling init() to fill it with text.
# ss, se, and showsel may be adjusted between new() and init()
# In general, init() is called to reposition or to refill the frame.
# sel() is used to adjust ss and se (selection). 
# The frame keeps blks as given to init, and keeps offsets into them.
# Frame.ins/.del are used after calling ins/del on blks to update the frame idea of offsets
# and to update the frame.
# The image, Frame.i, may be given as nil to init(), and may be set to nil at any time between
# calls to prevent the image from drawing.
# A new image (rectangle) may be set for the frame by calling Frame.resize().
# redraw() forces a complete redraw of the frame.
# scroll() scrolls up/down nlines.
# and pt2pos/pos2pt convert between points and positions in blks.
# Other functions are auxiliary and meant for the implementation.

# We could do something about tabs. Like for example: do not wrap long lines,
# and group blocks of text so that a single tab manages to tab all the text properly.
# Also, we do more work than needed. Might draw a lot less.

# This is not as highly coupled to the rest of o/live as it may seem due to init().
# The only module actually needed is Tblks. We use the rest to access the window image
# and colors, mostly.

# A frame is a list of Tbox, mostly. fmt() is the main routine in charge of text formatting.
# The text from Tblks drawn is cached in the boxes, mostly for debug checks.

implement Tframe;
include "mods.m";
mods, win, tree: import dat;
NCOL, HIGH, BACK, TEXT: import gui;
prefix: import str;
include "tblks.m";
	tblks:	Tblks;
	fixpos,  fixposins, fixposdel, dtxt, strstr, Maxline, Tblk, strchr, Str: import tblks;
include "tframe.m";

debug := 0;
nullframe: Frame;

init(d: Livedat, b: Tblks, dbg: int)
{
	dat = d;
	initmods();
	debug = dbg;
	tblks = b;
}

Frame.panic(fr: self ref Frame, s: string)
{
	fr.dump();
	panic(s);
}

charwidth(f : ref Font, c : int) : int
{
	s : string = "z";
	s[0] = c;
	return f.width(s);
}

Frame.new(r: Rect, i: ref Image, f: ref Font, cols: array of ref Image, beof: int): ref Frame
{
	if(debug)
		fprint(stderr, "\tnew frame [%d %d %d %d]\n", r.min.x, r.min.y, r.max.x, r.max.y);
	fr := ref nullframe;
	fr.cols = array[NCOL] of ref Image;
	fr.cols[0:] = cols[0:NCOL];
	fr.font = f;
	fr.tabsz = 4;
	fr.showsel = 1;
	fr.showbeof = beof;
	fr.resize(r, i);
	return fr;
}

mklni(i: ref Image, r: Rect): ref Image
{
	dpy := win.display;
	if(i == nil || !i.r.eq(r))
		i = dpy.newimage(r, win.image.chans, 0, Draw->White);
	return i;
}

# resizes and returns whether we must redraw it all or just the changes.
Frame.resize(fr: self ref Frame, r: Rect, i: ref Image): int
{
	if(debug || fr.debug)
		if(i != nil)
			fprint(stderr, "\tresize frame [%d %d %d %d] img\n",
				r.min.x, r.min.y, r.max.x, r.max.y);
		else
			fprint(stderr, "\tresize frame [%d %d %d %d] noimg\n",
				r.min.x, r.min.y, r.max.x, r.max.y);
	ofi := fr.i;
	ofr := fr.r;

	fr.r = r;
	if(fr.showbeof){
		fr.r.min.y += 1;
		fr.r.max.y -= 1;
	}
	fr.i = i;
	fr.sz.x = fr.r.dx()/fr.font.width("M");
	fr.sz.y = fr.r.dy()/fr.font.height;

	fr.boxes = array[0] of ref Tbox;
	fr.nboxes = fr.nr = 0;
	fr.tabwid = fr.tabsz * fr.font.width("O");
	fr.spwid = fr.font.width(" ");
	x := fr.r.dx() / 3;
	if(x > Beofwid)
		x = Beofwid;
	fr.sbeof = fr.r.min.x + (fr.r.dx() - x) / 2;
	fr.ebeof = fr.sbeof + x;


	# if just the height changed, but not possition or width, refill and done.
	if(fr.blks != nil)		# nil when called by Frame.new()
	if(ofi != nil && ofi == fr.i && ofr.min.eq(fr.r.min) && ofr.dx() == fr.r.dx()){
		fr.fill();
		return 0;
	} else
		fr.init(fr.blks, fr.pos);

	fr.mktick();
	frr := Rect((0,0), (fr.r.dx(), fr.font.height));
	fr.lni = mklni(fr.lni, frr);
	fr.lni.draw(fr.lni.r, fr.cols[BACK], nil, (0,0));
	return ofi == nil || ofi != fr.i || ofr.dx() != fr.r.dx();
}

# This is being using to change to position and not just blks.
# It throws it all away. Could reuse many of the boxes/images it has
# when new content intersects old one.
Frame.init(fr: self ref Frame, blks: ref Tblk, pos: int)
{
	if(debug || fr.debug)
		fprint(stderr, "\tframe init pos %d\n", pos);
	fr.blks = blks;
	l := blks.blen();
	fr.pos = fixpos(pos, l);
	fr.ss = fixpos(fr.ss, l);
	fr.se = fixpos(fr.se, l);
	fr.boxes = array[0] of ref Tbox;
	fr.nboxes = fr.nr = 0;
	fr.fill();
	fr.chk();
}

Frame.mktick(fr : self ref Frame)
{
	dpy := win.display;
	tr := Rect((0, 0), (Tickwid, fr.font.height));
	t := fr.tick = dpy.newimage(tr, win.image.chans, 0, Draw->White);
	t.draw(t.r, fr.cols[BACK], nil, (0, 0));
	t.draw(Rect((Tickwid/2, 0), (Tickwid/2+1, fr.font.height)), fr.cols[TEXT], nil, (0, 0));
	t.draw(Rect((0, 0), (Tickwid, Tickwid)), fr.cols[TEXT], nil, (0,0));
	t.draw(Rect((0, fr.font.height-Tickwid), (Tickwid, fr.font.height)),
		fr.cols[TEXT], nil, (0,0));
}

getboxes(blks: ref Tblk, pos: int, l: int, f: ref Font, maxwid: int): (array of ref Tbox, int)
{
	boxes := array[16] of ref Tbox;
	nboxes := 0;
	b: ref Tbox;
	b = nil;
	wid := 0;
	nr := 0;
	for(i := pos; i < pos + l && wid < maxwid; i++){
		c := blks.getc(i);
		if(c == -1)
			break;
		nr++;
		if(nboxes == len boxes){
			bb := array[len boxes+16] of ref Tbox;
			bb[0:] = boxes;
			boxes = bb;
		}
		case c {
		'\t' =>
			b = ref Tbox('\t', i, 1, (0,0), 0, 1, "\t");
			boxes[nboxes++] = b;
		'\n' =>
			b = ref Tbox('\n', i, 1, (0,0), 0, 1, "\n");
			boxes[nboxes++] = b;
		* =>
			cwid := charwidth(f, c);
			if(b == nil || b.sep){
				b = ref Tbox(0, i, 1, (0,0), cwid, 1, "");
				b.txt[0] = c;
				boxes[nboxes++] = b;
			} else {
				b.txt[b.nr] = c;
				b.nr++;
				b.wid += cwid;
			}
			wid += cwid;
		}
	}
	return (boxes[0:nboxes], nr);
}

# pos is not before fr.pos.
# returns (box idx, rune number in box) for pos
# (perhaps one past the last valid ones).
Frame.seek(fr: self ref Frame, pos: int): (int, int)
{
	for(i := 0; i < fr.nboxes; i++){
		b := fr.boxes[i];
		if(pos < b.pos)
			return(i, 0);
		if(pos < b.pos + b.nr){
			ri := pos - b.pos;
			if(b.sep && ri > 0)
				fr.panic("seek bug");
			return (i, ri);
		}
	}
	return (i, 0);
}

Frame.findnl(fr: self ref Frame, bi: int): int
{
	for(i := bi; i < fr.nboxes; i++)
		if(fr.boxes[i].sep == '\n')
			return i;
	return -1;
}

Frame.pt2pos(fr: self ref Frame, pt: Point): int
{
	if(pt.x < fr.r.min.x)
		pt.x = fr.r.min.x;
	if(pt.x > fr.r.max.x)
		pt.x = fr.r.max.x;
	if(pt.y < fr.r.min.y)
		return 0;
	if(pt.y > fr.r.max.y)
		return fr.pos+fr.nr;
	for(i := 0; i < fr.nboxes; i++){
		b := fr.boxes[i];
		r := Rect(b.pt, (b.pt.x+b.wid, b.pt.y+fr.font.height));
		if(!pt.in(r))
			continue;
		if(b.sep)
			return b.pos;
		else {
			for(i = 0; i < b.nr; i++){
				wid := charwidth(fr.font, b.txt[i]);
				r.max.x = r.min.x + wid;
				if(pt.in(r))
					return b.pos+i;
				r.min.x = r.max.x;
			}
			return b.pos+b.nr -1;	# aprox. last rune in box
		}
	}
	return fr.pos+fr.nr;	# aprox. by eof
}

Frame.pos2pt(fr: self ref Frame, pos: int): Point
{
	if(pos < fr.pos)
		pos = fr.pos;
	if(pos > fr.pos + fr.nr)
		pos = fr.pos + fr.nr;
	pt := Point(fr.r.min);
	for(i := 0; i < fr.nboxes; i++){
		b := fr.boxes[i];
		if(pos < b.pos + b.nr){
			pt = b.pt;
			if(b.sep)
				return pt;
			for(i = 0; b.pos + i < pos; i++)
				pt.x += charwidth(fr.font, b.txt[i]);
			return pt;
		}
	}
	if(i == fr.nboxes){	# pos >= fr.pos + fr.nr; place at end.
		if(fr.nboxes == 0)
			return fr.r.min;
		b := fr.boxes[fr.nboxes-1];
		if(b.pt.x + b.wid < fr.r.max.x)	# at end of last line.
			pt = Point(b.pt.x+b.wid, b.pt.y);
		else if(b.pt.y + fr.font.height < fr.r.max.y)	# at next line
			pt = Point(fr.r.min.x, b.pt.y + fr.font.height);
		else
			pt = Point(b.pt.x+b.wid, b.pt.y);	 # does not fit.
	}
	return pt;
}

# adjusts frame points; does nothing else.
Frame.move(fr: self ref Frame, at: Point)
{
	if(debug || fr.debug)
		fprint(stderr, "\tframe move [%d %d]\n", at.x, at.y);
	dx := at.x - fr.r.min.x;
	dy := at.y - fr.r.min.y;
	delta := Point(dx, dy);
	fr.r = fr.r.addpt(delta);
	for(i := 0; i < fr.nboxes; i++){
		fr.boxes[i].pt = fr.boxes[i].pt.add(delta);
		fr.boxes[i].dirty = 1;
	}
}

# length in runes of boxes
blen(boxes: array of ref Tbox): int
{
	l := 0;
	for(i := 0; i < len boxes; i++)
		if(boxes[i].sep)
			l++;
		else
			l += boxes[i].nr;
	return l;
}

# renumber is true when chars are new and do not come from box split or whatever.
# see also coment in Frame.ins
Frame.addboxes(fr: self ref Frame, bi: int, boxes: array of ref Tbox, renumber: int)
{
	nlen := len boxes + fr.nboxes;
	if(nlen > len fr.boxes){
		nboxes := array[nlen] of ref Tbox;
		if(bi > 0)
			nboxes[0:] = fr.boxes[0:bi];
		if(bi < fr.nboxes)
			nboxes[bi + len boxes:] = fr.boxes[bi:fr.nboxes];
		nboxes[bi:] = boxes;
		fr.boxes = nboxes;
	} else {
		for(i := fr.nboxes - 1; i >= bi; i--)
			fr.boxes[i + len boxes] = fr.boxes[i];
		fr.boxes[bi:] = boxes;
	}
	fr.nboxes += len boxes;
	if(renumber){
		nr := blen(boxes);
		fr.nr += nr;
		for(i := bi + len boxes; i < fr.nboxes; i++)
			fr.boxes[i].pos += nr;
	}
}

# renumber is true when chars are new and do not come
# from box coalescing or whatever.
# see also coment in Frame.ins
Frame.delboxes(fr: self ref Frame, bi: int, nb: int, renumber: int)
{
	nr := blen(fr.boxes[bi:bi+nb]);
	for(i := bi; i+nb< fr.nboxes; i++)
		fr.boxes[i] = fr.boxes[i+nb];
	if(i < len fr.boxes)
		fr.boxes[i] = nil;	# poison
	fr.nboxes -= nb;
	if(renumber){
		fr.nr -= nr;
		for(i = bi; i < fr.nboxes; i++)
			fr.boxes[i].pos -= nr;
	}
}

# splits boxes[bi] leaving the rune at ri in the second box.
# widths are made void and NOT computed
# (because during ins/del all rune offsets are wrong.)
Frame.splitbox(fr: self ref Frame, bi: int, ri: int)
{
	b := fr.boxes[bi];
	if(debug>1 || fr.debug>1)
		fprint(stderr, "\t\tsplitbox %d %d {%s}\n", bi, ri, b.text());
	if(ri == 0 || b.sep || ri > b.nr || b.nr != len b.txt)
		fr.panic("split bug");
	nb := ref Tbox(0, b.pos + ri, b.nr - ri, (0, 0), 0, 0, b.txt[ri:]);
	nb.wid = b.wid = 0;
	b.nr = ri;
	b.txt = b.txt[0:ri];
	b.dirty = nb.dirty = 1;
	fr.addboxes(bi+1, array[] of {nb}, 0);
}

Frame.fixselins(fr: self ref Frame, pos: int, nr: int)
{
	if(pos >= fr.ss && pos <= fr.se){
		if(fr.ss == fr.se)
			fr.ss = fr.se = pos + nr;
		else if(pos+nr > fr.se)
			fr.se = pos+nr;
		else
			fr.se += nr;
	} else if(pos < fr.ss){
		fr.ss += nr;
		fr.se += nr;
	}
}

# If text was inserted before/after the frame it adjusts positions and do nothing.
# Else, some text has been inserted in fr.blks, which makes all the offsets void from
# the point of insertion.
# It builds new boxes for the new text, and inserts them in place.
# To avoid adding too many boxes once the frame is full, it adds only as many as 
# needed to fill an entire frame, considering that the tab and newline widths are 0. 
# That is conservative, but it's simple and at least we know that offsets are right.
# Later we can reformat the text boxes in the frame.
# Returns true if further insertion is futile (eof or frame full).
# Adjusts the selection to that it moves while inserting, otherwise keeping
# it ok despite insertions before/after the current selection.
Frame.ins(fr: self ref Frame, pos: int, nr: int): int
{
	if(debug || fr.debug)
		fprint(stderr, "\tframe ins %d %d\n", pos, nr);
	fr.fixselins(pos, nr);
	if(pos > fr.pos + fr.nr || nr == 0)
		return 1;
	if(pos < fr.pos){
		fr.pos += nr;
		for(i := 0; i < fr.nboxes; i++)
			fr.boxes[i].pos += nr;
		return 0;
	}
	r :=ins(fr, pos, nr);
	fr.draw(0, fr.nboxes, 0);
	fr.sel(fr.ss, fr.se);
	return r;
}

# This is the actual insert, but it does not fix up ss, se, nor pos.
# Used by both Frame.ins and Frame.fill
ins(fr: ref Frame, pos: int, nr: int): int
{
	if(debug || fr.debug)
		fprint(stderr, "\tframe _ins %d %d\n", pos, nr);
	(bi, ri) := fr.seek(pos);
	maxwid := fr.r.dx() * (fr.r.dy()/fr.font.height);
	if(bi > 0)
		maxwid -= fr.boxes[bi-1].pt.y / fr.font.height;
	(boxes, nbr) := getboxes(fr.blks, pos, nr, fr.font, maxwid);
	if(nbr == 0)
		return 1;
	nboxes := len boxes;
	if(ri > 0){
		fr.splitbox(bi, ri);
		nboxes++;
		fr.sizebox(bi);
		fr.sizebox(bi+1);
		fr.addboxes(bi+1, boxes, 1);
	} else
		fr.addboxes(bi, boxes, 1);

	if(bi > 0)
		bi--;	# the box might recombine
	full := fr.fmt(bi);
	if(nbr < nr)
		full = 1;
	if(debug > 1|| fr.debug > 1)
		fr.dump();
	fr.chk();
	return full;
}

Frame.fill(fr: self ref Frame)
{
	(bi, nil) := fr.seek(fr.pos);
	# insertion at end extends the frame, it does not update offsets.
	for(pos := fr.pos + fr.nr; ins(fr, pos, 256) == 0; pos += 256)
		;
	fr.draw(bi, fr.nboxes, 0);
}

Frame.fixseldel(fr: self ref Frame, pos: int, nr: int)
{
	# compute intersection of selection and deleted text,
	# and number of runes removed from selection.
	ds := pos;
	de := pos + nr;
	ns := fr.se - fr.ss;
	if(de <= fr.ss)		# empty isect;
		nr = nr;
	else if(ds >= fr.se)		# empty isect
		nr = 0;
	else {
		if(ds < fr.ss){		# isect ==  [max(ds, fr.ss), min(de, fr.se)]
			ds = fr.ss;
			nr = ds - fr.ss;
		}  else
			nr = 0;
		if(de > fr.se)
			de = fr.se;
		ns -= (de - ds);
	}
	# adjust
	fr.ss -= nr;
	fr.se = fr.ss + ns;
	if(fr.ss > fr.blks.blen())		# pure paranoia
		fr.ss = fr.se = fr.blks.blen();
}

# It proceed like we did for ins. Adjusts offsets if this does not affect frame,
# or removes involved boxes and then reformat. But refills the frame
# after formatting it, because now there might be more room for text.
Frame.del(fr: self ref Frame, pos: int, nr: int)
{
	if(debug || fr.debug)
		fprint(stderr, "\tframe del %d %d\n", pos, nr);
	fr.fixseldel(pos, nr);
	if(pos >= fr.pos + fr.nr || nr == 0)
		return;
	if(pos + nr< fr.pos){
		fr.pos -= nr;
		for(i := 0; i < fr.nboxes; i++)
			fr.boxes[i].pos -= nr;
		return;
	}
	if(pos < fr.pos){		# adjust offsets for text removed
		d := fr.pos-pos;	# before frame.
		fr.pos -= d;
		for(i := 0; i < fr.nboxes; i++)
			fr.boxes[i].pos -= d;
		nr -= d;
	}
	(bs, rs) := fr.seek(pos);
	if(rs > 0){
		fr.splitbox(bs, rs); 
		bs++;
	}
	(be, re) := fr.seek(pos+nr);
	if(re > 0){
		fr.splitbox(be, re);
		be++;		# and include the first part
		re = 0;
	}
	fr.delboxes(bs, be-bs, 1);
	fr.chk();

	# bs-1 is now right before deletion. bs is right after deletion.
	# must redraw/resize them.
	if(bs > 0 && fr.nboxes > 0){
		fr.boxes[bs-1].dirty = 1;
		fr.sizebox(bs-1);
	}
	if(bs<fr.nboxes){
		fr.boxes[bs].dirty = 1;
		fr.sizebox(bs);
	}
	fr.fmt(bs);
	fr.fill();
	if(debug > 1 || fr.debug > 1)
		fr.dump();
	fr.draw(0, fr.nboxes, 0);
	sel(fr, fr.ss, fr.se);
}

selrange(fr: ref Frame, s, e: int): (int, int)
{
	(bs, nil) := fr.seek(s);
	(be, nil) := fr.seek(e);
	if(be < fr.nboxes)
		be++;
	if(bs == be && bs == fr.nboxes && bs > 0)
		bs--;	# last box draws eot tick
	return (bs, be);
}

sel(fr: ref Frame, ss: int, se: int)
{
	os := fr.ss;
	oe := fr.se;
	fr.ss = ss;
	fr.se = se;
	if(fr.i == nil)
		return;
	bs := be := ns := ne := -1;
	if(fr.ss < os &&  fr.se == oe) 		# extend back
		(bs, be) = selrange(fr, fr.ss, os);
	else if(fr.ss == os && fr.se > oe)		# extend fwd
		(bs, be) = selrange(fr, oe, fr.se);
	else {
		(bs, be) = selrange(fr, os, oe);	# clear old
		(ns, ne) = selrange(fr, fr.ss, fr.se);	# and draw new.
	}
	if(debug || fr.debug)
		fprint(stderr, "\tframe sel %d %d ob(%d:%d) nb(%d:%d)\n",
			ss, se, bs, be, ns, ne);
	if(bs > 0)
		bs--;
	fr.draw(bs, be, 1);
	if(ns >= 0)
		for(i := ns; i < ne; i++)
			if(i < bs || i >= be)
				fr.drawbox(i);
}

Frame.sel(fr: self ref Frame, ss: int, se: int)
{
	ss = fixpos(ss, fr.blks.blen());
	se = fixpos(se, fr.blks.blen());
	if(fr.ss != ss || fr.se != se)
		sel(fr, ss, se);
}

# Sets positions for boxes[b0:be], giving sizes to sep boxes and
# splitting/combining text boxes as needed to format the text;
# should the frame fill, remaining boxes are removed.
# Returns true if it's futile to add more text to the frame.
Frame.fmt(fr: self ref Frame, bi: int): int
{
	if(bi >= fr.nboxes)
		return 0;
	if(debug || fr.debug)
		fprint(stderr, "\tframe fmt b %d {%s}...\n", bi, fr.boxes[bi].text());
	for(; bi < fr.nboxes; bi++){
		b := fr.boxes[bi];
		fr.placebox(bi);
		if(b.pt.y+fr.font.height > fr.r.max.y){	# frame full, truncate
			fr.delboxes(bi, fr.nboxes - bi, 1);
			return 1;
		}
		if(b.sep){
			fr.sizebox(bi);
			continue;
		}
		if(b.pt.x + b.wid > fr.r.max.x){
			if(debug>1 || fr.debug >1)
				fprint(stderr, "\t\twrap %s\n", b.text());
			nbi := fr.wrapbox(bi);
			if(fr.boxes[nbi].pt.y+fr.font.height > fr.r.max.y){
				fr.delboxes(nbi, fr.nboxes-nbi, 1);
				return 1;
			}
		} else if(bi+1 < fr.nboxes && !fr.boxes[bi+1].sep){
			# try to combine at least two of them.
			if(fr.combinebox(bi) && (debug>1 || fr.debug>1))
				fprint(stderr, "\t\tcombine %s\n", b.text());
			if(fr.boxes[bi+1].nr == 0)
				fr.delboxes(bi+1, 1, 0);
		}
	}

	# Adjust y coord for the rest of boxes. But don't do so if
	# the first does not change placement: no lines were added/removed.
	if(bi < fr.nboxes){
		pt := fr.boxes[bi].pt;
		fr.placebox(bi);
		if(pt.eq(fr.boxes[bi].pt))
			return 1;
	}
	for(; bi < fr.nboxes; bi++){
		fr.placebox(bi);
		if(fr.boxes[bi].pt.y+fr.font.height > fr.r.max.y){
			fr.delboxes(bi, fr.nboxes-bi, 1);
			return 1;
		}
	}
	return 0;
}

# determines start point for box. It might go off-limits, but the pt
# is set ok according to the previous box.
Frame.placebox(fr: self ref Frame,  bi: int)
{
	b := fr.boxes[bi];
	opt := b.pt;
	if(bi > 0){
		lb := fr.boxes[bi-1];
		if(lb.sep != '\n' && lb.pt.x + lb.wid < fr.r.max.x)
			b.pt = Point(lb.pt.x+lb.wid, lb.pt.y);
		else
			b.pt = Point(fr.r.min.x, lb.pt.y+fr.font.height);
	} else
		b.pt = fr.r.min;
	if(!opt.eq(b.pt))
		b.dirty = 1;
}

# drains as many runes as feasingle from bi+1 into bi.
Frame.combinebox(fr: self ref Frame, bi: int): int
{
	b := fr.boxes[bi];
	nb := fr.boxes[bi+1];
	# Try to do it at once
	if(b.pt.x + b.wid + nb.wid <= fr.r.max.x){
		b.nr += nb.nr;
		b.wid += nb.wid;
		b.txt += nb.txt;
		nb.nr = 0;
		nb.wid = 0;
		nb.txt = "";
		b.dirty = 1;
		return 1;
	}
	x := b.pt.x + b.wid;
	wid := 0;
	for(i := 0; i < nb.nr; i++){
		cw := charwidth(fr.font, nb.txt[i]);
		if(x + wid + cw > fr.r.max.x)
			break;
		wid += cw;
	}
	if(i > 0){
		b.nr += i;
		b.txt += nb.txt[0:i];
		b.wid += wid;
		b.dirty = 1;
		nb.pos += i;
		nb.nr -= i;
		nb.txt = nb.txt[i:];
		nb.wid -= wid;
		nb.dirty = 1;
		return 1;
	}
	return 0;
}

# Wraps box bi (which should) either complete or a suffix.
# returns the index for the wrapped box (entire or suffix).
Frame.wrapbox(fr: self ref Frame, bi: int): int
{
	b := fr.boxes[bi];
	wid := 0;
	for(i := 0; i < b.nr; i++){
		cw := charwidth(fr.font, b.txt[i]);
		if(b.pt.x + wid + cw > fr.r.max.x)
			break;
		wid += cw;
	}
	if(i == b.nr){
		# This shouldn't happen, but it happens
		# when wrapping long lines some times.
		# It seems that b.wid >= wid as computed
		# above, and Frame.fmt thinks we should wrap.
if(0)fprint(stderr, "\nwrap at the end of a box? %d %d\n", b.wid, wid);
		b.wid = wid;
		b.dirty = 1;
		return bi;
	}
	pt := Point(fr.r.min.x, b.pt.y + fr.font.height);
	if(i == 0){
		b.pt = pt;
		b.dirty = 1;
		return bi;
	}
	nb := ref Tbox(0, b.pos + i, b.nr - i, pt, b.wid - wid, 1, b.txt[i:b.nr]);
	b.wid = wid;
	b.nr = i;
	b.dirty = 1;
	b.txt = b.txt[0:i];
	b.dirty = 1;
	nb.dirty = 1;
	fr.addboxes(bi+1, array[] of {nb}, 0);
	return bi+1;
}

# adjusts sizes for sep boxes, which are dynamic.
# recomputes width for text boxes.
Frame.sizebox(fr: self ref Frame, bi: int)
{
	b := fr.boxes[bi];
	owid := b.wid;
	case b.sep {
	'\t' =>
		b.wid = fr.tabwid - (b.pt.x - fr.r.min.x)%fr.tabwid;
		if(b.wid < fr.spwid)
			b.wid = fr.spwid;
		if(b.pt.x < fr.r.max.x && b.pt.x + b.wid > fr.r.max.x)
			b.wid = fr.r.max.x - b.pt.x;
	'\n' =>
		b.wid = fr.r.max.x - b.pt.x;
	0 =>
		b.wid = 0;
		for(i := 0; i < b.nr; i++)
			b.wid += charwidth(fr.font, b.txt[i]);
	}
	if(b.wid != owid)
		b.dirty = 1;
}

# text from the text block, to double check offsets.
Frame.boxtext(fr: self ref Frame, bi: int): string
{
	b := fr.boxes[bi];
	s := "";
	for(j:= 0; j < b.nr; j++)
		s[j] = fr.blks.getc(b.pos+j);
	return s;
}

Frame.chk(fr: self ref Frame)
{
	nr := blen(fr.boxes[0:fr.nboxes]);
	if(nr != fr.nr)
		fr.panic("nr check");
	for(i := 0; i < fr.nboxes; i++){
		b := fr.boxes[i];
		s := fr.boxtext(i);
		if(s != b.txt)
			fr.panic(sprint("box %d check: " +
				"pos %d nr %d txt [%s] blks [%s]\n", 
				i, b.pos, b.nr, b.txt, s));
	}
	if(fr.ss < 0 || fr.se < 0)
		fr.panic(sprint("bad sel %d %d\n", fr.ss, fr.se));
	l := fr.blks.blen();
	if(fr.ss > l || fr.se > l)
		fprint(stderr, "\tframe warning: sel range: %d %d\n", fr.ss, fr.se);
}

Frame.drawtick(fr: self ref Frame, i: ref Image, pt: Point)
{
	if(pt.x > fr.r.min.x)	# looks better
		pt.x--;
	r := Rect(pt, (pt.x+Tickwid, pt.y+fr.font.height));
	(cr, rc) := r.clip(fr.r);
	if(rc != 0)
		r = cr;
	i.draw(r, fr.tick, nil, (0, 0));
}

drawmark(fr: ref Frame, y: int, mark: int)
{
	if(mark){
		rr := Rect((fr.r.min.x, y), (fr.sbeof, y+1));
		fr.i.draw(rr, fr.cols[BACK], nil, (0,0));
		rr = Rect((fr.sbeof, y), (fr.ebeof, y+1));
		fr.i.draw(rr, fr.cols[TEXT], nil, (0,0));
		rr = Rect((fr.ebeof, y), (fr.r.max.x, y+1));
		fr.i.draw(rr, fr.cols[BACK], nil, (0,0));
	} else {
		rr := Rect((fr.r.min.x, y), (fr.r.max.x, y+1));
		fr.i.draw(rr, fr.cols[BACK], nil, (0,0));
	}
}


Frame.draw(fr: self ref Frame, bi: int, be: int, force: int)
{
	if(fr.i == nil)
		return;
	if(debug || fr.debug)
		fprint(stderr, "\tframe draw bi %d be %d fz %d [%d %d %d %d]\n",
			bi, be, force, fr.r.min.x, fr.r.min.y, fr.r.max.x, fr.r.max.y);
	if(fr.nboxes == 0){
		if(fr.showbeof){
			drawmark(fr, fr.r.min.y-1, 1);
			drawmark(fr, fr.r.min.y+fr.font.height, 1);
			if(fr.r.min.y+fr.font.height != fr.r.max.y)
				drawmark(fr, fr.r.max.y, 0);
		}
		fr.i.draw(fr.r, fr.cols[BACK], nil, (0,0));
		if(fr.showsel)
			fr.drawtick(fr.i, fr.r.min);
	} else
		for(i := bi; i < be && i < fr.nboxes; i++)
			if(force || fr.boxes[i].dirty)
				fr.drawbox(i);
}

Frame.redraw(fr: self ref Frame, force: int)
{
	fr.draw(0, fr.nboxes, force);
}

# The primary drawing function.
# Draws the box mentioned, drawing the selection within the box if it's affected.
# The last box in line clears the rest of the line and last in frame clears rest of f.r.
# drawing the tick past it when it's at end of text in frame.

Frame.drawbox(fr: self ref Frame, bi: int)
{
	b := fr.boxes[bi];
	if(debug>1||fr.debug>1)
		fprint(stderr, "\tframe drawbox %s\n", b.text());
	tickpt := Point(-1, -1);
	s := b.pos;
	e := b.pos + b.nr;
	pt := Point(0,0);
	r := Rect((0, 0), (b.wid, fr.font.height));
	fr.lni.draw(r, fr.cols[BACK], nil, (0, 0));
	# draw selection or determine tick position if box is affected.
	if(fr.ss < s && fr.se >= e || fr.ss >= s && fr.ss < e || fr.se >= s && fr.se < e){
		if(fr.ss != fr.se){
			ss := fr.ss;
			if(ss < s)
				ss = s;
			spt := fr.pos2pt(ss);
			ept := Point(spt.x+b.wid, 0);
			if(fr.se < e)
				ept = fr.pos2pt(fr.se);
			ept.y = 0;
			if(debug>1||fr.debug>1)
				fprint(stderr, "\t\tsel: pos %d %d [%d %d] [%d %d]\n",
					fr.ss, fr.se, spt.x, spt.y, ept.x, ept.y);
			frr := Rect((spt.x-b.pt.x, 0), (ept.x-b.pt.x, fr.font.height));
			fr.lni.draw(frr, fr.cols[HIGH], nil, (0,0));
		} else {
			tickpt = fr.pos2pt(fr.ss);
			if(debug>1||fr.debug>1)
				fprint(stderr, "\t\ttick: pos %d pt [%d %d]\n",
					fr.ss, tickpt.x, tickpt.y);
			tickpt.y = 0;
			tickpt.x -= b.pt.x;
		}
	}
	if(!b.sep)
		fr.lni.text(pt, fr.cols[TEXT], (0,0), fr.font, b.txt);
	if(tickpt.x != -1 && fr.showsel)
		fr.drawtick(fr.lni, tickpt);
	fr.i.draw((b.pt, (b.pt.x+b.wid, b.pt.y+fr.font.height)), fr.lni, nil, (0,0));
	b.dirty = 0;

	# clear rest of line if last box on line or frame
	# (plain boxes do not consume all the line)
	if(bi == fr.nboxes-1 || fr.boxes[bi+1].pt.y != b.pt.y)
	if(b.pt.x + b.wid < fr.r.max.x){
		col := fr.cols[BACK];
		if(b.pos+b.nr > fr.ss && b.pos+b.nr < fr.se)
			col = fr.cols[HIGH];
		r = Rect((b.pt.x+b.wid, b.pt.y), (fr.r.max.x, b.pt.y+fr.font.height));
		fr.i.draw(r, col, nil, (0,0));
	}

	# clear rest of rect if last box on frame and empty space below.
	if(bi == fr.nboxes-1 && b.pt.y + fr.font.height < fr.r.max.y){
		r= Rect((fr.r.min.x, b.pt.y+fr.font.height), fr.r.max);
		if(fr.showbeof)
			r.min.y++; # do not clear the eof mark line (flicker)
		fr.i.draw(r, fr.cols[BACK], nil, (0,0));
	}

	# draw tick if past the last box.
	if(bi == fr.nboxes-1 && fr.showsel && fr.ss == fr.se && fr.ss == fr.pos + fr.nr)
		fr.drawtick(fr.i, fr.pos2pt(fr.ss));

	# draw bof/eof if appropriate
	if(fr.showbeof && bi == 0)
		drawmark(fr, fr.r.min.y-1, fr.pos == 0);
	if(fr.showbeof && bi == fr.nboxes-1){
		y := b.pt.y + fr.font.height;
		drawmark(fr, y, fr.pos+fr.nr >= fr.blks.blen());
		if(y != fr.r.max.y)
			drawmark(fr, fr.r.max.y, 0); # clear reserved space.
	}
}

# Scrolls down (negative nl) or up (possitive nl) by moving the frame up or down.
# Scroll up/down stops when at the first line/only last line is shown.
# A scroll might move more than requested, because we guess how many
# chars to move (cf. line wrap). 
Frame.scroll(fr: self ref Frame, nl: int)
{
	if(debug || fr.debug)
		fprint(stderr, "\tframe scroll %d\n", nl);
	s := fr.blks.pack();
	l := fr.blks.blen();
	if(nl == 0 || nl > 0 && fr.pos + fr.nr >= l || nl < 0 && fr.pos == 0)
		return;
	npos := fr.pos;
	if(nl > 0){	# move down (scroll up)
		do {
			p := s.find(npos, '\n', Maxline);
			if(p < 0)
				break;
			npos = p;
			if(s.s[p] == '\n' && p < l)	# position just after the \n
				npos++;
		} while(--nl > 0);
	} else {	# move up (scroll down)
		do {
			p := s.findr(npos, '\n', Maxline);
			if(p < 0){
				npos = 0;
				break;
			}
			npos = p;
			if(s.s[p] == '\n' && p > 0)	# position right before the \n
				npos--;
		} while(++nl < 1);		# <1 for the \n right before the frame
		if(npos > 0 && npos+2 < l)	# skip after the \n just found,
			npos += 2;		# but not when at the start of text.
	}
	if(npos == fr.pos)
		return;
	# Easier but slow.
	fr.init(fr.blks, npos);
}

Tbox.text(b: self ref Tbox): string
{
	s := "";
	if(b.dirty)
		s += "d ";
	case b.sep {
	'\t' =>
		 s += sprint("%d %d:%d [\\t ]", b.pos, b.pt.x, b.wid);
	'\n' =>
		s += sprint("%d %d:%d [\\n]", b.pos, b.pt.x, b.wid);
	* =>
		s += sprint("%d %d:%d [%s]", b.pos, b.pt.x, b.wid, b.txt);
	}
	return s;
}

Frame.dump(fr: self ref Frame)
{
	s := sprint("frame: %d boxes (arry %d) pos %d nr %d sel %d %d\n",
		fr.nboxes, len fr.boxes, fr.pos, fr.nr, fr.ss, fr.se);
	i := fr.i;
	if(fr.i != nil)
		s += sprint("\timg [%d %d %d %d]",
			i.r.min.x, i.r.min.y, i.r.max.x, i.r.max.y);
	r := fr.r;
	s += sprint("\tr [%d %d %d %d] sz [%d %d] rsz [%d %d]\n",
			r.min.x, r.min.y, r.max.x, r.max.y,
			fr.sz.x, fr.sz.y, fr.r.dx(), fr.r.dy());
	for(bi := 0; bi < fr.nboxes; bi++){
		b := fr.boxes[bi];
		s += sprint("\tbox %d: %s\n", bi, b.text());
	}
	fprint(stderr, "\t%s\n\n", s);
}

