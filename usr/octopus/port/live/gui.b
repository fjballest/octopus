implement Gui;
include "mods.m";
mods, debug, win, tree: import dat;

include "env.m";
	env: Env;
Menu: import menus;
Ptag, Pline, Qatom, Qcol, Qrow, Pedit, Pdirties, Pdead, Pdirty,
intag, Playout, Pmore, Pshown, Panel: import wpanel;
panelctl, panelkbd, panelmouse, tagmouse, Tree: import wtree;
usage: import arg;

fonts: array of ref Draw->Font;
lxy: Point;

terminate(msg: string)
{
	exiting = 1;
	if(msg != nil){
		initscr();
		txt := "Exiting: " + msg;
		r := win.image.r;
		pt := Point((r.min.x+r.max.x)/2, r.min.y+r.dy()/4);
		font := getfont("L");
		pt.x -= font.width(txt)/2;
		win.image.text(pt, cols[TEXT], (0,0), font, txt);
		sys->sleep(5 * 1000);
	}
	kill(sys->pctl(0, nil),"killgrp");	# be sure to quit
	win.wmctl("exit");
	exit;
}

focusev(e: string): int
{
	Focusev: con "haskbdfocus ";
	
	l := len Focusev;
	if(len e > l && e[0:l] == Focusev)
		return (e[l] == '1');
	return -1;
}

lastxy(): Point
{
	return lxy;
}

winproc(w: ref Window, resizec: chan of int, mfc: chan of int, mc: chan of ref Cpointer)
{
	ev: string;
	img:= w.image;
	for(;;){
		alt {
		ev = <- w.ctl =>
			if(debug['W'])
				fprint(stderr, "wctl: %s\n", ev);
		ev = <- w.ctxt.ctl =>
			if(debug['W'])
				fprint(stderr, "wctx: %s\n", ev);
			if((f := focusev(ev)) >= 0)
				mfc <-= f;
		}
		if(ev == "exit"){
			if(debug['W'])
				fprint(stderr, "exit\n");
			# do not call w.wmctl("exit") ourselves, let the client do it.
			# (o/live might have to do some cleanup)
			mc <-= nil;
			exit;
		}
		w.wmctl(ev);
		if(w.image != img){
			if(debug['W'])
				fprint(stderr, "resize\n");
			img = w.image;
			resizec <-= 0;
		}
	}
}

nbrecvp(c: chan of ref Pointer): ref Pointer
{
	r: ref Pointer;
	r = nil;
	alt {
	r = <-c => ;
	* =>	;
	}
	return r;
}

mouseproc(w: ref Window, mfc: chan of int, mc: chan of ref Cpointer)
{
	Tdouble: con 500;

	pressmsec := sys->millisec();
	press2msec := pressmsec;
	dclick := pressb := 0;
	lm := ref Pointer(0, Point(0, 0), 0);
	ignore := 0;
Loop:
	for(;;){
		alt {
		wmfocus := <- mfc =>
			ignore = wmfocus == 0;
		m := <- w.ctxt.ptr =>
			lxy = m.xy;
			m.buttons &= 16rFF;
			if(w.pointer(*m)) 
				continue Loop;
			if(ignore)
				continue Loop;
			# insert no-button events between click-a/rlse-a/click-b
			if(lm.buttons && m.buttons && !(m.buttons&lm.buttons))
				mc <-= ref Cpointer(0, lm.xy, lm.msec, 0);
	
			# flag double clicks
			if(!lm.buttons && m.buttons){
				if(m.buttons == pressb){
					if(m.msec - pressmsec < Tdouble)
						dclick = 1;
					if(m.msec - press2msec < 2*Tdouble)
						dclick = 2;
				}
				pressb = m.buttons;
				press2msec = pressmsec;
				pressmsec = m.msec;
			}
			cm := ref Cpointer(m.buttons, m.xy, m.msec, 0);
			if(dclick){
				if(dclick == 2)
					cm.flags = CMtriple;
				else
					cm.flags = CMdouble;
				if(!m.buttons)
					dclick = 0;
			}
	
			# drop extra events received while processing
			# deliver just the last position
			while((m2 := nbrecvp(w.ctxt.ptr)) != nil){
				lxy = m2.xy;
				m2.buttons &= 16rFF;
				if(m2.buttons == cm.buttons){
					cm.xy = m.xy;
					cm.msec = m.msec;
				} else {
					mc <-= cm;
					lm = m;
					m = m2;
					break;
				}
			}
			if(m2 == nil){
				mc <-= cm;
				lm = m;
			}
		}
	}
}

nbrecvul(c: chan of int): int
{
	r := 0;
	alt {
	r = <-c => ;
	* =>	;
	}
	return r;
}

# just provides some buffering in kbdc
kbdproc(w: ref Window, kbdc: chan of int)
{
	for(;;){
		r := <- w.ctxt.kbd;
		if(r != 0)
			kbdc <-= r;
	}
}

Cpointer.text(m: self ref Cpointer): string
{
	flags:= " ";
	if(m.flags&CMdouble)
		flags = "d";
	return sprint("%s %x [%d %d] %d", flags, m.buttons, m.xy.x, m.xy.y, m.msec);
}

cookclick(m: ref Cpointer, mc: chan of ref Cpointer): int
{
	b:= m.buttons;
	do {
		m = <-mc;
	} while(m.buttons == b);
	if(m.buttons == 0)
		return 1;
	do {
		m = <-mc;
	} while(m.buttons != 0);
	return 0;
}

getfont(name: string): ref Font
{
	case name[0] {
	'r' or 'R' =>	return fonts[FR];
	'b' or 'B' =>	return fonts[FB];
	'l' or 'L' =>	return fonts[FL];
	't' or 'T' =>	return fonts[FT];
	'i' or 'I' =>	return fonts[FI];
	's' or 'S' =>	return fonts[FS];
	* =>			return nil;
	}
}

# Images are rows of 16x16 bits.
# two bytes per row, big endian.
# first, the mask (bits to clear)
# then, the image (bits to set)

arrowbits := array[64] of {
	byte 16rC0, byte 16r00,
	byte 16rE0, byte 16r00,
	byte 16rF0, byte 16r00,
	byte 16rF8, byte 16r00,
	byte 16rFC, byte 16r00,
	byte 16rFE, byte 16r00,
	byte 16rFF, byte 16r00,
	byte 16rFF, byte 16r80,
	byte 16rFF, byte 16rC0,
	byte 16rFF, byte 16rE0,
	byte 16rFF, byte 16rE0,
	byte 16rFE, byte 16rC0,
	byte 16rF8, byte 16r00,
	byte 16r60, byte 16r00,
	byte 16r00, byte 16r00,
	byte 16r00, byte 16r00,

	byte 16r00, byte 16r00,
	byte 16r40, byte 16r00,
	byte 16r60, byte 16r00,
	byte 16r70, byte 16r00,
	byte 16r78, byte 16r00,
	byte 16r7C, byte 16r00,
	byte 16r6E, byte 16r00,
	byte 16r67, byte 16r00,
	byte 16r6B, byte 16r80,
	byte 16r6D, byte 16rC0,
	byte 16r6E, byte 16rC0,
	byte 16r68, byte 16r00,
	byte 16r60, byte 16r00,
	byte 16r00, byte 16r00,
	byte 16r00, byte 16r00,
	byte 16r00, byte 16r00,

};

waitingbits := array[64] of {
	byte 16rC0, byte 16rFE,
	byte 16rE1, byte 16rFF,
	byte 16rF0, byte 16rFE,
	byte 16rF8, byte 16r3C,
	byte 16rFC, byte 16r7C,
	byte 16rFE, byte 16rFE,
	byte 16rFF, byte 16r7E,
	byte 16rFF, byte 16rBF,
	byte 16rFF, byte 16rDE,
	byte 16rFF, byte 16rFF,
	byte 16rFF, byte 16rEE,
	byte 16rFE, byte 16rEF,
	byte 16rF8, byte 16r07,
	byte 16r60, byte 16r0F,
	byte 16r00, byte 16r06,
	byte 16r00, byte 16r00,

	byte 16r00, byte 16r00,
	byte 16r40, byte 16rFE,
	byte 16r60, byte 16r04,
	byte 16r70, byte 16r18,
	byte 16r78, byte 16r20,
	byte 16r7C, byte 16r7E,
	byte 16r6E, byte 16r00,
	byte 16r67, byte 16r1E,
	byte 16r6B, byte 16r84,
	byte 16r6D, byte 16rCE,
	byte 16r6E, byte 16rC0,
	byte 16r68, byte 16r06,
	byte 16r60, byte 16r02,
	byte 16r00, byte 16r06,
	byte 16r00, byte 16r00,
	byte 16r00, byte 16r00,

};

# Cursors are taken from acme
dragbits := array[64] of {
	byte 16rC0, byte 16r00,
	byte 16rE0, byte 16r00,
	byte 16rF0, byte 16r00,
	byte 16rF8, byte 16r00,
	byte 16rFC, byte 16r38,
	byte 16rFE, byte 16r7C,
	byte 16rFF, byte 16rFE,
	byte 16rFF, byte 16rFF,
	byte 16rFF, byte 16rFF,
	byte 16rFF, byte 16rFF,
	byte 16rFF, byte 16rFF,
	byte 16rFF, byte 16rFF,
	byte 16rF9, byte 16rFF,
	byte 16r60, byte 16rFE,
	byte 16r00, byte 16r7C,
	byte 16r00, byte 16r38,

	byte 16r00, byte 16r00,
	byte 16r40, byte 16r00,
	byte 16r60, byte 16r00,
	byte 16r70, byte 16r00,
	byte 16r78, byte 16r00,
	byte 16r7C, byte 16r38,
	byte 16r6E, byte 16r44,
	byte 16r67, byte 16rBA,
	byte 16r6B, byte 16rA9,
	byte 16r6D, byte 16rC5,
	byte 16r6F, byte 16rC5,
	byte 16r69, byte 16r29,
	byte 16r60, byte 16rBA,
	byte 16r00, byte 16r44,
	byte 16r00, byte 16r38,
	byte 16r00, byte 16r00,
};

resizebits := array[64] of {
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF, 
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF,
	 byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F,
	 byte 16rF8, byte 16r1F,
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF,
	 byte 16rFF, byte 16rFF,

	 byte 16r00, byte 16r00,
	 byte 16r7F, byte 16rFE,
	 byte 16r7F, byte 16rFE,
	 byte 16r7F, byte 16rFE,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r70, byte 16r0E,
	 byte 16r7F, byte 16rFE,
	 byte 16r7F, byte 16rFE,
	 byte 16r7F, byte 16rFE,
	 byte 16r00, byte 16r00,
};

setcursor(x: int)
{
	Hex: con "0123456789abcdef";
	buf: array of byte;
	s := "cursor -1 -1 16 32 ";
	case x {
	Arrow =>				# how to hide the cursor?
		buf = arrowbits;
	Drag =>
		buf = dragbits;
	Waiting =>
		buf = waitingbits;
	Resize =>
		buf = resizebits;
	}
	for(i := 0; i < len buf; i++){
		c := int buf[i];
		s[len s] = Hex[c >> 4];
		s[len s] = Hex[c & 16rf];
 	}
	win.wmctl(s);
}

borderkind(p: ref Panel): int
{
	if(!(p.flags&Playout))
		return Bany;
	depth := p.depth;
	if(p.rowcol == Qatom && p.depth > 0)
		depth--;
	case depth {
	0 =>	return B0;
	1 =>	return B1;
	2 =>	return B2;
	* =>		return Bany;
	}
}

drawtag(p: ref Panel)
{
	if(!(p.flags&Pshown))
		return;
	k := borderkind(p);
	dirty := p.flags&(Pdirty|Pdirties);
	fl := p.flags&Pmore;
	if(dirty != 0)
		fl |= Pdirty;
	r := Rect(p.rect.min, (p.rect.min.x+Tagwid, p.rect.min.y+Taght));
	rr:= r;
	rr.max.y += Taght;
	(r, nil) = r.clip(p.rect);
	(rr, nil) = rr.clip(p.rect);
	case fl {
	0 =>		win.image.draw(r, bord[Btag][k], nil, (0,0));
	Pmore =>		win.image.draw(rr, bord[Bmtag][k], nil, (0,0));
	Pdirty =>		win.image.draw(r, bord[Bdtag][k], nil, (0,0));
	Pmore|Pdirty =>	win.image.draw(rr, bord[Bdmtag][k], nil, (0,0));
	}
	
}

minpt(p1, p2: Point): Point
{
	if(p1.x > p2.x)
		p1.x = p2.x;
	if(p1.y > p2.y)
		p1.y = p2.y;
	return p1;
}

maxpt(p1, p2: Point): Point
{
	if(p1.x < p2.x)
		p1.x = p2.x;
	if(p1.y < p2.y)
		p1.y = p2.y;
	return p1;
}


panelback(p: ref Panel): ref Image
{
	if(p == nil)
		return win.display.color(Draw->Red); # Signal the bug, but proceed
	case borderkind(p) {
	B0 =>
		return cols[BACK0];
	B1 =>
		return cols[BACK1];
	B2 =>
		return cols[BACK2];
	* =>
		return cols[BACK];
	}
}

# Borders and colors should be images with nice textures, not
# handcrafted colors. But we have got what we have.
# All this should probably be reworked.

loadcols()
{
	if(win == nil || win.display == nil || win.image == nil){
		kill(sys->pctl(0, nil), "killgrp");
		error("o/live: gui: no image");
	}
	dpy := win.display;
	o1 := draw->setalpha(Draw->White, 5);
	shadow1 := dpy.newimage(Rect((0,0),(2,2)), win.image.chans, 1, o1);
	o2 := draw->setalpha(Draw->White, 10);
	shadow2 := dpy.newimage(Rect((0,0),(2,2)), win.image.chans, 1, o2);
	o3 := draw->setalpha(Draw->White, 15);
	shadow3 := dpy.newimage(Rect((0,0),(2,2)), win.image.chans, 1, o3);

	cols = array[MAXCOL] of ref Image;
	cols[BACK] = dpy.colormix(Draw->Paleyellow, Draw->White);
	cols[HIGH] = dpy.colormix(Draw->Yellow, int 16rD0D0D0FF);
	cols[BORD] = dpy.color(int 16r501500FF);
	cols[TEXT] = dpy.black;
	cols[HTEXT] = dpy.black;
	cols[BACK0] = dpy.colormix(Draw->Paleyellow, Draw->White);
	cols[BACK0].draw(cols[BACK0].r, cols[TEXT], shadow3, (0,0));
	cols[BACK1] = dpy.colormix(Draw->Paleyellow, Draw->White);
	cols[BACK1].draw(cols[BACK1].r, cols[TEXT], shadow2, (0,0));
	cols[BACK2] = dpy.colormix(Draw->Paleyellow, Draw->White);
	cols[BACK2].draw(cols[BACK2].r, cols[TEXT], shadow1, (0,0));
	cols[HBORD] = dpy.color(Draw->Yellow);
	cols[FBORD] = dpy.color(int 16rFFAA00FF);
	cols[SET] = dpy.color(int 16r884400FF);
	cols[CLEAR] = cols[BACK];
	cols[MSET] = dpy.color(int 16rFFF000FF);
	cols[MCLEAR] = dpy.colormix(Draw->Paleyellow, Draw->White);
	cols[MBACK] = dpy.color(int 16r753500FF);
	o := draw->setalpha(Draw->White, 60);
	cols[SHAD] = dpy.newimage(Rect((0,0),(2,2)), win.image.chans, 1, o);
}

loadborders(k: int)
{
	dpy := win.display;
	c := win.image.chans;
	back: ref Image;

	if(bord == nil){
		bord = array[NBORD] of array of ref Image;
		for(i := 0; i < len bord; i++)
			bord[i] = array [NBKIND] of ref Image;
	}
	case k {
	B0 =>
		back = cols[BACK0];
	B1 =>
		back = cols[BACK0];
	B2 =>
		back = cols[BACK1];
	* =>
		back = cols[BACK2];
	}
	rr := Rect((0, 0), (Tagwid, 2*Taght));
	irr := rr.inset(1);
	r := Rect((0, 0), (Tagwid, Taght));
	ir := r.inset(1);

	bord[Bback][k] = back;
	bord[Btag][k] = dpy.newimage(rr, c, 0, Draw->White);
	bord[Btag][k].draw(r, cols[BORD], nil, (0,0));
	bord[Bdtag][k] = dpy.newimage(rr, c, 0, Draw->White);
	bord[Bdtag][k].draw(r, cols[BORD], nil, (0,0));
	bord[Bdtag][k].draw(ir, cols[HBORD], nil, (0,0));
	bord[Bmtag][k] = dpy.newimage(rr, c, 0, Draw->White);
	bord[Bmtag][k].draw(rr, cols[BORD], nil, (0,0));
	bord[Bdmtag][k] = dpy.newimage(rr, c, 0, Draw->White);
	bord[Bdmtag][k].draw(rr, cols[BORD], nil, (0,0));
	bord[Bdmtag][k].draw(irr, cols[HBORD], nil, (0,0));
}

loadfonts()
{
	dpy := win.display;
	fonts = array[NFONT] of ref Font;
	fonts[FR] = Font.open(dpy, "/fonts/charon/plain.normal.font");
	fonts[FB] = Font.open(dpy, "/fonts/charon/bold.normal.font");
	# cw.normal.font is bigger than plain.normal.font; use small:
	fonts[FT] = Font.open(dpy, "/fonts/charon/cw.small.font");
	fonts[FL] = Font.open(dpy, "/fonts/charon/plain.vlarge.font");
	fonts[FS] = Font.open(dpy, "/fonts/charon/plain.small.font");
	fonts[FI] = Font.open(dpy, "/fonts/charon/italic.normal.font");

	for(i := 0; i < len fonts; i++)
		if(fonts[i] == nil)
			error("can't load fonts");
}

writesnarf(s: string)
{
	fd := open("/chan/snarf", OWRITE|OTRUNC);
	if(fd != nil)
		fprint(fd, "%s", s);
	fd = open("/dev/snarf", OWRITE|OTRUNC);
	if(fd != nil)
		fprint(fd, "%s", s);
}


readsnarf(): string
{
	# BUG: should read only if qid changed

	fd := open("/chan/snarf",  OREAD);
	if(fd == nil)
		fd = open("/dev/snarf", OREAD);
	if(fd == nil)
		return "";
	data := readfile(fd);
	if(data == nil || len data == 0)
		return "";
	else
		return string data;
}

initscr()
{
	w := dat->win;
	w.image.draw(w.image.r, cols[BACK], nil, (0,0));
	fd := open("octopus.img", OREAD);
	if(fd == nil)
		fd = open("/lib/o/octopus.img", OREAD);
	if(fd != nil && (logo := w.display.readimage(fd)) != nil){
		logo.border(logo.r, 1, cols[BORD], (0,0));
		pt := Point((w.image.r.dx() - logo.r.dx())/2, (w.image.r.dy() - logo.r.dy())/2);
		r := logo.r.addpt(pt);
		r = r.addpt(w.image.r.min);
		w.image.draw(r, logo, nil, (0,0));
	}
}

debugging(): int
{
	for(i := 0; i < len debug; i++)
		if(debug[i] != 0)
			return 1;
	return 0;
}

init(d: Livedat, ctx: ref Draw->Context): (chan of int, chan of ref Cpointer, chan of int)
{
	dat = d;
	initmods();
	if(ctx == nil)
		ctx = wmcli->makedrawcontext();
	w := d->win = wmcli->window(ctx, "o/live", Wmclient->Appl);
	sz := w.displayr.size();
	if(debugging()){
		sz.x /= 2;
		sz.y /= 2;
	} else
		sz = sz.sub((30,30));
	r := Rect(Point(0, 0), sz);
	w.reshape(r);
	w.onscreen("place");
	w.startinput("kbd"::"ptr"::nil);
	mousec := chan[20] of ref Cpointer;
	mfc := chan of int;
	kbdc := chan[20] of int;
	resizec := chan of int;
	spawn mouseproc(w, mfc, mousec);
	spawn winproc(w, resizec, mfc, mousec);
	spawn kbdproc(w, kbdc);
	loadcols();
	loadborders(B0);
	loadborders(B1);
	loadborders(B2);
	loadborders(Bany);
	loadfonts();
	initscr();
	return (kbdc, mousec, resizec);
}
