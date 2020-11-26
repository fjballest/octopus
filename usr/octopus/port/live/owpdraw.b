implement Pimpl;
include "mods.m";
mods, debug, win, tree: import dat;


Cpointer, cols, panelback, maxpt, cookclick, drawtag, TEXT,
BACK, HIGH, HBORD, BORD, HTEXT, SET, CLEAR, MBACK, MSET, MCLEAR : import gui;
Ptag, nth, Predraw, Panel: import wpanel;
panelctl, panelkbd, panelmouse, tagmouse, Tree: import wtree;

Pdraw: adt {
	canvas:	ref Image;
	dcmds:	string;
};

# Beware: Draw functions and colors must be kept in sync with
# ../mero/ompdraw.b, which checks out user writes for validity
# we recheck here, just in case.

Drawfunc: type ref fn(canvas: ref Image, args: list of string): Point;

Dcmd: adt {
	name: string;
	drawfn: Drawfunc;
};

Dcol: adt {
	name: string;
	img:	ref Image;
};

dcols: list of Dcol;
dcmds: array of Dcmd;
panels: array of ref Pdraw;

pimpl(p: ref Panel): ref Pdraw
{
	if(p.implid < 0 || p.implid > len panels || panels[p.implid] == nil)
		panic("draw: bug: no impl");
	return panels[p.implid];
}

initcols()
{
	dpy := win.display;
	icols := array[] of {
		("black", Draw->Black),
		("white", Draw->White),
		("red", Draw->Red),
		("green", Draw->Green),
		("blue", Draw->Blue),
		("cyan", Draw->Cyan),
		("magenta", Draw->Magenta),
		("yellow", Draw->Yellow),
		("grey", Draw->Grey),
		("paleyellow", Draw->Paleyellow),
		("darkyellow", Draw->Darkyellow),
		("darkgreen", Draw->Darkgreen),
		("palegreen", Draw->Palegreen),
		("medgreen", Draw->Medgreen),
		("darkblue", Draw->Darkblue),
		("palebluegreen", Draw->Palebluegreen),
		("paleblue", Draw->Paleblue),
		("bluegreen", Draw->Bluegreen),
		("greygreen", Draw->Greygreen),
		("palegreygreen", Draw->Palegreygreen),
		("yellowgreen", Draw->Yellowgreen),
		("medblue", Draw->Medblue),
		("greyblue", Draw->Greyblue),
		("palegreyblue", Draw->Palegreyblue),
		("purpleblue", Draw->Purpleblue),
	};
	dcols = nil;
	for(i := 0; i < len icols; i++)
		dcols = Dcol(icols[i].t0, dpy.color(icols[i].t1))::dcols;
	dcols = Dcol("back", cols[BACK]):: dcols;
	dcols = Dcol("high", cols[HIGH])::dcols;
	dcols = Dcol("bord", cols[BORD])::dcols;
	dcols = Dcol("text", cols[TEXT])::dcols;
	dcols = Dcol("htext", cols[HTEXT])::dcols;
	dcols = Dcol("hbord", cols[HBORD])::dcols;
	dcols = Dcol("set", cols[SET])::dcols;
	dcols = Dcol("clear", cols[CLEAR])::dcols;
	dcols = Dcol("mback", cols[MBACK])::dcols;
	dcols = Dcol("mset", cols[MSET])::dcols;
	dcols = Dcol("mclear", cols[MCLEAR])::dcols;
}

init(d: Livedat): string
{
	prefixes = list of {"draw:"};
	dat = d;
	initmods();

	# BUG: needs arc fillarc, bezier, fillbezier, and text (from Draw->Image)
	# and probably needs move and copy.
	# PIC would be a nice language to implement here.

	dcmds = array[] of {
		Dcmd("ellipse", dellipse),		# ellipse cx cy rx ry  [w col]
		Dcmd("fillellipse", dfillellipse),	# fillellipse cx cy rx ry  [col]
		Dcmd("line", dline),			# line ax ay bx by [ea eb r col]
		Dcmd("rect", drect),			# rect ax ay bx by [col]
		Dcmd("poly", dpoly),			# poly x0 y0 x1 y1 ... xn yn e0 en w col
		Dcmd("bezspline", dpoly),		# bezspline x0 y0 x1 y1 ... xn yn e0 en w col
		Dcmd("fillpoly", dfillpoly),		# fillpoly x0 y0 x1 y1 ... xn yn w col
		Dcmd("fillbezspline", dfillpoly)	# fillbezspline x0 y0 x1 y1 ... xn yn w col
	};
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
		npanels := array[i+16] of ref Pdraw;
		npanels[0:] = panels;
		panels = npanels;
	}
	p.implid = i;
	panels[i] = ref Pdraw(nil, "");
	p.minsz = p.maxsz = Point(48,48);
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

pevent(nil: ref Panel, nil: string)
{
	# no ins/del events
}

atocol(s: string): ref Image
{
	for(l := dcols; l != nil; l = tl l)
		if((hd l).name == s)
			return (hd l).img;
	fprint(stderr, "o/live: atocol unknown color %s\n", s);
	return cols[TEXT];
}

dellipse(canvas: ref Image, args: list of string): Point
{
	if(len args < 5 || len args > 7)
		return Point(0,0);
	pt := Point(int nth(args, 1), int nth(args, 2));
	rd := Point(int nth(args, 3), int nth(args, 4));
	c := cols[TEXT];
	wid := 0;
	if(len args >= 6)
		wid = int nth(args, 5);
	if(len args == 7)
		c = atocol(nth(args, 6));
	if(canvas != nil)
		canvas.ellipse(pt, rd.x, rd.y, wid, c, (0,0));
	return pt.add(rd);
}

dfillellipse(canvas: ref Image, args: list of string): Point
{
	if(len args < 5 || len args > 6)
		return Point(0,0);
	pt := Point(int nth(args, 1), int nth(args, 2));
	rd := Point(int nth(args, 3), int nth(args, 4));
	c := cols[TEXT];
	if(len args == 6)
		c = atocol(nth(args, 5));
	if(canvas != nil)
			canvas.fillellipse(pt, rd.x, rd.y, c, (0,0));
	return pt.add(rd);
}

dline(canvas: ref Image, args: list of string): Point
{
	if(len args < 5 || len args > 9)
		return Point(0,0);
	min := Point(int nth(args, 1), int nth(args, 2));
	max := Point(int nth(args, 3), int nth(args, 4));
	ea := eb := wid := 0;
	c := cols[TEXT];
	if(len args >= 6)
		ea = int nth(args, 5);
	if(len args >= 7)
		eb = int nth(args, 6);
	if(len args >= 8)
		wid = int nth(args, 7);
	if(len args >= 9)
		c = atocol(nth(args, 8));
	if(canvas != nil)
		canvas.line(min, max, ea, eb, wid, c, (0,0));
	r := Rect(min, max);
	r = r.canon();
	return r.max;
}

drect(canvas: ref Image, args: list of string): Point
{
	if(len args < 5 || len args > 6)
		return Point(0,0);
	min := Point(int nth(args, 1), int nth(args, 2));
	max := Point(int nth(args, 3), int nth(args, 4));
	r := Rect(min, max);
	col := cols[TEXT];
	if(len args == 6)
		col = atocol(nth(args, 5));
	if(canvas != nil)
		canvas.draw(r, col, nil, (0,0));
	return max;
}

dpoly(canvas: ref Image, args: list of string): Point
{
	l := len args;
	if(l < 5 + 3 * 2)
		return Point(0,0);
	np := (l -5)/2;
	pts := array[np] of Point;
	cmd := hd args;
	args = tl args;
	max := Point(0,0);
	for(i := 0; i < len pts; i++){
		pts[i] = Point(int hd args, int hd tl args);
		args = tl tl args;
		if(max.x < pts[i].x)
			max.x = pts[i].x;
		if(max.y < pts[i].y)
			max.y = pts[i].y;
	}
	e0 := int hd args; args = tl args;
	e1 := int hd args; args = tl args;
	w  := int hd args; args = tl args;
	col  := atocol(hd args);
	if(canvas != nil)
		case cmd {
		"bezspline" =>
			canvas.bezspline(pts, e0, e1, w, col, (0,0));
		* =>
			canvas.poly(pts, e0, e1, w, col, (0,0));
		}
	return max;
}

dfillpoly(canvas: ref Image, args: list of string): Point
{
	l := len args;
	if(l < 3 + 3 * 2)
		return Point(0,0);
	np := (l - 3)/2;
	pts := array[np] of Point;
	cmd := hd args;
	args = tl args;
	max := Point(0,0);
	for(i := 0; i < len pts; i++){
		pts[i] = Point(int hd args, int hd tl args);
		args = tl tl args;
		if(max.x < pts[i].x)
			max.x = pts[i].x;
		if(max.y < pts[i].y)
			max.y = pts[i].y;
	}
	w  := int hd args; args = tl args;
	col  := atocol(hd args);
	if(canvas != nil)
		case cmd {
		"fillbezspline" =>
			canvas.fillbezspline(pts, w, col, (0,0));
		* =>
			canvas.fillpoly(pts, w, col, (0,0));
		}
	return max;
}

drawcmds(nil: ref Panel, s: string, canvas: ref Image): Point
{
	max := Point(0,0);
	(nil, cmds) := tokenize(s, "\n");
	for(; cmds != nil; cmds = tl cmds){
		(nargs, args) := tokenize(hd cmds, " \t");
		if(nargs > 0){
			for(i := 0; i < len dcmds; i++)
				if(dcmds[i].name == hd args){
					if(canvas != nil && debug['D']){
						for(l := args; l != nil; l = tl l)
							fprint(stderr, "'%s' ", hd l);
						fprint(stderr, "\n");
					}
					x := dcmds[i];
					xp := x.drawfn(canvas, args);
					max = maxpt(max, xp);
					break;
				}
		}
	}
	max = max.add((2,2));				# two extra pixels
	max = maxpt(max, Point(10, 10));	# and ensure a min. sz
	return max;
}

pupdate(p: ref Panel, d: array of byte)
{
	if(dcols == nil)
		initcols();
	dpy := win.display;
	c := win.image.chans;
	pi := pimpl(p);
	if(pi == nil)
		return;
	ncmds := string d;
	if(pi.dcmds == ncmds)
		return;
	pi.dcmds = string d;
	if(pi.canvas != nil)
		pi.canvas = nil;
	p.minsz = p.maxsz = drawcmds(p, pi.dcmds, nil);	# compute size
	r := Rect((0,0), p.minsz);
	cback := panelback(p.parent);
	ncanvas := dpy.newimage(r, c, 0, Draw->White);
	if(ncanvas == nil){
		fprint(stderr, "o/live: pdraw: %r\n");
		return;
	}
	ncanvas.draw(ncanvas.r, cback, nil, (0,0));
	drawcmds(p, pi.dcmds, ncanvas);
	pi.canvas = ncanvas;
	p.flags |= Predraw;
}

pdraw(p: ref Panel)
{
	if(dcols == nil)
		initcols();
	pi := pimpl(p);
	cback := panelback(p);
	if(pi != nil && pi.canvas != nil){
		win.image.draw(p.rect, pi.canvas, nil, (0,0));
		if(pi.canvas.r.dx() < p.rect.dx()){
			r := p.rect;
			r.min.x += pi.canvas.r.dx();
			win.image.draw(r, cback, nil, (0,0));
		}
		if(pi.canvas.r.dy() < p.rect.dy()){
			r := p.rect;
			r.min.y += pi.canvas.r.dy();
			win.image.draw(r, cback, nil, (0,0));
		}
	} else
		win.image.draw(p.rect, cback, nil, (0,0));
	if(p.flags&Ptag)
		drawtag(p);
}

pmouse(p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	if(panelmouse(tree, p, m, mc))
		return;
	pt := m.xy.sub(p.rect.min);
	b := m.buttons;
	if(m.buttons != 0 && cookclick(m, mc))
		p.fsctl(sprint("click %d %d %d %d", pt.x, pt.y, b, m.msec), 1);
}

pkbd(p: ref Panel, r: int)
{
	panelkbd(nil, p, r);
}

