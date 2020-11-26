# Generic panel coordination
# One process performs all operations on panels, so that
# there are no races. Because I/O is done by other processes (but for drawing),
# no panel is locked or kept busy. This is to be sure that there are no races.
# No tree operation should take a long time (but for mouse handling, perhaps).
# Generic panel operations are also implemented here.

implement Wtree;
include "mods.m";
mods, debug, win, tree: import dat;

Menu: import menus;
Ptag, Pline, Pedit, Pdead, Pdirty, Pshown, Predraw, Phide, Qatom,
Pbusy, Pdirties, Pmore, Playout, Qrow, Qcol, nth, Pinsist, Pfocus, Pjump,
intag, Panel: import wpanel;
Cpointer, Tagwid, Taght, Inset, setcursor, drawtag, lastxy, terminate,
maxpt, minpt,
getfont, readsnarf, cookclick, Arrow, Drag, Resize: import gui;
dirname, basename: import names;

init(d: Livedat)
{
	dat = d;
	initmods();
}

Tree.path(t: self ref Tree, p: ref Panel): string
{
	l := len t.slash.path;
	path := p.path[l:];
	if(path == "")
		path = "/";
	return path;
}

walktree(p: ref Panel, elems: list of string): ref Panel
{
	if(elems == nil)
		return p;
	if(hd elems == "/")
		return walktree(p, tl elems);
	for(i := 0; i < len p.child; i++)
		if(p.child[i].name == hd elems)
			return walktree(p.child[i], tl elems);
	return nil;
}

Tree.walk(t: self ref Tree, path: string): ref Panel
{
	if(path == nil)
		return nil;
	path = checkpath(path);
	elems: list of string;
	if(path != nil)
		elems = names->elements(path);
	if(elems != nil)
		elems = tl elems;	# get rid of "/"
	return walktree(t.slash, elems);
}

notshown(p: ref Panel, prunep: ref Panel)
{
	if(p == prunep)
		return;
	p.flags &= ~Pshown;
	p.rect = Rect((0, 0), (0, 0));
	p.resized = 0;
	if(p.rowcol)
		for(i := 0; i < len p.child; i++)
			notshown(p.child[i], prunep);
}

showtree(p: ref Panel, force: int)
{
	mustdraw := p.flags&Predraw;
	p.flags &= ~Predraw;
	if(p.rect.dx() <= Inset || p.rect.dy() <= Inset || (p.flags&Phide)){
		# not enough size to show the panel.
		notshown(p, nil);
		return;
	}
	p.flags |= Pshown;
	force |= !p.rect.eq(p.orect);
	if(p.rowcol != Qatom){
		for(i := 0; i < len p.child; i++)
			showtree(p.child[i], force);
		p.draw();
	} else
		if(force || mustdraw){
			if(debug['L'])
			fprint(stderr, "show: %s\t[%d %d %d %d]" +
				" drw%d frz%d dp=%d\n",
				p.text(), p.rect.min.x, p.rect.min.y,
				p.rect.max.x, p.rect.max.y,
				mustdraw, force, p.depth);
			p.draw();	# must draw tag as well
			if(debug['D'])
				sys->sleep(2000);
		}
	if(p.flags&Pjump){
		p.flags &= ~Pjump;
		pt := p.rect.min.add((3, 3));
		win.wmctl("ptr " + string pt.x + " " + string pt.y);
	}
	return;
}

Tree.layout(t: self ref Tree, p: ref  Panel, auto: int)
{
	if(p == nil)
		p = t.dslash;
	force := t.dslash != p;
	t.dslash = p;
	notshown(t.slash, t.dslash);
	# up to 10 times we try to recompute the
	# layout if a panel was full (after hidding a child)
	for(i := 0; i < 10; i++)
		if(layoutm->layout(p, auto) != 0){
			force = 1;
			t.tags();
		} else
			break;
	showtree(p, force);
}

tagtree(fp: ref Panel, hidden: int): (int, int)
{
	dirties := (fp.flags&Pdirty);
	more := (fp.flags&Phide);
	hidden |= (fp.flags&Phide);
	focus := 0;
	fp.nshown = 0;
	for(i := 0; i < len fp.child; i++){
		(cd, cm) := tagtree(fp.child[i], hidden);
		dirties |= cd;
		more |= cm;
		focus |= fp.child[i].flags&Pfocus;
		if(!(fp.child[i].flags&Phide))
			fp.nshown++;
	}
	if(fp.rowcol){
		if(dirties)
			fp.flags |= Pdirties;
		else
			fp.flags &= ~Pdirties;
		if(more)
			fp.flags |= Pmore;
		else
			fp.flags &= ~Pmore;
	}
	if(!hidden && (fp.flags&Pshown) && (fp.flags&Ptag)){
		drawtag(fp);
		if(focus)
			win.image.border(fp.rect, 1,
				gui->cols[gui->FBORD], (0,0));
	}
	return (dirties, more);
}

Tree.tags(t: self ref Tree)
{
	tagtree(t.slash, 0);
}

showchildren(p: ref Panel, first: int, last: int, only: ref Panel)
{
	this := 0;
	for(i := 0; i < len p.child; i++){
		np := p.child[i];
		if(first <= this && this < last || np == only){
			if(np.flags&Phide){
				np.ctl("show");
				np.fsctl("show", 1);
			}
		} else
			if(!(np.flags&Phide)){
				np.ctl("hide");
				np.fsctl("hide", 1);
			}
		this++;
	}
}

Tree.size(nil: self ref Tree, p: ref  Panel, op: int)
{
	case op {
	More =>
		if(p.nshown >= len p.child)
			showchildren(p, 0, 1, nil);
		else
			showchildren(p, 0, p.nshown+1, nil);
	Full =>
		showchildren(p, 0, len p.child, nil);
	Max =>
		if((fp := p.parent) != nil && fp != p){
			if(fp.nshown != 1)
				showchildren(fp, 0, 0, p);
			else
				showchildren(fp, 0, len fp.child, nil);
			p.flags |= Pjump;
		}
	}
}

deltree(p: ref Panel)
{
	p.flags |= Pdead;
	for(i := 0; i < len p.child; i++)
		deltree(p.child[i]);
	p.term();
}

closetree(t: ref Tree, p: ref Panel)
{
	p.flags |= Pdead;
	dp := p.parent;
	if(dp == nil)
		terminate("Root panel removed");
	nshown := 0;
	for(i := 0; i < len dp.child; i++)
		if(dp.child[i] == p)
			dp.child[i] = nil;
		else if (!(dp.child[i].flags&Phide))
			nshown++;
	packchildren(dp);
	deltree(p);
	if(nshown == 0 && len dp.child > 0)
		showchildren(dp, 0, len dp.child, nil);
	if(dp.flags&(Pdirties|Pmore))
		t.tags();
}

orderchildren(p: ref Panel)
{
	ochild := p.child;
	n := len ochild;
	if(n < len p.order)
		n = len p.order;
	nchild := array[n] of ref Panel;
	pos := 0;
	for(ol := p.order; ol != nil; ol = tl ol)
		for(i := 0; i < len ochild; i++)
			if(ochild[i] != nil && hd ol == ochild[i].name){
				nchild[pos++] = ochild[i];
				ochild[i] = nil;
				break;
			}
	for(i = 0; i < len ochild; i++)
		if(ochild[i] != nil)
			nchild[pos++] = ochild[i];
	p.child = nchild[0:pos];
}

packchildren(p: ref Panel)
{
	i,j : int;
	for(i = j = 0; j < len p.child; j++)
		if((p.child[i] = p.child[j]) != nil)
			i++;
	p.child = p.child[0:i];
}

unescape(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == 1)
			s[i] = '\n';
	return s;
}

updatetree(p: ref Panel, newname: string, vers: int,
	ctls: string, data: array of byte, edits: string)
{
	if(debug['P'] > 1){
		cs := ds := es := "";
		if(ctls != nil)
			cs = " ctls";
		if(data != nil)
			ds = " data";
		if(edits != nil)
			es = " edits";
		path  := p.path;
		fprint(stderr, "o/live: updatetree %s%s%s%s\n", path, cs, ds, es);
	}
	if(newname != nil){
		dp := p;
		p = Panel.new(newname, dp);
		if(p == nil)
			return;
		p.flags |= Predraw;
		orderchildren(dp);
		dp.flags |= Predraw;
	}
	if(data != nil)
		p.update(data);
	if(ctls != nil){
		(nil, cl) := tokenize(ctls, "\n");
		for(; cl != nil; cl = tl cl)
			p.ctl(hd cl);
	}
	if(edits != nil){
		(nil, cl) := tokenize(edits, "\n");
		for(; cl != nil; cl = tl cl)
			p.event("edit" + unescape(hd cl));
	}
	# vers never goes backward, but it may be possible
	# that we receive an update from an old version of the panel.
	if(vers > p.vers)
		p.vers = vers;
}

Tree.focus(t: self ref Tree, p: ref Panel)
{
	if(t.sel != nil && p != t.sel){
		t.sel.flags &= ~Pfocus;
		if(t.sel.parent != nil && t.sel.parent.flags&Pshown){
			r := t.sel.parent.rect;
			c := gui->cols[gui->BORD];
			win.image.border(r, 1, c, (0,0));
		}
	}
	if(p != nil){
		p.flags |= Pfocus;
		t.sel = p;
	}
}

tabs(n: int): string
{
	s := "";
	for(i := 0; i < n; i++)
		s += "  ";
	return s;
}

dumptree(p: ref Panel, d: int)
{

	fprint(stderr, "%s%s\n", tabs(d), p.text());
	if(p.rowcol != Qatom)
		for(i := 0; i < len p.child; i++)
				dumptree(p.child[i], d+1);
}

Tree.dump(t: self ref Tree, p: ref Wpanel->Panel)
{
	if(p == nil)
		p = t.slash;
	dumptree(p, 0);
}

checkpath(path: string): string
{
	if(path == nil)
		path = "/";
	if(path[0] != '/')
		panic("Tree: relative path");
	return path;
}
 
ptwalktree(p: ref Panel, pt: Point, atomok: int): ref Panel
{
	if(p.flags&Pdead)
		return nil;
	if(pt.in(p.rect) && p.rowcol != Qatom)
		for(i := 0; i < len p.child; i++){
			np := p.child[i];
			if(np.flags&Phide)
				continue;
			if(pt.in(np.rect) && (atomok || np.rowcol != Qatom))
				return ptwalktree(np, pt, atomok);
		}
	return p;
}

Tree.ptwalk(t: self ref Tree, pt: Point, atomok: int): ref Panel
{
	p := ptwalktree(t.dslash, pt, atomok);
	if(atomok)
		return p;
	else
		for(;;){
			if(p.parent == nil)
				return p;
			if(p.flags&Playout)
				return p;
			p = p.parent;
		}
	
}

iscmd(s: string): int
{
	for(i := 0; i < len s; i++){
		if(s[i] == Keyboard->Up || s[i] == Keyboard->Down)
			return 1;
		if(s[i] == Keyboard->Left || s[i] == Keyboard->Right)
			return 1;
	}
	return 0;
}

treeproc(t: ref Tree)
{
	t.kbdfocus = t.sel = nil;
	for(;;){
		o := <-t.opc;
		if(o == nil)
			terminate(nil);
		pick op := o {
		Kbd =>
			kf := t.kbdfocus;
			if(kf == nil || iscmd(op.s) || kf.flags&Pdead)
				kf = t.kbdfocus = t.ptwalk(lastxy(), 1);
			if(kf != nil && !(kf.flags&Pdead))
				for(i := 0; i < len op.s; i++)
					t.kbdfocus.kbd(op.s[i]);
		Mouse =>
			p := t.ptwalk(op.m.xy, 1);
			if(p != nil && !(p.flags&Pdead)){
				t.kbdfocus = p;
				t.kbdfocus.mouse(op.m, op.mc);
			}
			op.rc <-= 0;
		Layout =>
			p := t.walk(op.path);
			if(p == nil)
				p = t.dslash;
			t.layout(p, op.auto);
		Close =>
			p := t.walk(op.path);
			if(p != nil){
				if(isprefix(p.path, t.dslash.path))
					terminate("Root panel gone");
				closetree(t, p);
			}
		Focus =>
			p := t.walk(op.path);
			t.focus(p);
		Update =>
			p := t.walk(op.path);
			newname: string;
			if(p == nil){
				# must be a new panel
				# walk to parent instead.
				p = t.walk(dirname(op.path));
				newname = basename(op.path, nil);					}
			if(p != nil && !(p.flags&Pdead))	
				updatetree(p, newname, op.vers, op.ctls,
					op.data, op.edits);
		Tags =>
			t.tags();
		Insdel =>
			p := t.walk(op.path);
			if(p != nil && !(p.flags&Pdead))
				p.event(op.ctl);
		* =>
			fprint(stderr, "o/live: unknown tree op\n");
		}
	}
}

Tree.start(name: string): ref Tree
{
	slash := Panel.new(name, nil);
	if(slash == nil){
		werrstr("bad panel type");
		return nil;
	}
	slash.path = "/" + name;
	opc := chan of ref Treeop;
	if(debug['P'])
		fprint(stderr, "tree slash %s\n", slash.path);
	t := ref Tree("/" + name, slash, slash, opc, nil, nil);
	spawn treeproc(t);
	return t;
}

# Adjust the panel size to the size as set by the user.
# From this point on the size of the panel is kept fixed.
# If due to resizes, there's not enough space, the panels
# won't be shown and the user will notice. 
resize(nil: ref Tree, p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer): int
{
	p.resized = 0;
	setcursor(Resize);
	b := m.buttons;
	oxy := m.xy;
	while(m.buttons == b)
		m = <-mc;
	if(m.buttons != 0){
		do {
			m = <-mc;
		} while(m.buttons != 0);
		setcursor(Arrow);
		return 0;
	}
	setcursor(Arrow);
	r := Rect(oxy, m.xy);
	d := Point(r.dx(), r.dy());
	if(oxy.x < (p.rect.min.x + p.rect.max.x)/2)
		d.x = -d.x;
	if(oxy.y < (p.rect.min.y + p.rect.max.y)/2)
		d.y = -d.y;
	if(d.x < 10)
		d.x = 0;
	if(d.y < 10)
		d.y = 0;
	sz := d.add((p.rect.dx(), p.rect.dy()));
	if(!sz.eq((p.rect.dx(), p.rect.dy())))
	if(sz.x + 2 * Inset < win.image.r.dx())
	if(sz.y + 2 * Inset < win.image.r.dy()){
		p.size = sz;
		p.resized = 1;
	}
	return 0;
}

insertpoint(p: ref Panel, pt: Point): int
{
	pos := i := 0;
	if(p.rowcol == Qrow)
		for(i = 0; i < len p.child; i++){
			np := p.child[i];
			if(np.flags&Pshown)
			if(pt.x > np.rect.min.x + np.rect.dx()/2)
				pos = i+1;
			else if(pt.x < np.rect.min.x + np.rect.dx()/2)
				break;
		}
	else
		for(i = 0; i < len p.child; i++){
			np := p.child[i];
			if(np.flags&Pshown)
			if(pt.y > np.rect.min.y + np.rect.dy()/2)
				pos = i+1;
			else if(pt.y < np.rect.min.y + np.rect.dy()/2)
				break;
		}
	return pos;
}

copying := 0;

drag(t: ref Tree, p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer, innerok: int)
{
	setcursor(Drag);
	b := m.buttons;
	xy := m.xy;
	while(m.buttons == b){
		m = <-mc;
	}
	if(m.buttons != 0){
		do {
			m = <-mc;
		} while(m.buttons != 0);
		setcursor(Arrow);
		return;
	}
	r := Rect(xy, m.xy);
	r = r.canon();
	if(p.rowcol && r.dx() < 10 && p.rect.contains(m.xy)){
		p.ctl("col");
		p.fsctl("col", 1);
		t.layout(nil, 0);
	} else if(p.rowcol && r.dy() < 10 && p.rect.contains(m.xy)){
		p.ctl("row");
		p.fsctl("row", 1);
		t.layout(nil, 0);
	} else {
		np := t.ptwalk(m.xy, innerok);
		if(innerok && np.rowcol == Qatom)
			np = np.parent;
		if(np == p){
			pos := insertpoint(np, m.xy);
			p.fsctl(sprint("pos %d\n", pos), 1);
		} else if(np != nil && np != p){
			pos := insertpoint(np, m.xy);
			path := np.path;
			op := "moveto";
			if(copying)
				op = "copyto";
			p.fsctl(sprint("%s %s %d", op, path, pos), 1);
			copying = 0;
		}
	}
	setcursor(Arrow);
}

wcmd(t: ref Tree, p: ref Panel, c: string)
{
	if(c != "Close")
		p.flags &= ~Pinsist;
	case c {
	"Copy" =>
		copying = 1;
		pt := p.rect.min;
		pt.add((Inset+Tagwid/2, Inset+Taght/2));
		win.wmctl("ptr " + string pt.x + " " + string pt.y);
	"More" =>
		t.size(p, More);
		t.tags();
		t.layout(nil, 0);
	"Hide" =>
		p.ctl("hide");
		p.fsctl("hide", 1);
		t.tags();
		t.layout(nil, 0);
	"Close" =>
		if(p.flags&(Pdirties|Pdirty))
			if(!(p.flags&Pinsist)){
				p.flags |= Pinsist; 
				p.fsctl("exec !echo dirty panels", 1);
				return;
			}
		if(p == t.slash ||  p == t.dslash)
			terminate(nil);
		p.fsctl("exec Close", 1);
	"Top" =>
		if(p == t.dslash)
			t.layout(t.slash, 0);
		else
			t.layout(p, 0);
		pt := p.rect.min.add((Tagwid/2, Taght/2));
		win.wmctl("ptr " + string pt.x + " " + string pt.y);
	"Full" =>
		t.size(p, Full);
		t.tags();
		t.layout(nil, 0);
	* =>
		fprint(stderr, "o/live: wcmd: unknown cmd %s\n", c);
	}
	if(debug['P'])
		t.dump(nil);
}

tagmenu: ref Menu;

tagmouse1(t: ref Tree, p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	m = <-mc;
	case m.buttons {
	1 =>
		setcursor(Resize);
		m = <-mc;
		case m.buttons {
		0 =>
			t.layout(t.dslash, 1);
			setcursor(Arrow);
			return;
		1 =>
			if(resize(t, p, m, mc))
				t.layout(nil, 0);
			setcursor(Arrow);
			return;
		}
	}
	setcursor(Arrow);	
	while(m.buttons)
		m = <-mc;
}

tagmouse(t: ref Tree, p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer)
{
	if(tagmenu == nil)
		tagmenu = Menu.new(array[] of
			{"Copy", "More", "Hide", "Close", "Top", "Full"});
	case m.buttons {
	1 =>
		m = <-mc;
		case m.buttons {
		1 =>
			drag(t, p, m, mc, 0);
		0 =>
			tagmouse1(t, p, m, mc);
		* =>
			while(m.buttons)
				m = <-mc;
		}
	2 =>
		if(cookclick(m, mc)){
			t.size(p, Max);
			t.tags();
			t.layout(nil, 0);
		}
	4 =>
		m = <-mc;
		case m.buttons {
		0 =>
			copying = 0;
			opt := tagmenu.run(m, mc);
			if(opt != nil)
				wcmd(t, p, opt);
		* =>
			while(m.buttons)
				m = <-mc;
		}
	* =>
		while(m.buttons)
			m = <-mc;
	}
}

panelmouse(t: ref Tree, p: ref Panel, m: ref Cpointer, mc: chan of ref Cpointer): int
{
	if((p.flags&Ptag) && intag(p, m.xy)){
		tagmouse(t, p, m, mc);
		return 1;
	}
	case m.buttons {
	2 =>
		if(cookclick(m, mc))
			p.fsctl(sprint("exec %s", p.name), 1);
		return 1;
	4 =>
		if(cookclick(m, mc))
			p.fsctl(sprint("look %s", p.name), 1);
		return 1;
	}
	return 0;
}

panelkbd(nil: ref Tree, p: ref Panel, r: int)
{
	if(r == Keyboard->Del)
		p.fsctl("interrupt", 1);
	else if(p.flags&Pedit)
		p.fsctl(sprint("keys %c", r), 1);
}

flagredraw(fp: ref Panel)
{
	fp.flags |= Predraw;
	for(i := 0; i < len fp.child; i++)
		flagredraw(fp.child[i]);
}

flaghide(fp: ref Panel)
{
	fp.flags &= ~Pshown;
	fp.rect = Rect((0,0),(0,0));		# make fp.rect different
	for(i := 0; i < len fp.child; i++)	# on the next draw.
		flaghide(fp.child[i]);
}

# The FS should never report certain attributes for certain panels.
# In any case, we process most of them here, and most panels may
# call this function to deal with their ctls.
panelctl(nil: ref Tree, p: ref Panel, s: string): int
{
	(nargs, args) := tokenize(s, " \t\n");
	if(nargs < 1)
		return -1;
	case hd args {
	"row" =>
		if(p.rowcol != Qrow)
			flagredraw(p);
		p.rowcol = Qrow;
	"col" =>
		if(p.rowcol != Qcol)
			flagredraw(p);
		p.rowcol = Qcol;
	"appl" =>
		# arg ignored
		p.flags &= ~Playout;
	"layout" =>
		p.flags |= Playout;
	"hide" =>
		p.flags |= Phide;
		flaghide(p);
	"show" =>
		p.flags &= ~Phide;
		flagredraw(p);
	"tag" =>
		if(!(p.flags&Ptag))
			p.flags |= Predraw;
		p.flags |= Ptag;
	"notag" =>
		if(p.flags&Ptag)
			p.flags |= Predraw;
		p.flags &= ~Ptag;
	"dirty" =>
		# containers should never get here
		p.flags |= Pdirty;
	"clean" =>
		# containers should never get here
		p.flags &= ~Pdirty;
	"font" =>
		o := p.font;
		# only text panels should get here
		p.font = getfont(nth(args, 1));
		if(o != p.font)
			p.flags |= Predraw;
	"order" =>
		if(tl args != p.order){
			p.order = tl args;
			orderchildren(p);
			flagredraw(p);
		}
	* =>
		return -1;
	}
	return 0;
}
