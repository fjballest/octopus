implement Olive;
include "mods.m";
mods, debug, win, tree: import dat;
Menu: import menus;
setcursor, Waiting, Arrow,
getfont, Cpointer, cols, panelback, maxpt, cookclick, drawtag,
BACK,TEXT, readsnarf, CMdouble, terminate : import gui;
Ptag, Pline, Pedit, Pdead, Pdirty, 
intag, Panel: import wpanel;
panelctl, panelkbd, Treeop, panelmouse, tagmouse, Tree: import wtree;
Msg: import merop;
Blk: import blks;
usage: import arg;
basename: import names;

# 
#  Viewer for o/mero. This program is in charge
#  of user I/O, and behaves as a write-through cache regarding
#  the o/mero provided file tree.
#  Events are handled by o/ports, and the snarf/selection info is
#  kept outside as well.
# See the comment at ../mero/mero.b for details.

Olive: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

ctlc: chan of (ref Panel, list of string, chan of int);
datac: chan of (ref Panel, array of byte, chan of int);

ioproc(kbdc: chan of int, mousec: chan of ref Cpointer, resizec: chan of int)
{
	rc := chan of int;
	while(!gui->exiting){
		alt{
		r := <-kbdc =>
			s := "";
			s[0] = r;
			# consume keys repeated and buffer
			# any other key received while we were busy.
			do {
				ir := r;
				alt {
					r = <-kbdc => ;
					* => r = -1;
				}
				if(r != ir && r != -1)
					s[len s] = r;
			} while(r != -1);
			tree.opc <-= ref  Treeop.Kbd(s);
		m := <-mousec =>
			if(m == nil)
				terminate(nil);
			if(debug['M'])
				fprint(stderr, "m [%d %d] %x f%x\n",
				m.xy.x, m.xy.y, m.buttons, m.flags);
			tree.opc <-= ref  Treeop.Mouse(m, mousec, rc);
			# Must not recv from mousec while the focus is using
			# the mouse. Thus, synchronize.
			<-rc;
		<-resizec =>
			if(win.image == nil){
				fprint(stderr, "o/live: no image\n");
				terminate(nil);
			}
			tree.opc <-= ref Treeop.Layout(nil, 1);
		}
	}
}

ctlproc(fd: ref FD, ctlc: chan of (ref Panel, list of string, chan of int),
	datac: chan of (ref Panel, array of byte, chan of int),
	sc: chan of string)
{
	m: ref Msg;
	m = ref Msg.Ctl(tree.slash.path, "top");
	md := m.pack();
	if(write(fd, md, len md) != len md)
		sc <-= sprint("%r");
	sc <-= nil;
	obuf := ref Blk(nil, 0, 0);
	for(;;) alt {
	(p, sl, c) := <-ctlc =>
		dctl := "";
		for(; sl != nil; sl = tl sl){
			m = ref Msg.Ctl(p.path, hd sl);
			dctl = hd sl;
			obuf.put(m.pack());
		}
		sts := 0;
		data := obuf.get(obuf.blen());
		if(write(fd, data, len data) != len data){
			if(1 || debug['E'])
			fprint(stderr, "cltproc: write (%s) %r\n", dctl);
			sts = -1;
		}
		if(c != nil)
			c <-= sts;
	(p, d, c) := <-datac =>
		m = ref Msg.Update(p.path, p.vers, nil, d, nil);
		md = m.pack();
		sts := 0;
		if(write(fd, md, len md) != len md){
			fprint(stderr, "cltproc: write: %r\n");
			sts = -1;
		}
		if(c != nil)
			c <-= sts;
		
	}
}

isfocus(m: ref Msg): int
{
	pick mm := m {
	Ctl =>
		return mm.ctl == "focus";
	}
	return 0;
}

updatemsg(m: ref Msg, nl, nt: int): (int, int)
{
	if(debug['E'])
		fprint(stderr, "o/live: event: %s\n", m.text());
	path := m.path;
	if(isprefix(tree.slash.path, path))
		path = path[len tree.slash.path:];
	else if(!isfocus(m)){
		fprint(stderr, "o/live: bad update path %s for %s\n",
			path, tree.slash.path);
		return (nl, nt);
	}
	if(path == "")
		path = "/";
	pick mm := m {
	Update =>
		uop := ref Treeop.Update(path,
			mm.vers, mm.ctls, mm.data, mm.edits);
		tree.opc <-= uop;
		nl++;
		nt++;
	Ctl =>
		ev: string;
		(ev, mm.ctl) = splitl(mm.ctl, " \t");
		mm.ctl = drop(mm.ctl, " \t");
		case ev {
		"top" =>
			nl = 0;
			tree.opc <-= ref Treeop.Layout(path, 0);
		"close" =>
			tree.opc <-= ref Treeop.Close(path);
			nt++;
			nl++;
		"focus" =>
			tree.opc <-= ref Treeop.Focus(path);
			nt++;
		"ins" or "del" or "edend" =>
			tree.opc <-= ref Treeop.Insdel(path, ev + " " + mm.ctl);
			nt++;
		}
	* =>
		panic("o/live: unknown event\n");
	}
	return (nl, nt);
}

updateproc(fd: ref FD)
{
	blk := ref Blk(nil, 0, 0);
	for(;;){
		nr := blk.read(fd, 4096);
		if(nr <= 0)
			terminate("o/live: eof on o/mero");
		nl := nt := 0;
		while((m := Msg.bread(blk)) != nil)
			(nl, nt) = updatemsg(m, nl, nt);
		if(nl)
			tree.opc <-= ref Treeop.Layout(nil, 0);
		if(nt)
			tree.opc <-= ref  Treeop.Tags;
	}
}

choosescreen(omero: string, mc: chan of ref Cpointer): string
{
	(dirs, n) := readdir->init(omero, readdir->NAME);
	if(n < 0)
		terminate(sprint("omero: %r"));
	if(n < 3)
		terminate("o/live: no screens");
	scrs := array[n-2] of string;
	n = 0;
	for(i := 0; i < len dirs; i++)
		if(dirs[i].name != "appl" && dirs[i].name != "olive")
			scrs[n++] = dirs[i].name;
	if(n == 1)
		return scrs[0];
	txt := "Click to select a screen";
	r := win.image.r;
	pt := Point((r.min.x+r.max.x)/2, r.min.y+r.dy()/4);
	font := getfont("L");
	pt.x -= font.width(txt)/2;
	win.image.text(pt, cols[TEXT], (0,0), font, txt);
	smenu := Menu.new(scrs);
	m := <-mc;
	scr := smenu.run(m, mc);
	if(scr == "scroll" || scr == "")
		return scrs[0];
	else
		return scr;
}

nullflags := array[256] of int;

init(ctx: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dat = load  Livedat Livedat->PATH;
	if(dat == nil){
		fprint(fildes(2), "o/live: can't load %s: %r\n", Livedat->PATH);
		raise "fail: loads";
	}
	dat->loads();
	initmods();
	arg->init(args);
	arg->setusage("o/live [-dEFKLMPSTW] [dir] scr");
	debug = nullflags;
	while((opt := arg->opt()) != 0) {
		case opt{
		'd' =>
			debug['E'] = 1;
			# debug flags:
		'P' or	# panel events and changes
		'W' or	# window events
		'L' or	# layout computing
		'M' or	# mouse events
		'E' or	# events to/from omero and builtin cmds
		'T' or	# text panel
		'K' or	# keyboard events
		'F' or	# text frame
		'S' or	# text sync checks
		'D' =>	# delay and report draws
			debug[opt]++;
			if(opt == 'T')
				debug['S']++;
		* =>
			usage();
		}
	}
	if(debug['E'] > 0){
		merop->debug = debug['E']-1;
		blks->debug = merop->debug;
	}
	args = arg->argv();
	omero, dir: string;
	case len args {
	1 =>
		omero = "/mnt/ui";
		dir = hd args;
	2 =>
		omero = hd args;
		dir = hd tl args;
	0 =>
		omero = "/mnt/ui";
		dir = nil;
	* =>
		usage();
	}
	dir = basename(dir, nil);
	wmcli->init();
	menus->init(dat);
	sys->pctl(NEWPGRP, nil);
	blks->init();
	merop->init(sys, blks);
	layoutm->init(dat);
	ctlc = chan[16] of (ref Panel, list of string, chan of int);
	datac = chan[16] of (ref Panel, array of byte, chan of int);
	wpanel->init(dat, "/dis/o/live", ctlc, datac);
	wtree->init(dat);
	fd := open(omero + "/olive", ORDWR);
	if(fd == nil)
		error(sprint("%s: %r", omero + "/olive"));
	(kbdc, mousec, resizec) := gui->init(dat, ctx);
	setcursor(Arrow);
	if(dir == nil)
		dir = choosescreen(omero, mousec);
	tree = Tree.start(dir);
	if(tree == nil)
		error(sprint("can't create tree: %r"));
	sc := chan of string;
	spawn ctlproc(fd, ctlc, datac, sc);
	if((e := <-sc) != nil){
		kill(sys->pctl(0, nil), "killgrp");
		error("o/live: can't set op-level panel: " + e);
	}
	spawn updateproc(fd);
	spawn ioproc(kbdc, mousec, resizec);
}
