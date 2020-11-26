implement Menus;

include "mods.m";
mods, debug, win, tree: import dat;

Cpointer, SET, getfont, cols, TEXT, BACK, BACK0, BORD, MSET, MCLEAR, MBACK,
maxpt, Tagwid, Taght, Inset, setcursor, cookclick, SHAD, Arrow: import gui;
Qcol, Qrow, Qatom, Ptag, Phide, Playout, Panel: import Wpanel;

Rx: con 60;
Ry: con 35;
Borwid: con 3;	# border width, for shadow

init(d: Livedat)
{
	dat = d;
	initmods();
}

nullmenu: Menu;

Menu.new(opts: array of string): ref Menu
{
	mn:= ref nullmenu;
	mn.opts = array[len opts] of Opt;
	mn.nsects = len opts;
	if(mn.nsects % 2)
		mn.nsects++;
	mn.∆φ = (2.0 * Math->Pi) / real mn.nsects;
	φ := 0.0;
	for(i := 0; i < len opts; i++){
		mn.opts[i] = Opt(opts[i], φ, nil, nil, (0,0), ((0,0), (0,0)) );
		φ += mn.∆φ;
	}
	return mn;
}

mkoptimage(r: Rect, s: string, font: ref Font, c: int): ref Image
{
	dpy := win.display;
	i := dpy.newimage(r, win.image.chans, 0, Draw->White);
	i.draw(i.r, cols[MBACK], nil, (0,0));
	i.border(r, 1, cols[BORD], (0,0));
	pt := Point(Inset/2, Inset/2);
	pt.x += (r.dx() - font.width(s)) / 2;
	i.text(pt, cols[c], (0,0), font, s);
	return i;
}

Menu.mk(mn: self ref Menu)
{
	dpy := win.display;
	font := getfont("B");
	maxwid := 0;
	for(i := 0; i < len mn.opts; i++){
		wid := font.width(mn.opts[i].name);
		if(wid +4 > maxwid)
			maxwid = wid + 4;
	}
	rx := Rx + maxwid/2 + Borwid;
	ry := Ry + font.height/2 + Borwid;
	mn.r = Rect((0,0), (2*rx, 2*ry));
	mn.saved = dpy.newimage(mn.r, win.image.chans, 0, Draw->Black);
	r := Rect((0,0), (maxwid, font.height));
	for(i = 0; i < len mn.opts; i++){
		# center of the option
		mn.opts[i].pt.x = rx + int (real Rx * math->cos(mn.opts[i].φ));
		mn.opts[i].pt.y = ry + int (real Ry * math->sin(mn.opts[i].φ));
		# top-left corner
		mn.opts[i].pt.x -= maxwid/2;
		mn.opts[i].pt.y -= (font.height/2);
		mn.opts[i].si = mkoptimage(r, mn.opts[i].name, font, MSET);
		mn.opts[i].ci = mkoptimage(r, mn.opts[i].name, font, MCLEAR);
	}
}

Menu.draw(mn: self ref Menu, min: Point, set, first: int)
{
	c := min.add((mn.r.dx()/2, mn.r.dy()/2));
	a := Image.arrow(0,0,0);
	win.image.line(c.add((-15,15)),c.add((15, -10)), a, a, 0, cols[TEXT], (0,0));
	win.image.line(c.add((15,15)),c.add((-15, -10)), a, a, 0, cols[TEXT], (0,0));
	for(i := 0; i < len mn.opts; i++){
		dpt := min.add(mn.opts[i].pt);
		mn.opts[i].sr = mn.opts[i].si.r.addpt(dpt);
		img := mn.opts[i].ci;
		if(set == i)
			img = mn.opts[i].si;
		if(first){
			# draw the shadow just once.
			shadr := mn.opts[i].sr.addpt((Borwid-1, Borwid-1));
			win.image.draw(shadr, cols[TEXT], cols[SHAD], (0,0));
		}
		win.image.draw(mn.opts[i].sr, img, nil, (0,0));
	}
}

Menu.optat(mn: self ref Menu, pt: Point): int
{
	# pt in sector [opt.φ - ∆φ/2, opt.φ + ∆φ/2 ]
	ptcos := real - pt.x / math->sqrt(real (pt.x*pt.x +pt.y*pt.y));
	φ := math->acos(ptcos);
	if(pt.y > 0)
		φ = -φ;
	φ += Math->Pi;	# φ in [0, 2π]

	#fprint(stderr, "φ %f ptcos %f x: %d y: %d\n", φ, ptcos, pt.x, pt.y);

	φ += mn.∆φ;
	if(φ > 2.0 * Math->Pi)
		φ -= 2.0 * Math->Pi;
	
	x := int (φ / mn.∆φ) - 1;
	if(x < 0)
		x += mn.nsects;

	#fprint(stderr, "φ %g n %d ∆φ %g\n", φ, x, mn.∆φ);
	# might consider doing nothing when the angle is not clear enough
	# to avoid mistakes.
	if(x < 0 || x > len mn.opts -1)
		return -1;
	return x;
}

Menu.mouse(mn: self ref Menu, nil: Point, m: ref Cpointer, mc: chan of ref Cpointer): string
{
	xy := m.xy;
	m = <-mc;
	case m.buttons {
	4 =>
		do {
			m = <-mc;
		} while(m.buttons);
		return mn.opts[mn.last].name;
	0 =>
		d := oxy := Point(0,0);
		do {
			m = <-mc;
			oxy = d = m.xy.sub(xy);
			if(d.x < 0)
				d.x = -d.x;
			if(d.y < 0)
				d.y = -d.y;
		} while(d.x < 20 && d.y < 20 && !m.buttons);
		case m.buttons {
		0 =>
			sys->sleep(100);
			moved: int;
			do {
				moved = 0;
				alt { m = <-mc => moved = 1; * => moved = 0; }
			} while(moved);
			id := mn.optat(oxy);
			if(id < 0)
				return nil;
			mn.last = id;
			return mn.opts[mn.last].name;
		* =>
			glitch := m.buttons;
			do {
				m = <-mc;
			} while(m.buttons);
			if(glitch == 4)
				return mn.opts[mn.last].name;
			if(glitch == 1)
				return "scroll";
			return nil;
		}
	1 =>
		return "scroll";
	* =>
		do {
			m = <-mc;
		} while(m.buttons);
		return nil;
	}
}

Menu.run(mn: self ref Menu, m: ref Cpointer, mc: chan of ref Cpointer): string
{
	at := m.xy;
	if(mn.opts[0].si == nil)
		mn.mk();
	min := at.add((-mn.r.dx()/2, -mn.r.dy()/2));
	smin := min;
	if(smin.x < win.image.r.min.x)
		smin.x = win.image.r.min.x;
	if(smin.y < win.image.r.min.y)
		smin.y = win.image.r.min.y;
	if(smin.y + mn.r.dy() > win.image.r.max.y)
		smin.y = win.image.r.max.y - mn.r.dy();
	if(smin.x + mn.r.dx() > win.image.r.max.x)
		smin.x = win.image.r.max.x - mn.r.dx();
	if(!smin.eq(min)){
		min = smin;
		nm := min.add((mn.r.dx()/2, mn.r.dy()/2));
		m = ref *m;
		win.wmctl("ptr " + string nm.x + " " + string nm.y);
		m.xy.x = nm.x; m.xy.y = nm.y;	# adjust or φ will be wrong
	}
	mn.sr = mn.saved.r.addpt(min);
	mn.saved.draw(mn.r, win.image, nil, min);
	mn.draw(min, mn.last, 1);
	opt := mn.mouse(min, m, mc);
	win.wmctl("ptr " + string at.x + " " + string at.y);
	win.image.draw(mn.r.addpt(min), mn.saved, nil, (0,0));
	return opt;
}
