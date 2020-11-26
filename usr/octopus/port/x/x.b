implement Ox;
# o/x. In charge of opening files and executing commands from
# applications using o/mero

include "mods.m";
fsname, seled, debug, findpanel, findseled, Csam, Crc, Csh, Ccmd, 
sharedns, scroll, trees, ui, Tree, Edit: import oxedit;
Xcmd, deledit, newedit, msg, fatal, putedit: import oxex;
editcmd: import sam;
drop: import str;

include "wait.m";
wait: Wait;

Ox: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

omero := "/mnt/ui";
persist := 0;

dump()
{
	for(trl := oxedit->trees; trl != nil; trl = tl trl)
		(hd trl).dump();
}

mkhome(s: string): (ref Tree, ref Edit)
{
	t: ref Tree;
	e: ref Edit;
	t = nil;
	e = nil;
	scrs := panels->screens();
	if(scrs == nil)
		fatal("o/x: no screens");
	for(; scrs != nil; scrs = tl scrs){
		scr := hd scrs;
		home := Tree.new(s);
		home.mk(scr);
		ne := newedit(home, s, 0, 1);
		if(ne != nil && e == nil)
			(t, e) = (home, ne);
	}
	if(t != nil){
		fd := open("/mnt/snarf/sel", OWRITE|OTRUNC);
		if(fd != nil)
			fprint(fd, "/%s/row:wins/col:1\n", t.scr);
	}
	return (t, e);
}

mkui(dir: string): (ref Tree, ref Edit, chan of ref Pev)
{
	dir = names->rooted(workdir->init(), dir);
	dir = names->cleanname(dir);
	ui = Panel.init("ox");
	if(ui == nil)
		fatal(sprint("o/x: can't create ui: %r"));
	ui.ctl("hold\n");
	(t, e) := mkhome(dir);
	ui.ctl("release\n");
	return (t, e, ui.evc());
}

look(tr: ref Tree, ed: ref Edit, what: string)
{
	if(ed != nil)
		ed.lru = now();
	run(tr, ed, "Open " + what, 1);
}

lookfile(tr: ref Tree, dir, what: string)
{
	path := names->rooted(dir, what);
	addr, fname: string;

	(e, nil) := stat(fsname(path));
	err: string;
	if(e < 0){
		err = sprint("%r");
		# file:address?
		(fname, addr) = splitl(what, ":");
		fname = names->rooted(dir, fname);
		addr = drop(addr, ":");
		if(len addr > 0 && addr[len addr -1] == ':')
			addr = addr[:len addr-1];
		(e, nil) = stat(fsname(fname));
		if(e >= 0)
			path = fname;
		else
			addr = nil;
	}
	if(e >= 0){
		logcmd("look", dir, path);
		ned := newedit(tr, path, 0, 0);
		if(ned != nil){
			if(addr != nil)
				editcmd(ned, addr + "\n");
			if(ned.body != nil)
				ned.body.ctl("focus");
		}
	}
}

done(tr: ref Tree): int
{
	for(edl := tr.eds; edl != nil; edl = tl edl)
		pick edp := hd edl{
		File =>
			if(edp.dirty){
				msg(tr, tr.path, sprint("%s: unsaved edits\n", tr.path));
				return -1;
			}
		}
	tr.close();
	return 0;
}

logcmd(c, dir, what: string)
{
	fd := open("/mnt/ports/post", OWRITE);
	if(fd != nil){
		(s, nil) := splitl(what, "\n");
		if(s != nil)
			what = s;
		fprint(fd, "%s: %s#%s\n", c, what, dir);
	}
	fd = nil;
}

run(tr: ref Tree, ed: ref Edit, what: string, istag: int)
{
	stderr = fildes(2);
	dir: string;
	if(ed != nil){
		dir = ed.dir;
		ed.lru = now();
	} else
		dir = tr.path;
	what = drop(what, " \t\n");
	logcmd("exec", dir, what);
	(nwargs, wargs) := tokenize(what, " \t\n");
	if(nwargs < 1)
		return;
	cmd := hd wargs;
	seled = findseled();
	if(seled != nil){
		seled.lru = now();
		seled.getedits();
	}
	if(debug)
		fprint(stderr, "seled: %s \n", seled.text());

	ui.ctl("hold\n");
	case cmd {
	"" =>
		; # ignore
	"End" =>
		do {
			if(trees == nil){
				ui.ctl("release\n");
				kill(pctl(0,nil), "killgrp");
				exit;
			}
		} while(done(hd trees) >= 0);
	"Close" =>
		if(ed == nil){
			done(tr);
			if(len trees == 0)
				mkhome(getenv("home"));
		} else
			deledit(ed);
	"Open" =>
		if(nwargs > 1)
			lookfile(tr, dir, hd tl wargs);
		else {
			if(ed != nil)
			if((e := ed.cleanto(cmd, nil)) != nil)
				msg(tr, dir, sprint("%s: %s\n", ed.path, e));
			else
				if(ed.get() < 0)
					ed.close();
		}
	"Write" =>
		if(ed == nil)
			msg(tr, dir, "no edit at point\n");
		else {
			where := ed.path;
			if(nwargs > 1)
				where = hd tl wargs;
			putedit(ed, where);
		}
	"Keep" =>
		if(ed != nil)
			ed.keep = 1;
		else
			msg(tr, dir, "no edit at point\n");
	"Dup" =>
		scr: string;
		if(nwargs == 2){
			scr = hd tl wargs;
			create(omero + "/" + scr, OREAD, 8r775+DMDIR);
		} else
			scr = nil;
		nt := Tree.new(dir);
		nt.mk(scr);
		newedit(nt, dir, 0, 1);
		if(nwargs == 2)
			msg(tr, dir, scr += " created\n");
	"Cmds" =>
		msg(tr, dir, Xcmd.ftext(0));
	"Scroll" =>
		if(nwargs != 1)
			msg(tr, dir, "usage: Scroll\n");
		else
			scroll = !scroll;
			if(scroll)
				msg(tr, dir, "new panels scroll\n");
			else
				msg(tr, dir, "new panels do not scroll\n");
	"Ctl" =>
		if(nwargs < 2)
			msg(tr, dir, "usage: Ctl ctl\n");
		else if(ed != nil){
			ctl := hd tl wargs;
			for(wargs = tl tl wargs; wargs != nil; wargs = tl wargs)
				ctl += " " + hd wargs;
			ed.body.ctl(ctl  + "\n");
		}
	"Edit" or "Rc" or "Sh" =>
		if(ed == nil)
			msg(tr, dir, "no current edit\n");
		else
			case cmd {
			"Edit" =>	ed.dfltcmd = Csam;
			"Rc" =>	ed.dfltcmd = Crc;
			"Sh" =>	ed.dfltcmd = Csh;
			}
	* =>
		# external command; it always refers to seled.
		cmd=drop(cmd, " \t\n");
		ck := cmd[0];
		if(ed != nil && !istag)
		if(ck != Csam && ck != Crc && ck != Csh && ck != Ccmd)
			ck = ed.dfltcmd;
		file := "";
		if(seled != nil){
			dir = seled.dir;
			file = seled.path;
		}
		if(ck == Ccmd){
			if(oxedit->fsdir != "")
				ck = Crc;
			else
				ck = Csh;
			what = what[1:];
		}
		case ck {
		Crc =>
			if(cmd[0] == Crc)
				what = what[1:];
			if(debug)
				fprint(stderr, "host cmd %s\n", what);
			Xcmd.new(what, file, dir, nil, nil, tr.tid, 1);
		Csh =>
			if(cmd[0] == Csh)
				what = what[1:];
			if(debug)
				fprint(stderr, "inferno cmd %s\n", what);
			Xcmd.new(what, file, dir, nil, nil, tr.tid, 0);
		* =>
			if(debug)
				fprint(stderr, "edit cmd %s\n", what);
			editcmd(seled, what + "\n");
		}
	}
	ui.ctl("release\n");

}

ofocus: ref Edit;
nfocus(ed: ref Edit)
{
	nfocus: ref Panel;
	if(ed != nil)
		nfocus = ed.tag;
	if(ofocus != nil && ofocus.tag != nil && ofocus.tag != nfocus)
		ofocus.tag.ctl("font B\n");
	if(nfocus != nil)
		nfocus.ctl("font I\n");
	ofocus = ed;
}

edevent(ed: ref Edit, op: string, arg: string, istag: int)
{
	tr := Tree.find(ed.tid);
	if(debug)
		fprint(stderr, "o/x: editev %s: %s [%s]\n", ed.path, op, arg);
	case op {
	"look" =>
		look(tr, ed, arg);
	"exec" or "apply" =>
		run(tr, ed, arg, istag);
	"close" =>
		ed.close();
	"clean" or "dirty" =>
		pick edp := ed {
		File =>
			edp.dirty = (op == "dirty");
		}
	"focus" =>
		nfocus(ed);
	}
	if(debug)
		dump();
}

trevent(tr: ref Tree, op: string, arg: string)
{
	if(debug)
		fprint(stderr, "o/x: treeev %s: %s [%s]\n", tr.path, op, arg);
	case op {
	"look" =>	;
		look(tr, nil, arg);
	"exec" or "apply" =>
		run(tr, nil, arg, 1);
	"close"  =>
		tr.close();
	}
}

updatecmdstag(tr: ref Tree)
{
	ui.ctl("hold\n");
	t := "cmds: " + Xcmd.ftext(1);
	fd := open(tr.xtag.path+"/data", OWRITE|OTRUNC);
	if(fd != nil){
		data := array of byte t;
		write(fd, data, len data);
	}
	ui.ctl("release\n");
}

eventproc(evc: chan of ref Pev, xc: chan of int)
{
	if(debug)
		fprint(stderr, "\necho killgrp >/prog/%d/ctl\n\n", pctl(0, nil));
	for(;;){
		alt {
		ev := <-evc =>
			if(ev == nil)
				break;
			(nil, p) := splitstrl(ev.path, "/tag:");
			istag := p != nil;
			if(ev.arg == nil)
				ev.arg = "";
			(tr, ed) := findpanel(ev.id);
			if(tr == nil){
				# external event
				# could use focus events to locate
				# a tree where the user selected
				# something last.
				if(ev.ev != "close")
					tr = hd trees;
			}
			if(tr != nil)
			if(ed != nil)
				edevent(ed, ev.ev, ev.arg, istag);
			else
				trevent(tr, ev.ev, ev.arg);
		tid := <-xc =>
			tr := Tree.find(tid);
			if(tr != nil)
				updatecmdstag(tr);
		}
	}
}

oxproc(pidc: chan of int, fsdir, uidir, cmd: string)
{
	pidc <-= pctl(NEWPGRP, nil);
	stderr = fildes(2);
	os->init();
	panels->init();
	oxedit->init(dat, fsdir);
	regx->init(dat);
	sam->init(dat);
	samcmd->init(dat);
	samlog->init(dat);
	xc := chan[10] of int;	# see xcmdproc 
	oxex->init(dat, xc);
	tblks->init(sys, str, err, 0);
	oxload->init(dat);
	scroll = 1;
	evc: chan of ref Pev;
	t: ref Tree;
	e: ref Edit;
	t = nil;
	e = nil;
	if(uidir == nil){
		dir := getenv("home");
		if(getenv("OCTOPUS") != nil && fsdir == "")
			dir = "/pc" + dir;
		else if(dir == nil)
			dir = "/";
		(t, e, evc) = mkui(dir);
	} else
		evc = oxload->loadui(uidir);
	if(t != nil && cmd != nil){
		if(debug)fprint(stderr, "o/x: initcmd: %s\n", cmd);
		run(t, e, cmd, 1);
	}
	eventproc(evc, xc);
}

oxmain(fsdir, uidir, cmd: string)
{
	pid := pctl(NEWPGRP, nil);
	stderr = fildes(2);
	pidc := chan of int;
	wfd := open(sprint("/prog/%d/wait", pid), OREAD);
	stime := now();
	spawn oxproc(pidc, fsdir, uidir, cmd);
	oxpid := <-pidc;
	if(persist){
		wait->init();
		for(;;){
			(spid, nil, sts) := wait->read(wfd);
			if(spid != oxpid)
				continue;
			fprint(stderr, "o/x: restart: %d exited: %s\n", spid, sts);
			t := now();
			if(t - stime < 10)
				error("o/x exiting. aborting\n");
			stime = t;
			spawn oxproc(pidc, fsdir, uidir, nil);
			oxpid = <-pidc;
		}
	}
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	dat = checkload(load Oxdat Oxdat->PATH, Oxdat->PATH);
	dat->loadmods(sys, err);
	initmods(dat->mods);
	wait = checkload(load Wait Wait->PATH, Wait->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(argv);
	arg->setusage("o/x [-9dnp] [-o dir] [-l dir] [-i cmd]");
	uidir, cmd: string;
	fsdir := "";
	while((opt := arg->opt()) != 0) {
		case opt {
		'9' =>
			fsdir  = "/mnt/fs";
		'd' =>
			debug = 1;
		'n' =>
			sharedns = 1;
		'o' =>
			omero = arg->earg();
		'p' =>
			persist = 1;
		'l' =>
			uidir = arg->earg();
		'i' =>
			cmd = arg->earg();
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(len argv > 0)
		arg->usage();
	setenv("omero", omero);
	spawn oxmain(fsdir, uidir, cmd);
}
