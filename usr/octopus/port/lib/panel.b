implement Panels;

include "sys.m";
	sys: Sys;
	stat, Qid, FD, sleep, create, ORCLOSE, remove, QTDIR,
	DMDIR, OREAD, OWRITE, OTRUNC, werrstr, tokenize,
	open, fprint, read, ORDWR, write, pctl, sprint: import sys;
include "env.m";
	env: Env;
	getenv, setenv: import env;
include "readdir.m";
	readdir: Readdir;
	MTIME, NAME, DESCENDING: import readdir;
include "keyring.m";
include "security.m";
	random:	Random;
	randomint, ReallyRandom: import random;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "string.m";
	str: String;
	splitl: import str;
include "names.m";
	names: Names;
	basename: import names;
include "io.m";
	io: Io;
	readdev: import io;

include "panel.m";

apid: int;

init()
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	env = checkload(load Env Env->PATH, Env->PATH);
	readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	names = checkload(load Names Names->PATH, Names->PATH);
	str = checkload(load String String->PATH, String->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	random = checkload(load Random Random->PATH, Random->PATH);
	omero = getenv("omero");
	if(omero == nil){
		(e, nil) := stat("/mnt/ui/appl");
		if(e >= 0)
			omero = "/mnt/ui";
	}
	if(omero == nil)
		error("$omero is not set");
}

Panel.init(nm: string): ref Panel
{
	name, path: string;
	fd: ref FD;
	apid = pctl(0, nil);
	if(nm[0] == '/'){
		name = basename(nm, nil);
		path = nm;
		fd = open(path, OREAD);
	} else {
		name = sprint("col:%s.%d", nm, apid);
		path = sprint("%s/appl/%s", omero, name);
		fd = create(path, OREAD, DMDIR|8r775);
	}
	if(fd == nil)
		return nil;
	fd = nil;
	cfd := open(path + "/ctl", OWRITE|ORCLOSE);
	if(cfd == nil && nm[0] != '/'){
		remove(path);
		return nil;
	}
	p := ref Panel(0, name, path, cfd, -1);
	p.ctl(sprint("appl 0 %d\n", apid));
	return p;
}

eparsearg(s: string): (string, string)
{
	arg: string;
	if(s == nil)
		return (nil, nil);
	(arg, s) = splitl(s, " ");
	if(arg == nil || s == nil || len s < 1)
		return (arg, nil);
	s = s[1:];	# skip ' '
	return (arg, s);
}

eparse(s: string): ref Pev
{
	Pref: con "o/mero: ";
	path, id, ev, arg: string;

	# Must match events sent by o/mero. See
	# big comment near the start of ../mero/mero.b
	# Also, don't use tokenize, look/exec/apply carry strings
	# as arguments. 
	l := len s;
	if(l > 0 && s[l-1] == '\n')
		s = s[:l-1];

	# o/mero:
	if(len s <= len Pref)
		return nil;
	s = s[len Pref:];

	(path, s) = eparsearg(s);
	(id, s) = eparsearg(s);
	(ev, arg) = eparsearg(s);
	if(path == nil || id == nil || ev == nil)
		return nil;
	case ev {
	"look" or "exec" or "apply" or "click" or "keys" =>
		if(arg == nil)
			return nil;
	"close" or "interrupt" or "clean" or "dirty" or "focus" =>
		if(arg != nil)
			return nil;
	* =>
		return nil;
	}
	return ref Pev(int id, path, ev, arg);
}

reader(fd: ref FD, ec: chan of ref Pev, pc: chan of int)
{
	pc <-= pctl(0, nil);
	buf := array[4096] of byte;	# enough for application events
	for(;;){
		nr := read(fd, buf, len buf);
		if(nr <= 0){
			ec <-= nil;
			break;
		}
		ev := eparse(string buf[0:nr]);
		if(ev == nil)
			fprint(stderr, "panel: reader: bad event: %s\n", string buf[0:nr]);
		else
			ec <-= ev;
	}
}

Panel.evc(p: self ref Panel): chan of ref Pev
{
	fd := create("/mnt/ports/" + p.name, ORDWR|ORCLOSE, 8r664);
	if(fd == nil)
		return nil;
	expr := array of byte sprint("o/mero: %s.*", p.path[len omero:]);
	write(fd, expr, len expr);
	pc := chan of int;
	ec := chan of ref Pev;
	spawn reader(fd, ec, pc);
	p.rpid = <-pc;
	fd = nil;
	return ec;
}

Panel.newnamed(p: self ref Panel, nm: string, id: int): ref Panel
{
	nm = sprint("%s/%s", p.path, nm);
	create(nm, OREAD, DMDIR|8r775);
	return p.new(nm, id);
}

Panel.new(p: self ref Panel, nm: string, id: int): ref Panel
{
	name, path: string;
	fd: ref FD;
	if(nm[0] == '/'){
		name = basename(nm, nil);
		path = nm;
		fd = open(path, OREAD);
	} else {
		rnd := randomint(ReallyRandom)%16rFFFF;
		name = sprint("%s.%4.4ux", nm, rnd);
		path = sprint("%s/%s", p.path, name);
		fd = create(path, OREAD, DMDIR|8r775);
	}
	if(fd == nil)
		return nil;
	fd = nil;
	pn := ref Panel(id, name, path, nil, -1);
	if(id != 0)
		if(pn.ctl(sprint("appl %d %d\n", id, apid)) < 0)
			fprint(stderr, "panel: new: ctl: %r\n");
	return pn;
}

Panel.close(p: self ref Panel)
{
	if(p.rpid >= 0)
		kill(p.rpid, "kill");	# BUG?
	remove(p.path);
	p.gcfd = nil;	# ORCLOSE for top-level
	p.path = nil;	# poison
	p.rpid = -1;
}

Panel.ctl(p: self ref Panel, ctl: string): int
{
	if(p.path == nil){
		fprint(stderr, "panel: ctl %s on closed panel %s\n", ctl, p.name);
		return -1;
	}
	fd := open(p.path+"/ctl", OWRITE);
	if(fd == nil)
		return -1;
	data := array of byte ctl;
	nw := sys->write(fd, data, len data);
	data = nil;
	fd = nil;
	return nw;
}

nullattrs: Attrs;
Panel.attrs(p: self ref Panel): ref Attrs
{
	fd := open(p.path+"/ctl", OREAD);
	if(fd == nil)
		return nil;
	buf := array[1024] of byte;
	nr := read(fd, buf, len buf);
	if(nr < 0)
		return nil;
	(nil, al) := tokenize(string buf[0:nr], "\n");
	attrs := ref nullattrs;
	for(; al != nil; al = tl al){
		(nargs, args) := tokenize(hd al, " \t\n");
		if(nargs > 0)
		case hd args {
		"tag"	=> attrs.tag = 1;
		"notag"	=> attrs.tag = 0;
		"show"	=> attrs.show = 1;
		"hide"	=> attrs.show = 0;
		"col"	=> attrs.col =1;
		"row"	=> attrs.col = 0;
		"clean"	=> attrs.clean = 1;
		"dirty"	=> attrs.clean = 0;
		"scroll"	=> attrs.scroll = 1;
		"noscroll"	=> attrs.scroll = 0;
		"appl" =>
			if(nargs >= 3){
				attrs.applid = int hd tl args;
				attrs.applpid= int hd tl tl args;
			}
		"layout" =>
			attrs.applid = attrs.applpid = -1;
		"sel" =>
			if(nargs >= 3)
				attrs.sel =(int hd tl args, int hd tl tl args);
		"font" =>
			if(nargs >= 2)
				attrs.font = (hd tl args)[0];
		"mark" =>
			if(nargs >= 2)
				attrs.mark = int hd tl args;
		"tab" =>
			if(nargs >= 2)
				attrs.tab = int hd tl args;
		* =>
			attrs.attrs = args::attrs.attrs;
		}
	}
	return attrs;
}

userscreen(): string
{
	path := io->readdev("/mnt/snarf/sel", nil);
	if(len path > 1){
		(path, nil) = splitl(path[1:], "/");
		return path;
	}
	return nil;
}

screens(): list of string
{
	(dirs, n) := readdir->init(omero, NAME|DESCENDING);
	res : list of string;
	res = nil;
	for(i := 0; i < n; i++)
		if(dirs[i].name != "appl" && (dirs[i].qid.qtype&QTDIR))
			res = dirs[i].name :: res;
	return res;
}

cols(scr: string): list of string
{
	path := "/" + scr + "/" + "row:wins";
	fd := open(omero+"/"+path+"/ctl", OREAD);
	if(fd == nil)
		return nil;
	buf := array[1024] of byte;
	nr := read(fd, buf, len buf);
	if(nr < 0)
		return nil;
	(nil, al) := tokenize(string buf[0:nr], "\n");
	cl: list of string;
	for(; al != nil; al = tl al){
		(nil, cl) = tokenize(hd al, " \t\n");
		if(cl != nil && hd cl == "order"){
			cl = tl cl;
			break;
		}
	}
	res: list of string;
	if(cl != nil)
		for(; cl != nil; cl = tl cl)
			res = (path + "/" + hd cl) :: res;
	if(res != nil){
		cl = nil;
		for(; res != nil; res = tl res)
			cl = hd res::cl;
		res = cl;
	}
	return res;
}

rows(scr: string): list of string
{
	path := "/" + scr;
	(dirs, nd) := readdir->init(omero+path, NAME|DESCENDING);
	res: list of string;
	for(i := 0; i < nd; i++)
		if(dirs[i].qid.qtype&QTDIR)
		if(dirs[i].name != "row:wins")
			res = (path + "/" + dirs[i].name) :: res;
	return res;
}

sel(): string
{
	path := io->readdev("/mnt/snarf/sel", nil);
	if(path == nil)
		return nil;
	fd := open(omero + path + "/data", OREAD);
	if(fd == nil)
		return nil;
	data := io->readfile(fd);
	if(data == nil)
		return nil;
	txt := string data;
	p := ref Panel;
	p.path = omero + path;
	attrs := p.attrs();
	if(attrs == nil)
		return nil;
	if(attrs.sel.t0 != attrs.sel.t1 &&
	  attrs.sel.t0 >= 0 && attrs.sel.t0 < len txt &&
	  attrs.sel.t1 >= 0 && attrs.sel.t1 <= len txt)
		return txt[attrs.sel.t0:attrs.sel.t1];
	else
		return "";
}
