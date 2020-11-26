#
# Text panel.
# Text is handled by the Tblks module.
# Undo/redo is handled by a separate Tundo module.
# Drawing is handled by Tframe, which is also in charge of maintaining the
# selection and the position of the text shown in the panel.

implement Pimpl;
include "mods.m";
mods, debug, win, tree: import dat;
Menu: import menus;
setcursor, Waiting, Arrow,
getfont, Cpointer, cols, panelback, maxpt, cookclick, drawtag,
BACK,TEXT, readsnarf, Inset, terminate, writesnarf, 
SET, CLEAR, SHAD, BORD, CMtriple, CMdouble : import gui;
Pscroll, Ptag, Pline, Pedit, Pshown, Pdead, Pdirty, Pnosel, Ptbl, Predraw, Pinsist, Ptemp,
intag, nth, Panel, All: import wpanel;
panelctl, panelkbd, panelmouse, tagmouse, Treeop, Tree: import wtree;
usage: import arg;
randomint, ReallyRandom: import random;

include "lists.m";
	lists: Lists;
	append, reverse: import lists;
include "tblks.m";
	tblks: Tblks;
	fixpos,  fixposins, fixposdel, dtxt, strstr, Maxline, Tblk, strchr, Str: import tblks;
include "tundo.m";
	tundo: Tundo;
	Edit, Edits: import tundo;
include "tframe.m";
	tframe:	Tframe;
	Frame:	import tframe;

Ptext: adt {
	blks:	ref Tblks->Tblk;	# sequence of text blocks being edited.
	edits:	ref Tundo->Edits;	# edit operations for sync, undo, redo.
	f:	ref Tframe->Frame;	# nil or initialized frame
	s0:	int;		# 1st sel. point, to extend sel.
	mlast:	int;		# last option used in its menu
	tabtext:	string;		# for tbls, the original text, as updated.
	nlines:	int;		# nb. of lines in text (to compute maxsz)
	id:	int;		# tag to identify our own ins/del events
	editing:	int;		# edstart issued.

	new:	fn(): ref Ptext;
	gotopos:	fn(pi: self ref Ptext, npos: int): int;
	wordat:	fn(pi: self ref Ptext, pos: int, long: int, selok: int): (int, int);

	dump:	fn(pi: self ref Ptext);
};

panels: array of ref Ptext;
textmenu: ref Menu;

pimpl(p: ref Panel): ref Ptext
{
	if(p.implid < 0 || p.implid > len panels || panels[p.implid] == nil)
		panic("draw: bug: no impl");
	return panels[p.implid];
}

init(d: Livedat): string
{
	prefixes = list of {"text:", "button:", "label:", "tag:", "tbl:"};
	dat = d;
	initmods();
	dat = d;
	lists = load Lists Lists->PATH;
	if(lists == nil)
		return sprint("loading %s: %r", Lists->PATH);
	tblks = load Tblks Tblks->PATH;
	if(tblks == nil)
		return sprint("loading %s: %r", Tblks->PATH);
	tframe = load Tframe Tframe->PATH;
	if(tframe == nil)
		return sprint("loading %s: %r", Tframe->PATH);
	tundo= load Tundo Tundo->PATH;
	if(tundo == nil)
		return sprint("loading %s: %r", Tundo->PATH);
	tblks->init(sys, str, err, debug['T']);
	tframe->init(dat, tblks, debug['F']);
	tundo->init(sys, err, lists, tblks, debug['T']);
	return nil;
}

nullptext: Ptext;
Ptext.new(): ref Ptext
{
	pi := ref nullptext;
	pi.id = randomint(ReallyRandom)%16rFFFF;
	return pi;
}

Ptext.gotopos(pi: self ref Ptext, npos: int): int
{
	if(npos == pi.f.pos)
		return pi.f.pos;
	s := pi.blks.pack();
	npos = fixpos(npos, len s.s);
	if(len s.s > 0 && npos == len s.s)	# show something
		npos--;
	if(npos > 0){
		n := s.findr(npos, '\n', Maxline);# just past the last \n
		if(n >= 0){
			if(n > 0 && n == '\n')
				n++;
			npos = n;
		} else if(npos < len s.s)	# scrolling within the first line.
			npos = 0;
	}
	return npos;
}

# Taken from acme
isalnum(c : int) : int
{
	# Hard to get absolutely right.  Use what we know about ASCII
	# and assume anything above the Latin control characters is
	# potentially an alphanumeric.
	#
	if(c <= ' ')
		return 0;
	if(16r7F<=c && c<=16rA0)
		return 0;
	if(strchr("!\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~", c) >= 0)
		return 0;
	return 1;
}

iswordchar(r: int, long: int): int
{
	if(isalnum(r) || strchr("0123456789_", r) >= 0)
		return 1;
	if(long && strchr("|&?=!%.-+/:", r) >= 0)
		return 1;
	return 0;
}


isparen(set: string, r: int): int
{
	i := strchr(set, r);
	if(i >= 0)
		return i + 1;
	else
		return 0;
}

#  Returns the word at pos.
#  If we are looking at the end of line, we pretend we look right
#  before it. In any case:
# 	The word is the selection when it exists and selok.
#  	It is the longest set of <wordchar>s if pos at <wordchar>
#		(if long,  |&?=.-+/: are also considered as word chars)
#  	It is the text between {} [] '' "" () if pos is at delim.
#  	It is the current line otherwise (if pos at blank)
#
Ptext.wordat(pi: self ref Ptext, pos: int, long: int, selok: int): (int, int)
{
	ss := pi.f.ss;
	se := pi.f.se;
	lparen := "{[(«<“";
	rparen :=  "}])»>”";
	paren := "\"'`";
	s := pi.blks.pack();
	nr := len s.s;
	if(pos >nr)
		pos = nr;
	if(pos == nr && pos > 0)
		pos--;
	spos := epos := pos;
	if(nr == 0)
		return (spos, epos);
	if(selok && pos >= ss && pos <= se && ss != se)
		return (ss, se);
	if(iswordchar(s.s[pos], long)){
		while(spos > 0 && iswordchar(s.s[spos], long))
			spos--;
		if(spos > 0)
			spos++;
		while(epos < nr && iswordchar(s.s[epos], long))
			epos++;
	} else if(pp := isparen(paren, s.s[pos])){
		spos++;
		for(epos = spos; epos < nr; epos++)
			if(isparen(paren, s.s[epos]) == pp)
				break;
	} else if(pp = isparen(lparen, s.s[pos])){
		nparen := 1;
		spos++;
		for(epos = spos; epos < nr; epos++){
			if(isparen(lparen, s.s[epos]) == pp)
				nparen++;
			if(isparen(rparen, s.s[epos]) == pp)
				nparen--;
			if(nparen <= 0){
				break;
			}
		}
	} else if(pp = isparen(rparen, s.s[pos])){
		nparen := 1;
		if(spos > 0)
		for(spos--; spos > 0; spos--){
			if(isparen(rparen, s.s[spos]) == pp)
				nparen++;
			if(isparen(lparen, s.s[spos]) == pp)
				nparen--;
			if(nparen <= 0){
				spos++;
				break;
			}
		}
	} else { # pos at blank
		if(s.s[spos] == '\n' && spos > 0 && s.s[spos-1] != '\n'){
			# click at right part of line; step back
			# so that expanding leads to previous line
			spos--;
		}
		while(spos > 0 && s.s[spos-1] != '\n')
			spos--;
		while(epos < nr && s.s[epos] != '\n')
			epos++;
		if(epos < nr)
			epos++;	# include \n
	}
	if(spos < 0 || epos < 0 || epos < spos || epos > nr)
		panic(sprint("spos/epos bug: %d %d %d\n", spos, epos, nr));
	return (spos, epos);
}

Ptext.dump(pi: self ref Ptext)
{
	pi.blks.dump();
	if(debug['T'] > 1)
		pi.edits.dump();
	if(debug['F'] > 1)
		pi.f.dump();
}

settextsize(p: ref Panel): int
{
	if(p.resized)
		return 0;
	pi := pimpl(p);
	osz := Rect(p.minsz, p.maxsz);
	p.minsz = Point(p.font.height, p.font.height);
	p.maxsz = Point(All, All);
	s := pi.blks.pack();
	if(p.flags&Pline){
		p.maxsz.y = p.font.height;
		if(!(p.flags&Pedit) && len s.s > 0)
			p.minsz.x = p.maxsz.x = p.font.width(s.s) + 2;
	} else {
		p.minsz = Point(p.font.height*2,p.font.height*2+2);
		if(pi.nlines != 0){
			n := pi.nlines + 2;
			p.maxsz.y =  p.font.height * n + 2;
		}
	}
	nsz := Rect(p.minsz, p.maxsz);
	if(debug['L'] > 1)
		fprint(stderr, "textsz\t%-20s\tmin: %03dx%03d" +
			" max: %03dx%03d %d lines\n", p.name,
			p.minsz.x, p.minsz.y,
			p.maxsz.x, p.maxsz.y, pi.nlines);
	return !osz.eq(nsz);
}

Mopen, Mfind, Mexec, Mclose, Mwrite, Mpaste: con iota;
pinit(p: ref Panel)
{
	if(tree == nil)
		tree = dat->tree;
	if(textmenu == nil){
		a := array[] of {"Open", "Find", "Exec", "Close", "Write", "Paste"};
		textmenu = Menu.new(a);
	}
	for(i := 0; i < len panels; i++)
		if(panels[i] == nil)
			break;
	if(i == len panels){
		npanels := array[i+16] of ref Ptext;
		npanels[0:] = panels;
		for(j := len panels; j < len npanels; j++)
			npanels[j] = nil; # paranoia
		panels = npanels;
	}
	p.implid = i;
	pi := panels[i] = Ptext.new();
	pi.edits = Edits.new();
	pi.mlast = Mexec;
	p.flags &= ~(Pline|Pedit);
	tab := 8;
	if(len p.name > 3 && p.name[0:3] == "tbl"){
		p.flags |= Ptbl|Pedit|Ptemp;
		pi.tabtext = "[empty]";
		pi.mlast = Mopen;
		tab = 3;
	} else if(len p.name > 4 && p.name[0:4] == "text"){
		p.flags |= Pedit;
		pi.mlast = Mopen;
	} else if(len p.name > 3 && p.name[0:3] == "tag")
		p.flags |= Pline|Pedit|Ptemp;
	else
		p.flags |= Pline|Ptemp;
	s := "";
	if(p.flags&Pline){
		p.font = getfont("B");
		(nil, n) := splitl(p.name, ":");
		if(n != nil){
			n = n[1:];
			(s, nil) = splitl(n, ".");
			if(s == nil)
				s = nil;
		}
	} else
		p.font = getfont("R");
	pi.blks = Tblk.new(s);
	if(settextsize(p) != 0)
		spawn newlayout();
	# create frame w/o image. it maintains selection, mostly.
	# pdraw will attach an image to the frame and reset its size.
	pi.f = Frame.new(Rect((0, 0), p.minsz), nil, p.font, gui->cols, !(p.flags&Pline));
	pi.f.debug = debug['F'];
	pi.f.tabsz = tab;
	pi.f.showsel = p.flags&Pedit;
	pi.f.init(pi.blks, pi.f.pos);
	pi.s0 = pi.f.ss;
}

pterm(p: ref Panel)
{
	if(p.implid != -1){
		pi := pimpl(p);
		panels[p.implid] = nil; 
		p.implid = -1;
		pi.f = nil;
		pi.edits = nil;
		pi.blks = nil;
	}
}

dirty(p: ref Panel, set: int)
{
	if(p.flags&Ptemp)
		return;
	old := p.flags;
	if(set)
		p.flags |= Pdirty;
	else
		p.flags &= ~Pdirty;
	if(old != p.flags){
		if(set){
			pi := pimpl(p);
			pi.mlast = Mwrite;
			p.fsctl("dirty", 1);
		} else
			p.fsctl("clean", 1);
		tree.tags();
	}
}

tab(p: ref Panel)
{
	pi := pimpl(p);
	(n, toks) := tokenize(pi.tabtext, "\t\n");
	if(n <= 0)
		return;
	wl := array[n] of string;
	wwl := array[n] of int;
	for(i := 0; i < n; i++){
		wl[i] = hd toks;
		toks = tl toks;
	}
	mint := pi.f.spwid;
	maxt := pi.f.tabwid;
	colw := 0;
	maxw := 0;
	for(i = 0; i < n; i++){
		wwl[i] = p.font.width(wl[i]);
		if(maxw < wwl[i])
			maxw = wwl[i];
	}
	spwid := p.font.width(" ");
	for(i = 0; i < n; i++)
		while(wwl[i] < maxw){
			wl[i] += " ";
			wwl[i] += spwid;
		}
	for(i=0; i<n; i++){
		w := p.font.width(wl[i]);
		wwl[i]  = w;
		if(maxt-w%maxt < mint)
			w += mint;
		if(w % maxt)
			w += maxt-(w%maxt);
		if(w > colw)
			colw = w;
	}
	ncol := 1;
	if(colw != 0)
		ncol = p.rect.dx()/colw;	# can't use pi.f.r, because
	if(ncol < 1)			# frame may be using an old rectangle.
		ncol = 1;
	nrow := (n+ncol-1)/ncol;

	ns := "";
	for(i=0; i<nrow; i++){
		for(j:=i; j<n; j+=nrow){
			ns += wl[j];
			if(j+nrow >= n)
				break;
			else
				ns += "\t";
		}
		ns += "\n";
	}
	pi.blks = Tblk.new(ns);
	pi.f.init(pi.blks, pi.f.pos);
	pi.s0 = pi.f.ss;
	pi.nlines = nrow+1;
	settextsize(p);
}

pdraw(p: ref Panel)
{
	pi := pimpl(p);
	if(!(p.flags&Pshown)){
		pi.f.i = nil;
		return;
	}
	w := dat->win;
	if(p.flags&Ptbl){
		pi.f.i = nil;	# don't draw using old rectangle.
		tab(p);
	}
	if(pi.f.i == nil || !p.rect.eq(p.orect)){
		rd := pi.f.resize(p.rect, w.image);
		# only when we draw do we know the
		# actual rectangle used. If the entire frame
		# fits now we should show it all.
		if(pi.f.sz.y >= pi.nlines && pi.f.pos != 0)
			pi.f.init(pi.blks, pi.gotopos(0));
		pi.f.redraw(rd);
	} else {
		pi.f.i = w.image;
		pi.f.redraw(0);
	}
	settextsize(p);
	if(p.flags&Pline)	# maybe there's more room
		pi.f.fill();	# for text; fill it up.
	if(p.flags&Ptag)
		drawtag(p);
}

stringlines(s: string): int
{
	nc := n := 0;
	for(i := 0; i < len s; i++)
		if(s[i] == '\n' || nc == Maxline){
			n++;
			nc = 0;
		} else
			nc++;
	return n;
}

pupdate(p: ref Panel, d: array of byte)
{
	pi := pimpl(p);
	s := pi.blks.pack();
	ns := string d;
	nr := len s.s;
	if(!(p.flags&Pshown)){
		pi.f.i = nil;	# avoid drawing
		p.flags |= Predraw;
	}
	if(p.flags&Ptbl){
		pi.tabtext = ns;
		pi.blks = Tblk.new(ns);
		pi.f.i = nil;		# pdraw tabs
		p.flags |= Predraw;	# the text.
		pi.f.init(pi.blks, 0);
	} else if(ns != "" && str->prefix(s.s, ns)){
		(ss, se) := (pi.f.ss, pi.f.se);
		ns = ns[nr:];
		pi.blks.ins(ns, nr);
		pi.f.ins(nr, len ns);
		if(p.flags&Pedit)
			pi.f.sel(ss, se);
	} else {
		pi.blks = Tblk.new(ns);
		pi.f.init(pi.blks, pi.f.pos);
	}
	pi.edits = Edits.new();
	s = pi.blks.pack();
	pi.nlines = stringlines(s.s);
	if(p.flags&Ptbl)		# conservative estimate
		pi.nlines /= 3;	# assume three columns
	if(settextsize(p) != 0)
		spawn newlayout();
	nsel := -1;
	if((p.flags&Pline) || !(p.flags&Pedit) || (p.flags&Pscroll))
		nsel = len s.s;
	if(!(p.flags&Ptbl) && nsel >= 0 && p.flags&Pscroll && pi.nlines > 2){
		movetoshow(p, nsel);
		pi.f.sel(nsel, nsel);
		pi.s0 = pi.f.ss;
	}
}

printdiff(s: string, ftext: string)
{
	l := len s;
	if(l > len ftext)
		l = len ftext;
	for(i := 0; i < l - 1 && s[i] == ftext[i]; i++)
		;
	ui := i;
	if(i > 15)
		i -= 15;
	else
		i = 0;
	sj := len s - 1;
	fj := len ftext - 1;
	while(sj > 0 && fj > 0 && s[sj] == ftext[fj]){
		sj--; fj--;
	}
	if(sj + 15 < len s)
		sj += 15;
	else
		sj = len s;
	if(fj + 15 < len ftext)
		fj += 15;
	else
		fj = len ftext;
	fprint(stderr, "o/live and o/mero text differs: pos %d:\n", ui);
	fprint(stderr, "text[%s]\n\nfile[%s]\n\n", s[i:sj], ftext[i:fj]);
	fprint(stderr, "%d and %d bytes\n", len s, len ftext);
}

syncchk(p: ref Panel, tag: string)
{
	if(debug['S']){
		# double check that we are really synced with the FS.
		pi := pimpl(p);
		fname := "/mnt/ui" + p.path + "/data";
		fd := open(fname, OREAD);
		data := readfile(fd);
		if(data != nil){
			ftext := string data;
			s := pi.blks.pack().s;
			if(s != ftext){
				pi.dump();
				pi.edits.dump();
				printdiff(s, ftext);
				panic(sprint("o/live: %s: insdel bug", tag));
			}
		}
		# double check that the text in the frame is also in sync.
		pi.f.chk();
	}
}

# For tables we report a selection that would yield the same word
# in the text uploaded by the user to the panel. Our text does not
# match the user text because of the tabulation.
tblsel(pi: ref Ptext): (int, int)
{
	(w0, w1) := pi.wordat((pi.f.ss + pi.f.se)/2, 1, 0);
	s := pi.blks.pack();
	w := s.s[w0:w1];
	for(i := 0; i < len pi.tabtext - len w; i++)
		if(str->prefix(w, pi.tabtext[i:]))
			return(i, i+len w);
	return (0, 0);
}

startedits(p: ref Panel): int
{
	pi := pimpl(p);
	if(pi.editing)
		return 0;
	if(p.fsctl(sprint("edstart %d", p.vers), 0) < 0){
		fprint(stderr, "o/live: concurrent edit\n");
		return -1;
	}
	pi.editing++;
	return 0;
}

endedits(p: ref Panel)
{
	pi := pimpl(p);
	if(pi.editing){
		p.fsctl(sprint("edend %d %d", pi.id, p.vers), 1);
		p.vers++;
		pi.editing--;
	}
}

syncedits(p: ref Panel, edits: list of ref Edit): int
{
	pi := pimpl(p);

	if(!pi.editing){
		fprint(stderr, "o/live: syncedits: not editing\n");
		return -1;
	}
	ctls: list of string;
	tag := pi.id;
	for(; edits != nil; edits = tl edits){
		e := hd edits;
		ev := sprint("%s %d %d %d ", e.name(), tag, p.vers, e.pos);
		pick  dp := e{
		Ins =>
			ev += e.s;
		Del =>
			ev += sprint("%d", len e.s);
		}
		ctls = append(ctls, ev);
	}

	# This is a good time to update o/mero's idea of the selection.
	(ss, se) := (pi.f.ss, pi.f.se);
	if(p.flags&Ptbl)
		(ss, se) = tblsel(pi);
	ctls = append(ctls, sprint("sel %d %d", pi.f.ss, pi.f.se));
	p.fsctls(ctls, 1);
	return 0;
}

applyedit(p: ref Panel, e: ref Edit): int
{
	if(e != nil){
		pi := pimpl(p);
		pick ep := e {
		Ins =>
			pi.blks.ins(ep.s, ep.pos);
			pi.f.ins(ep.pos, len ep.s);
			return ep.pos + len ep.s;
		Del =>
			pi.blks.del(len ep.s, ep.pos);
			pi.f.del(ep.pos, len ep.s);
			return ep.pos;
		}
	}
	return -1;
}

applyedits(p: ref Panel, el: list of ref Edit): int
{
	pi := pimpl(p);
	r := pi.s0;
	for(; el != nil; el = tl el)
		r = applyedit(p, hd el);
	return r;
}

undo(p: ref Panel): int
{
	pi := pimpl(p);
	return applyedits(p, pi.edits.undo());
}

redo(p: ref Panel): int
{
	pi := pimpl(p);
	return applyedits(p, pi.edits.redo());
}

# insert done by us
ins(p: ref Panel, s: string, pos: int)
{
	pi := pimpl(p);
	os0 := pi.s0;
	pi.blks.ins(s, pos);
	pi.s0 = fixposins(pi.s0, pos, len s);
	if(pi.edits.ins(s, pos) < 0){
		sl := pi.edits.sync();
		if(syncedits(p, sl) < 0){
			fprint(stderr, "o/live: ins: bug: can't sync\n");
			pi.blks.del(len s, pos);
			pi.s0 = os0;
			return;
		}
		pi.edits.synced();
		if(pi.edits.ins(s, pos) < 0){
			pi.edits.dump();
			pi.dump();
			for(; sl != nil; sl = tl sl)
				fprint(stderr, "syncing %s\n", (hd sl).text());
			panic(sprint("text: ins [%s] %d failed", s, pos));
		}
	}
	pi.f.ins(pos, len s);
}

# delete done by us
del(p: ref Panel, n: int, pos: int): string
{
	pi := pimpl(p);
	os0 := pi.s0;
	ds := pi.blks.del(n, pos);
	pi.s0 = fixposdel(pi.s0, pos, n);
	if(pi.edits.del(ds, pos) < 0){
		sl := pi.edits.sync();
		if(syncedits(p, sl) < 0){
			fprint(stderr, "o/live: del: bug: can't sync\n");
			pi.blks.ins(ds, pos);
			pi.s0 = os0;
			return "";
		}
		pi.edits.synced();
		if(pi.edits.del(ds, pos) < 0){
			pi.dump();
			pi.edits.dump();
			for(; sl != nil; sl = tl sl)
				fprint(stderr, "syncing %s\n", (hd sl).text());
			panic(sprint("text: del [%s] %d failed", ds, pos));
		}
	}
	pi.f.del(pos, n);
	return ds;
}

pctl(p: ref Panel, s: string)
{
	pi := pimpl(p);
	odirty := p.flags&Pdirty;
	ofont := p.font;
	if(panelctl(tree, p, s) < 0){
		(nargs, args) := tokenize(s, " \t\n");
		if(nargs > 0)
		case hd args {
		"sel" =>
			ss := fixpos(int nth(args, 1), pi.blks.blen());
			se := fixpos(int nth(args, 2), pi.blks.blen());
			if(se < ss)
				se = ss;
			pi.s0 = ss;
			if(ss != pi.f.ss || se != pi.f.se){
				if(!(p.flags&Pshown))
					pi.f.i = nil;
				pi.f.sel(ss, se);
				if(!(p.flags&Ptbl))
					movetoshow(p, ss);
			}
		"tab" =>
			tab := int nth(args, 1);
			if(tab < 3)
				tab = 3;
			if(tab > 20)
				tab = 20;
			if(pi.f.tabsz != tab){
				pi.f.tabsz = tab;
				pi.f.i = nil;
				p.flags |= Predraw;
			}
		"nousel" =>
			p.flags |= Pnosel;
		"scroll" =>
			p.flags  |= Pscroll;
		"noscroll" =>
			if(!(p.flags&Ptbl))
				p.flags &= ~Pscroll;
		"temp" =>
			p.flags |= Ptemp;
		* =>
			; # ignore others
		}
	}
	if(pi.f != nil)
		pi.f.debug = debug['F'];
	if(odirty && !(p.flags&Pdirty)){
		pi.edits.cpos = pi.edits.pos;
		# BUG: potential race here: User puts, editor issues a clean ctl,
		# and the user adds an edit in the mean while.
		# If this happens, we could just set Pdirty again.
		# But let see if the race is a real one.
		eds := pi.edits.sync();
		if(eds != nil)
			panic("text pctl: clean while dirty edits");
		pi.edits.synced();
	}
	if(ofont != p.font){
		pi.f.i = nil;		# recompute widths and init
		pi.f.font = p.font;
		if(settextsize(p) != 0)
			spawn newlayout();
		p.flags |= Predraw;
	}
}

# Ins/Del events maintain text in sync by reporting updates
# Edend reports that an external edit is finished.
# Editins/Editdel events are used to fill up our initial undo list, but
# are not meant to update our data.
pevent(p: ref Panel, ev: string)
{
	tags, verss, op, poss: string;

	pi := pimpl(p);
	if(!(p.flags&Pshown))
		pi.f.i = nil;		# avoid drawing
	uev := ev;

	(op, ev) = splitl(ev, " \t");		# ins|del|edend
	ev = drop(ev, " \t");

	(tags, ev) = splitl(ev, " \t");	# tag
	ev = drop(ev, " \t");
	if(len tags == 0 || len ev == 0){
		fprint(stderr, "o/live: pevent: short event 1[%s]\n", uev);
		return;
	}
	tag := int tags;
	if(tag == pi.id)		# event generated by us; ignore it.
		return;
	if(pi.editing){
		# allow it to proceed and hope for the best. it's likely
		# that the event is ok but out of order due to a bug in hold.
		fprint(stderr, "o/live: pevent: bug: ins/del while editing\n");
	}
	(verss, ev) = splitl(ev, " \t");		# vers
	ev = drop(ev, " \t");
	if(len verss == 0){
		fprint(stderr, "o/live: pevent: short event 2[%s]\n", uev);
		return;
	}
	vers := int verss;
	pos := -1;
	if(op != "edend"){
		(poss, ev) = splitl(ev, " \t");	# pos
		if(len poss == 0 || len ev == 0){
			fprint(stderr, "o/live: pevent: short event 3[%s]\n", uev);
			return;
		}
		pos = int poss;
		ev = ev[1:];
	}

	# When we receive external ins/del events, we should be ready to put them
	# in place, because we cannot be editing.
	# Events  "editins" and "editdel" are not updates to the current state,
	# they report edits done to a panel so that update may set up old edits for
	# undo/redo; they must not be received for ongoing edits, only for full updates.
	s := ev;
	ed: ref Edit;
	case op {
	"edend" =>
		if(vers <= p.vers)
			fprint(stderr, "o/live: edend vers %d <= vers %d\n",
				vers, p.vers);
		else
			p.vers = vers;
	"ins" or "del" =>
		if(op == "ins"){
			ed = ref Edit.Ins(1, 1, vers, pos, s);
			pi.nlines += stringlines(s);
			settextsize(p);
			if(pi.edits.ins(s, pos) < 0)
				fprint(stderr, "o/live: extern ins edit failed\n");
		} else {
			ed = ref Edit.Del(1, 1, vers, pos, s);
			if(pi.edits.del(s, pos) < 0)
				fprint(stderr, "o/live: extern del edit failed\n");
		}
		applyedit(p, ed);
		pi.edits.synced();
	"editins" =>
		if(pi.edits.ins(s, pos) < 0)
			fprint(stderr, "o/live: editins failed\n");
		pi.edits.synced();
	"editdel" =>
		if(pi.edits.del(s, pos) < 0)
			fprint(stderr, "o/live: editdel failed\n");
		pi.edits.synced();
	}
}

writepsel(p: ref Panel)
{
	# be sure that our ctl reflects the selection.
	pi := pimpl(p);
	(ss, se) := (pi.f.ss, pi.f.se);
	if(p.flags&Ptbl)
		(ss, se) = tblsel(pi);
	p.fsctl(sprint("sel %d %d", pi.f.ss, pi.f.se), 1);

	if((p.flags&Pline) || (p.flags&Pnosel))
		return;

	# o/mero updates /mnt/snarf/sel
	p.fsctl("focus", 1);

	# this is not needed, but it hides latency.
	if(p.parent != nil && p.parent.flags&Pshown)
		win.image.border(p.parent.rect, 1,
			gui->cols[gui->FBORD], (0,0));

}

movetoshow(p: ref Panel, pos: int)
{
	pi := pimpl(p);
	if(pos < pi.f.pos || (pos > pi.f.pos + pi.f.nr)){
		npos := pi.gotopos(pos);
		pi.f.init(pi.blks, npos);
		pi.f.scroll(-pi.f.sz.y/2);
	}
}

cut(p: ref Panel, putsnarf: int): int
{
	pi := pimpl(p);
	nr := pi.f.se - pi.f.ss;
	if(nr == 0)
		return 0;
	pos := pi.f.ss;
	s := "";
	if(!(p.flags&Pedit)){
		t := pi.blks.pack();
		s = t.s[pi.f.se:pi.f.se];
		pi.f.sel(pi.f.ss, pi.f.ss);
	} else
		s = del(p, nr, pos);
	pi.s0 = pi.f.ss;
	if(putsnarf){
		writesnarf(s);
		writepsel(p);
	}
	return 1;
}

paste(p: ref Panel, pos: int): int
{
	if(!(p.flags&Pedit))
		return 0;
	pi := pimpl(p);
	s := readsnarf();
	if(len s == 0)
		return 0;
	ins(p, s, pos);
	pi.f.sel(pos, pos + len s);
	pi.s0 = pi.f.ss;
	writepsel(p);
	return 1;
}

exec(p: ref Panel, pos: int)
{
	pi := pimpl(p);
	s := pi.blks.pack();
	if(pos <pi.f.ss || pos > pi.f.se)
		for(;pos > pi.f.ss; pos--)
			if(iswordchar(s.s[pos], 1))
				break; 
	(ws, we) := pi.wordat(pos, 1, 1);
	c := s.s[ws:we];
	pi.f.sel(ws, we);
	pi.s0 = pi.f.ss;
	p.fsctl("exec " + c, 1);
	if(!(p.flags&Pedit))
		pi.f.sel(we, we);
}

look(p: ref Panel, pos: int)
{
	pi := pimpl(p);
	s := pi.blks.pack();
	(ws, we) := pi.wordat(pos, 1, 1);
	c := s.s[ws:we];
	pi.f.sel(ws, we);
	pi.s0 = pi.f.ss;
	p.fsctl("look " + c, 1);
	if(!(p.flags&Pedit))
		pi.f.sel(we, we);
}

search(p: ref Panel, pos: int)
{
	ws, we: int;
	txt: string;
	pi := pimpl(p);
	s := pi.blks.pack();
	(ws, we) = pi.wordat(pos, 0, 1);
	txt = s.s[ws:we];
	i := -1;
	if(we < len s.s)
		i = strstr(s.s[we:], txt);
	if(i < 0)
		i = strstr(s.s, txt);
	else
		i += we;
	if(i < 0)
		return;
	if(debug['T'])
		fprint(stderr, "search: %s: pos %d\n", dtxt(txt), i);
	pi.f.sel(i, i + len txt);
	pi.s0 = pi.f.ss;
	movetoshow(p, pi.f.ss);
	pt := pi.f.pos2pt(pi.f.ss);
	pt = pt.add((p.font.width(txt[0:1])/2, p.font.height -2));
	win.wmctl("ptr " + string pt.x + " " + string pt.y);
}

# Select requires us to coallesce mouse events that would do nothing
# but update further our possition.
getmouse(mc: chan of ref Cpointer): ref Cpointer
{
	m := <-mc;
	for(;;){
		mm: ref Cpointer;
		mm = nil;
		# nbrecv
		alt {
		mm = <-mc => ;
		* => ;
		}
		if(mm == nil || mm.buttons != m.buttons)
			break;
		m = mm;
	}
	return m;
}

select(p: ref Panel, pos: int, m: ref Cpointer, mc: chan of ref Cpointer): ref Cpointer
{
	pi := pimpl(p);
	b := m.buttons;
	s := pi.blks.pack();
	pi.f.sel(pos, pos);
	if(m.flags&(CMdouble|CMtriple)){
		long := m.flags&CMtriple;
		(ws, we) := pi.wordat(pos, long, 0);
		if(debug['T'])
			fprint(stderr, "getword: pos %d long %d: %d %d %s\n",
				pos, long, ws, we, dtxt(s.s[ws:we]));
		pi.f.sel(ws, we);
		pi.s0 = pi.f.ss;
		do {
			m = <-mc;
		} while(m.buttons == b);
	} else {
		pi.s0 = pos;
		do {
			if(m.xy.y < pi.f.r.min.y){		# scroll up
				pi.f.scroll(-1-(pi.f.r.min.y-m.xy.y)/p.font.height);
				pi.f.sel(pi.f.pos, pi.s0);
				sys->sleep(100);
			} else if(m.xy.y > pi.f.r.max.y){	# scroll down
				pi.f.scroll(1+(m.xy.y-pi.f.r.max.y)/p.font.height);
				pi.f.sel(pi.s0, pi.f.pos + pi.f.nr);
				sys->sleep(100);
			} else {
				pos = pi.f.pt2pos(m.xy);
				if(pos < pi.s0)
					pi.f.sel(pos, pi.s0);
				else
					pi.f.sel(pi.s0, pos);
			}
			m = getmouse(mc);
		} while(m.buttons == b);
	}
	if(b == 1)
		writepsel(p);
	return m;
}

pmouse1(p: ref Panel, pos: int, m: ref Cpointer, mc: chan of ref Cpointer)
{
	dirties := 0;
	pi := pimpl(p);
	m = select(p, pos, m, mc);
	case m.buttons {
	0 =>
		return;
	3 =>
		if(startedits(p) >= 0){
			if(cut(p, 1))
				dirties = 1;
			while(m.buttons){
				m = <-mc;
				if(m.buttons == 5){
					undo(p);
					dirties = 0;
					break;
				}
			}
		}
	5 =>
		if(startedits(p) >= 0){
			if(cut(p, 0)){
				pos = pi.f.ss;
				dirties = 1;
			}
			if(paste(p, pos))
				dirties = 1;
		}
	}
	if(dirties)
		dirty(p, 1);
	while(m.buttons)
		m = <-mc;
}

pmouse2(p: ref Panel, pos: int, m: ref Cpointer, mc: chan of ref Cpointer)
{
	pi := pimpl(p);
	if(pi.f.ss != pi.f.se && pos >= pi.f.ss && pos < pi.f.se){
		m = <-mc;
		if(m.buttons == 0)
			exec(p, pos);
	} else {
		m = select(p, pos, m, mc);
		if(m.buttons == 0)
			exec(p, pos);
	}
	while(m.buttons)
		m = <-mc;
}

# To avoid blinking, we use double buffering during
# scroll operations. This is because we redraw the whole frame,
# and do not shift rectangles around. This makes it easier to draw
# overlayed scroll bars.

scrdraw(p: ref Panel, i: ref Image): ref Image
{
	pi := pimpl(p);
	r := Rect((0,0), (p.rect.dx(), p.rect.dy()));
	if(i == nil){
		i = win.display.newimage(r, win.image.chans, 0, Draw->White);
		pi.f.resize(r, i);
	}
	drawscrollbar(p, i);
	win.image.draw(p.rect, i, nil, (0,0));
	return i;
}

scrdone(p: ref Panel)
{
	pi := pimpl(p);
	pi.f.resize(p.rect, win.image);
}

drawscrollbar(p: ref Panel, i: ref Image)
{
	Barwid: con 25;
	Barht: con 120;

	pi := pimpl(p);
	bar, r: Rect;
	bar.max.x = r.max.x = i.r.max.x - Inset - 3;
	bar.min.x = r.min.x = r.max.x - Barwid;
	r.min.y = i.r.min.y + Inset;
	ysz := Barht;
	r.max.y = r.min.y + ysz;
	if(r.max.y + 3 > i.r.max.y){
		r.max.y = i.r.max.y - 3;
		ysz = r.dy();
	}
	i.draw(r.addpt((2,2)), cols[TEXT], cols[SHAD], (0,0));
	i.draw(r, cols[CLEAR], cols[SHAD], (0,0));
	l := len pi.blks.b[0].s;
	y0 := dy := 0;
	if(l > 0){
		y0 = ysz * pi.f.pos / l;
		dy = ysz * pi.f.nr / l;
		if(dy < 3)
			dy = 3;
	} else {
		y0 = 0;
		dy = r.dy();
	}
	bar.min.y = r.min.y + y0;
	bar.max.y = bar.min.y + dy;
	if(bar.max.y > r.max.y)
		bar.max.y = r.max.y;
	if(bar.min.y > bar.max.y - 2)
		bar.min.y = bar.max.y - 2;
	i.draw(bar.addpt((3,3)), cols[TEXT], cols[SHAD], (0,0));
	i.draw(bar, cols[SET], nil, (0,0));
	i.border(r, 1, cols[BORD], (0,0));
}

jumpscale(p: ref Panel, xy: Point): real
{
	pi := pimpl(p);
	s := pi.blks.pack();
	dy := xy.y - p.rect.min.y;
	if(dy > p.rect.max.y - xy.y)
		dy = p.rect.max.y - xy.y;
	dc := len s.s - pi.f.pos;
	if(dc < pi.f.pos)
		dc = pi.f.pos;
	if(dy < 1)
		dy = 1;
	return (real dc) / (real dy);
}

pmouse3scrl(p: ref Panel, pos: int, m: ref Cpointer, mc: chan of ref Cpointer)
{
	pi := pimpl(p);
	if(pi.blks.blen() == 0){	# the panel is empty; scroll does nothing.
		do{
			m = <-mc;
		} while(m.buttons);
		return;
	}
	xy := m.xy;
	jfactor := real 0;
	jy := xy.y;
	old := pi.f.pos;
	i := scrdraw(p, nil);
	b := m.buttons;
	do {
		if(jfactor <= real 0.00001){
			pos = pi.f.pos;
			jfactor = jumpscale(p, xy);
		}
		jpos := pos + int (real (xy.y - jy) * jfactor);
		if(jpos != old)
			jpos = pi.gotopos(jpos);
		if(jpos != old){
			old = jpos;
			pi.f.init(pi.blks, jpos);
			scrdraw(p, i);
		}
		more := 0;
		m = <- mc;
		do {
			alt {
			m = <-mc =>
				more=1;
			* =>
				more = 0;
			}
		} while(more && m.buttons == b);
		xy = m.xy;
	} while(m.buttons);
	scrdone(p);
}

pmouse3(p: ref Panel, pos: int, m: ref Cpointer, mc: chan of ref Cpointer)
{
	pi := pimpl(p);
	m = <- mc;
	case m.buttons {
	0 =>
		textmenu.last = pi.mlast;
		cmd := textmenu.run(m, mc);
		if(debug['T'])
			fprint(stderr, "pmouse3: cmd: %s at %d\n", cmd, pos);
		case cmd {
		"scroll" =>
			pmouse3scrl(p, pos, m, mc);
		"Find" =>
			search(p, pos);
		"Open" =>
			look(p, pos);
		"Exec" =>
			exec(p, pos);
		"Cut" =>
			if(startedits(p) >= 0)
				if(cut(p, 1))
					dirty(p, 1);
		"Paste" =>
			if(startedits(p) >= 0){
				dirties := cut(p, 0);
				if(paste(p, pos) || dirties)
					dirty(p, 1);
			}
		"Close" =>
			if(p.flags&Pdirty)
				if(!(p.flags&Pinsist)){
					p.flags |= Pinsist; 
					p.fsctl("exec !echo dirty panels", 1);
					return;
				}
			p.fsctl("exec Close", 1);
		"" =>
			; # ignore null commands
		* =>
			p.fsctl("exec " + cmd, 1);
		}
		pi.mlast = textmenu.last;
	4 =>
		pmouse3scrl(p, pos, m, mc);
	* =>
		do
			m = <-mc;
		while(m.buttons);
	}
}

pmouse(p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	if((p.flags&Ptag) && intag(p, m.xy)){
		tagmouse(tree, p, m, mc);
		return;
	}
	pi := pimpl(p);
	# mouse movement syncs any pending edit.
	eds := pi.edits.sync();
	if(eds != nil){
		if(syncedits(p, eds) < 0){
			fprint(stderr, "o/live: pmouse: bug: syncedits failed\n");
			return;
		}
		syncchk(p, "mouse");
	}
	pi.edits.synced();
	endedits(p);
	pos := pi.f.pt2pos(m.xy);
	case m.buttons {
	1 =>
		# For tbls, this should probably allow drag&drop
		pmouse1(p, pos, m, mc);
		if(debug['T'] > 1)
			pi.dump();
	2 =>
		pmouse2(p, pos, m, mc);
		if(debug['T'] > 1)
			pi.dump();
	4 =>
		pmouse3(p, pos, m, mc);
		if(debug['T'] > 1)
			pi.dump();
	}
}

pkbd(p: ref Panel, k: int)
{
	Killword:	con 16r17;	# C-w
	pi := pimpl(p);
	pos := pi.f.ss;
	s := "";
	s[0] = k;
	if(!(p.flags&Pedit)){
		p.fsctl("keys " + s, 1);
		return;
	}
	if(k != Keyboard->Up && k != Keyboard->Down && k != Keyboard->Esc)
	if(startedits(p) < 0)
		return;
	case k {
	'\b' =>
		didcut := cut(p, 1);
		if(didcut){
			pi.mlast = Mpaste;
			pi.s0= pi.f.ss;
		}
		if(!didcut && pos > 0){
			pos--;
			movetoshow(p, pos);
			del(p, 1, pos);
		}
		dirty(p, 1);
	Killword =>
		(ws, we) := pi.wordat(pos, 1, 1);
		if(ws != we){
			pos = ws;
			n := we - ws;
			movetoshow(p, pos);
			del(p, n, pos);
			pi.s0 = pi.f.ss;
		}
	Keyboard->Del =>
		p.fsctl("interrupt", 1);
	Keyboard->Ins =>
		dirties := cut(p, 0);
		if(paste(p, pos) || dirties)
			dirty(p, 1);
	Keyboard->Left or Keyboard->Right=>
		if(k == Keyboard->Left)
			pos = undo(p);
		else
			pos = redo(p);
		if(pos >= 0){
			pi.f.sel(pos, pos);
			pi.s0 = pos;
			dirty(p, pi.edits.pos != pi.edits.cpos);
			movetoshow(p, pos);
		}
	Keyboard->Up or Keyboard->Down =>
		if(p.flags&Pline)
			return;
		n := pi.f.sz.y / 3;
		if(n < 2)
			n = 2;
		if(k == Keyboard->Up)
			n = -n;
		pi.f.scroll(n);
	Keyboard->Esc =>
		if(pi.s0 < pos)
			pi.f.sel(pi.s0, pos);
		else
			pi.f.sel(pos, pi.s0);
	* =>
		if(k == '\n' && (p.flags&Pline)){
			if(pi.s0 < pos)
				pi.f.sel(pi.s0, pos);
			else
				pi.f.sel(pos, pi.s0);
			# be sure that our ctl reflects the selection.
			if(syncedits(p, nil) < 0)
				return;	# concurrent edit; do nothing
			exec(p, pos); 	# exect at pos would exec all the line.
		} else {
			cut(p, 1);
			if(!(p.flags&Pline))
				movetoshow(p, pos);
			ins(p, s, pos);
			pt := pi.f.pos2pt(pos);
			if(pt.y + p.font.height >= pi.f.r.max.y && !(p.flags&Pline))
				pi.f.scroll(1);
			dirty(p, 1);
			if((p.flags&Pedit) && (k == '\n' || (p.flags&Pline))){
				pi.nlines++;
				if(settextsize(p) != 0)
					spawn newlayout();
			}
		}
	}
	if(debug['T'] > 1)
		pi.dump();
}

newlayout()
{
	tree.opc <-= ref Treeop.Layout(nil, 0);
}

