#  This program derives from Plan B's omero, and thus, is twice that big.
#  That puts a limit on the number of omero descendants.

#  The o/mero file server. This program does not draw at all.
#  Viewers are started to perform actual user I/O according to
#  subtrees provided by this file server. 
# 
#  The tree has one directory for applications, /appl. They create their
#  uis inside. Subdirs of /appl represent a top-level panel for the application.
#  Each directory created at the root represents a screen (or viewer),
#  and is provided so that o/live can attach to it. 
#
# Applications use /appl/* files to setup their UI, and perform I/O.
# Viewers use /olive and trees outside /appl, to perform I/O.
#
# Selection is maintained outside. /dev/sel /dev/snarf maintain the user selection and
# the clipboard, and can be operated from outside. It is o/live the one filling them upon
# cut and paste operations.
#
# Event channels are not implemented by this program. ports(4) is used to
# send events from o/mero to applications. All of them
# start with "o/mero: <appdir>".
# Events posted for viewers are sent using merop, a protocol spoken via
# the /olive file served by o/mero. O/mero replies to reads with updates for the
# tree viewed and the viewer writes control requests.
# Events:
#	from o/mero to o/live (via merop):
#		"Tupdate file data"
#		"Ctl top"
#		"Ctl ins tag vers pos string"
#		"Ctl del tag vers pos string"
#
#	from o/live or appl. to o/mero (via merop Ctl or ctl files):
#		tag/notag
#		show/hide
#		col/row
#		dirty/clean
#		appl id pid
#		layout
#		sel %d %d
#		font F
#		tab %d
#		"click %d %d %d %d"
#		"keys %s"
#		"interrupt"
#		"look string"
#		"exec string"
#		"copyto /another/path [pos]"
#		"moveto /another/path [pos]"
#		"edstart vers"
#		"ins tag vers pos string"
#		"del tag vers pos n"
#		"edend tag vers"
#		"top"
#		"pos n"
#		"hold"
#		"release"
#		"usel"
#		"nousel"
#		"scroll"
#		"noscroll"
#		"temp"
#		"notemp"
#		"focus"
#
#	from o/mero to application (via o/ports):
#		"o/mero: /appl/path/for/panel look string"
#		"o/mero: /appl/path/for/panel exec string"
#		"o/mero: /appl/path/for/panel apply string"
#		"o/mero: /appl/path/for/panel close"
#		"o/mero: /appl/path/for/panel click %d %d %d %d"
#		"o/mero: /appl/path/for/panel keys %s"
#		"o/mero: /appl/path/for/panel interrupt"
#		"o/mero: /appl/path/for/panel clean"
#		"o/mero: /appl/path/for/panel dirty"
#		"o/mero: /appl/path/for/panel focus"
#
# When panels are replicated the tree is still
# a tree, and not a DAG. Only that several files would refer to the
# same panels (but different replicas).
#
# Cooperative editing is done using Panel.evers. Each editing increments
# it by one. O/live incrs. its local version when it gets an ins/del event.
# Also, updates sent to o/live update its idea of the panel version.
# ins/del ctls must supply the version (also data's qid.vers) for the file
# before the ins/del being done.
#
# The main program logic is kept here.
# merotree provides panel routines that deal with both the panels and their
# files in the tree, to avoid races.
# panel keeps the data and attributes for panels, and most basic routines.
# omp* files implement mostly syntax checking for panels, and provide extra
# panel-specific attributes.

implement Omero;
include "sys.m";
	Dir, pctl, NEWPGRP, DMDIR, open, OTRUNC,
	OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE,
	MAFTER, MCREATE, pipe, mount,
	fprint, write, sprint, tokenize, bind, create,
	pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "draw.m";
include "styx.m";
	Rmsg, Tmsg: import styx;
include "error.m";
	checkload, stderr, panic, kill, error: import err;
include "styxservers.m";
	Styxserver, readbytes, readstr, Navigator, 
	Eexists, Enotfound, Eperm, Ebadfid, Enotdir, Fid: import styxs;
	nametree: Nametree;
	Tree: import nametree;
include "daytime.m";
	now: import daytime;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "string.m";
	drop, splitl, splitr: import str;
include "lists.m";
	append, reverse, combine: import lists;
include "env.m";
	env: Env;
	getenv: import env;
include "mpanel.m";
	escape, unescape,
	Panel, Repl, Tappl, Trepl, qid2ids: import panels;
	Qdir, Qctl, Qdata, Qolive, Qedits: import Panels;
include "names.m";
include "tbl.m";
include "dat.m";
	dat: Dat;
include "merotree.m";
	pchanged, pcreate, mkcol, chpos, premove,
	moveto, mktree, copyto: import merotree;
include "blks.m";
include "merop.m";
include "merocon.m";
	post, hold, rlse, Con: import merocon;
include "io.m";
	io: Io;
	readdev: import io;

Omero: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
	mnt:	string;
	debug:	int;
	appl:	big;
	slash:	big;
	user:	string;
	vgen:	int;

	srv:	ref Styxserver;
	sys:	Sys;
	err:	Error;
	str:	String;
	tbl:	Tbl;
	lists:	Lists;
	merop:	Merop;
	blks:	Blks;
	panels:	Panels;
	names:	Names;
	merocon:	Merocon;
	merotree: Merotree;
	styx:	Styx;
	styxs:	Styxservers;
	daytime:	Daytime;
};

fsopen(m: ref Tmsg.Open): ref Rmsg
{
	(fid, mode, d, e) := srv.canopen(m);
	if(e != nil)
		return ref Rmsg.Error(m.tag, e);
	(pid, rid, qt) := qid2ids(fid.path);
	(p, r) := Panel.lookup(pid, rid);
	if(p == nil || r == nil)
		return ref Rmsg.Error(m.tag, Enotfound);
	case qt {
	Qdir =>
		return nil;
	Qdata=>
		if(mode != OREAD && (m.mode&OTRUNC) != 0){
			p.data = array[0] of byte;
			fsdata(p, r, array[0] of byte, big 0);
		}
	Qolive =>
		Con.new(fid.fid);
	Qedits =>
		fid.data = array of byte p.edits;
	}
	fid.open(mode, d.qid);
	return ref Rmsg.Open(m.tag, d.qid, srv.iounit());
}

fscreate(m: ref Tmsg.Create): ref Rmsg
{
	(fid, mode, d, e) := srv.cancreate(m);
	if(e != nil)
		return ref Rmsg.Error(m.tag,  e);
	if((m.perm&DMDIR) == 0)
		return ref Rmsg.Error(m.tag, Enotdir);
	(pid, rid, nil) := qid2ids(fid.path);
	(p, r) := Panel.lookup(pid, rid);
	if(p == nil || r == nil)
		return ref Rmsg.Error(m.tag, Enotfound);
	if(!p.container)
		return ref Rmsg.Error(m.tag, "parent is not a container");
	if(1 == 0 && r.tree != Tappl && fid.path != slash)	# permit this by now
		return ref Rmsg.Error(m.tag, "can't create in a view subtree");
	np := pcreate(p, r, d.name);
	if(np == nil)
		return ref Rmsg.Error(m.tag, "bad panel type");
	nq := Qid(np.repl[0].dirq,0,QTDIR);
	d.atime = d.mtime = now();
	fid.open(mode, nq);
	return ref Rmsg.Create(m.tag, nq, srv.iounit());
}

fsremove(m: ref Tmsg.Remove): ref Rmsg
{
	(fid, nil, e) := srv.canremove(m);	# childs ?
	srv.delfid(fid);
	if(e != nil)
		return ref Rmsg.Error(m.tag, e);

	(pid, rid, nil) := qid2ids(fid.path);
	(spid, nil, nil) := qid2ids(slash);
	(apid, nil, nil) := qid2ids(appl);
	(p, r) := Panel.lookup(pid, rid);
	if(p == nil || r == nil)
		return ref Rmsg.Error(m.tag, Enotfound);
	if(pid == spid || pid == apid || r.tree == Trepl)
		return ref Rmsg.Error(m.tag, Eperm);

	# Remove the panel, now. From now on, any request made to files for
	# the removed panel will fail with an error message indicating that
	# the panel was already removed. But the panel is gone now.
	premove(p, r);
	return ref Rmsg.Remove(m.tag);
}

fsclunk(m: ref Tmsg.Clunk): ref Rmsg
{
	fid := srv.getfid(m.fid);
	if(fid == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	(pid, rid, qt) := qid2ids(fid.path);
	(p, r) := Panel.lookup(pid, rid);
	if(qt == Qolive && fid.isopen){
		c := Con.lookup(fid.fid);
		if(c != nil){
			for(;;){
				(cp, cr, cs, d) := c.ctl();
				if(cp == nil)
					break;
				if(cs != nil)
					fsctl(cp, cr, cs);
				if(d != nil){
					cp.data = array[0] of byte;
					fsdata(cp, cr, d, big 0);
				}
			}
			c.close();
		}
	}

	if(p != nil && r != nil && r.tree == Tappl)
	if(fid.isopen && (fid.mode&ORCLOSE))
		premove(p, r);
	srv.delfid(fid);
	return ref Rmsg.Clunk(m.tag);
}

fsread(m: ref Tmsg.Read): (ref Rmsg, int)	# (reply, defer)
{
	(fid, e) := srv.canread(m);
	if(e != nil)
		return (ref Rmsg.Error(m.tag, e), 0);
	if(fid.qtype&QTDIR)
		return (nil, 0);
	(pid, rid, qt) := qid2ids(fid.path);
	(p, r) := Panel.lookup(pid, rid);
	if(p == nil || r == nil)
		return (ref Rmsg.Error(m.tag, Enotfound), 0);
	case qt {
	Qctl =>
		s := p.ctlstr(r);
		return (readstr(m, s), 0);
	Qdata =>
		return (readbytes(m, p.data), 0);
	Qolive =>
		c := Con.lookup(fid.fid);
		if(c == nil)
			return (ref Rmsg.Error(m.tag, "i/o error"), 0);
		c.read(m);
		return (nil, 1);
	Qedits =>
		return (readbytes(m, fid.data), 0);
	* =>
		panic("bad file type");
	}
	return (nil, 0);
}

postctl(p: ref Panel, nil: ref Repl, c: string): string
{
	p.post(c);
	return nil;
}

execctl(p: ref Panel, r: ref Repl, c: string): string
{
	cmd := c[5:];
	case cmd {
	"New" =>
		mkcol(p, r);
	"Close" =>
		premove(p, r);
	* =>
		p.post(c);
	}
	return nil;
}

topctl(p: ref Panel, r: ref Repl, nil: string): string
{
	if(!p.container)
		return "not a container";
	post(p.pid, p, r, "top");
	return nil;
}

movetoctl(p: ref Panel, r: ref Repl, c: string): string
{
	(n, args) := tokenize(c, " ");
	case n {
	2 =>
		path := hd tl args;
		if(path[0] != '/')
			path = "/" + path;
		return moveto(p, r, path, -1);
	3 =>
		path := hd tl args;
		if(path[0] != '/')
			path = "/" + path;
		return moveto(p, r, path, int hd tl tl args);
	* =>
		return "wrong number of arguments";
	}
} 

copytoctl(p: ref Panel, r: ref Repl, c: string): string
{
	(n, args) := tokenize(c, " ");
	pos := -1;
	case n {
	2 =>
		;
	3 =>
		pos = int hd tl tl args;
	* =>
		return "wrong number of arguments";
	}
	path := hd tl args;
	if(path[0] != '/')
		path = "/" + path;
	e := copyto(p, r, path, pos);
	# ignore error if the target already exists.
	# too many things to keep tar happy.
	if(e == Eexists)
		e = nil;
	return e;
}

posctl(p: ref Panel, r: ref Repl, c: string): string
{
	(n, args) := tokenize(c, " ");
	case n {
	2 =>
		chpos(p, r, int hd tl args);
	* =>
		return "wrong number of arguments";
	}
	return nil;
}

dumpctl(nil: ref Panel, nil: ref Repl, nil: string): string
{
	panels->dump();
	merotree->dump();
	merocon->dump();
	return nil;
}

debugctl(nil: ref Panel, nil: ref Repl, c: string): string
{
	(n, args) := tokenize(c, " ");
	case n {
	2 =>
		debug = int hd tl args;
		blks->debug = merop->debug = debug;
		if(debug > 1)
			styxs->traceset(1);
		else
			styxs->traceset(0);
	* =>
		return "wrong number of arguments";
	}
	return nil;
}

nopctl(nil: ref Panel, nil: ref Repl, nil: string): string
{
	return nil;
}

holdrlsectl(p: ref Panel, nil: ref Repl, c: string): string
{
	(n, args) := tokenize(c, " ");
	case n {
	1 =>
		if(p.pid == 0)
			return "set appl pid first";
		if(hd args == "hold")
			hold(p);
		else
			rlse(p);
		return nil;
	}
	return "wrong number of arguments";
}

focusctl(p: ref Panel, r: ref Repl, nil: string): string
{
	if(r.id == 0){
		# event sent probably by the app.
		# use instead the first replica available.
		if(len p.repl > 1 && p.repl[1] != nil)
			r = p.repl[1];
	}
	if(r.id != 0){
		fd := open("/mnt/snarf/sel", OWRITE|OTRUNC);
		if(fd != nil)
			fprint(fd, "%s\n", r.path);
		else
			fprint(stderr, "o/mero: focusctl: %r");
		fd = nil;
	}
	p.vpost(p.pid, "focus");
	p.post("focus");
	return nil;
}

fsdata(p: ref Panel, r: ref Repl, d: array of byte, off: big): string
{
	(nil, e) := p.put(d, off);
	if(e != nil)
		return e;
	e = p.newdata();
	p.newvers();
	if(e != nil)
		return e;
	pchanged(p);
	if(r.id != 0)
		p.post("dirty");
	p.vpost(p.pid, "update");
	return nil;
}

Ctlcmd: type ref fn(p: ref Panel, r: ref Repl, c: string): string;
Ctl: adt {
	name:	string;
	cmd:	Ctlcmd;
};

ctlcmds: array of Ctl;

fsctl(p: ref Panel, r: ref Repl, ctl: string): string
{
	if(ctlcmds == nil)
		ctlcmds = array[] of {
			Ctl("click ", postctl),
			Ctl("keys ", postctl),
			Ctl("look ", postctl),
			Ctl("exec ", execctl),
			Ctl("moveto ", movetoctl),
			Ctl("copyto ", copytoctl),
			Ctl("dump", dumpctl),
			Ctl("order ", nopctl),
			Ctl("top", topctl),
			Ctl("pos", posctl),
			Ctl("hold", holdrlsectl),
			Ctl("release", holdrlsectl),
			Ctl("debug", debugctl),
			Ctl("focus", focusctl),
		};
	if(debug)
		fprint(stderr, "o/mero: %s: ctl: %s\n", r.path, ctl);
	for(i := 0; i < len ctlcmds; i++){
		l := len ctlcmds[i].name;
		if(len ctl >= l && ctl[0:l] == ctlcmds[i].name)
			break;
	}
	u := 0;
	e, c: string;
	if(i < len ctlcmds)
		e = ctlcmds[i].cmd(p, r, ctl);
	else
		(u, e, c) = p.ctl(r, ctl);
	if(e != nil){
		if(debug)
			fprint(stderr, "o/mero: ctl failed: %s\n", e);
		return e;
	}
	pchanged(p);
	if(c != nil){
		# The panel wants c events posted to all replicas.
		# It changed, but we must not send update events.
		# (eg. ins/del events carrying panel changes).
		p.vpost(p.pid, c);
	} else if(u)
		p.vpost(p.pid, "update");
	if(r.id != 0 && ctl == "dirty")
		p.post("dirty");
	if(r.id != 0 && ctl == "clean")
		p.post("clean");
	return nil;
}

olivectl(m: ref Tmsg.Write): ref Rmsg
{
	fid := srv.getfid(m.fid);
	c := Con.lookup(fid.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, "i/o error");
	c.write(m);
	e: string;
	do {
		(cp, cr, cs, d) := c.ctl();
		if(cs == "fail")
			e = "ctl failed";
		else if(cp == nil)
			break;
		else if(cs == "top"){
			c.top = cr.path;
			cp.vpost(cp.pid, "update");
		} else if (cs != nil)
			e = fsctl(cp, cr, cs);
		if(e == nil && d != nil)
			e = fsdata(cp, cr, d, big 0);
	} while(e == nil);
	if(e != nil)
		return ref Rmsg.Error(m.tag, e);
	else
		return ref Rmsg.Write(m.tag, len m.data);
}

usrctl(m: ref Tmsg.Write): ref Rmsg
{
	fid := srv.getfid(m.fid);
	(pid, rid, nil) := qid2ids(fid.path);
	(p, r) := Panel.lookup(pid, rid);
	if(p == nil || r == nil)
		return ref Rmsg.Error(m.tag, Enotfound);
	(nil, ctls) := tokenize(string m.data, "\n");
	e: string;
	for(; ctls != nil && e == nil; ctls = tl ctls)
		e= fsctl(p, r, unescape(hd ctls));
	if(e != nil)
		return ref Rmsg.Error(m.tag, e);
	else
		return ref Rmsg.Write(m.tag, len m.data);
}

fswrite(m: ref Tmsg.Write): ref Rmsg
{
	(fid, e) := srv.canwrite(m);
	if(e != nil)
		return ref Rmsg.Error(m.tag, e);
	(pid, rid, qt) := qid2ids(fid.path);
	(p, r) := Panel.lookup(pid, rid);
	if(p == nil || r == nil)
		return ref Rmsg.Error(m.tag, Enotfound);
	case qt {
	Qctl =>
		# BUG: this does not work for big ctl requests that
		# do not fit in a single write request.
		if(len m.data == srv.msize - Styx->IOHDRSZ){
			fprint(stderr, "o/mero: BUG: ctl request > msize\n");
			return ref Rmsg.Error(m.tag, "o/mero: bug: big ctl request");
		}
		return usrctl(m);
	Qdata =>
		# Can't report errors on close!
		# But why should we bother? nobody checks those anyway.
		nw := len m.data;
		e = fsdata(p, r, m.data, m.offset);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		else
			return ref Rmsg.Write(m.tag, nw);
	Qolive =>
		return olivectl(m);
	Qedits =>
		# pretend we accept them, to keep tar(1) happy.
		return ref Rmsg.Write(m.tag, len m.data);
	* =>
		panic("bug: o/mero: bad file type for write");
	}
	return nil;
}

fswstat(m: ref Tmsg.Wstat): ref Rmsg
{
	# pretend we accept wstats, so that tar(1) can be used
	# to extract entire trees and does not think its wstats
	# failed.
	return ref Rmsg.Wstat(m.tag);
}

fsreq(req: ref Tmsg) : (ref Rmsg, int)	# (reply, defer)
{
	r: ref Rmsg;
	pick m := req {
	Open =>
		r = fsopen(m);
	Create =>
		r = fscreate(m);
	Remove =>
		r = fsremove(m);
	Read =>
		return fsread(m);
	Write =>
		r = fswrite(m);
	Wstat =>
		r = fswstat(m);
	Clunk =>
		r = fsclunk(m);
	Flush =>
		Con.flush(m.oldtag);
		r = ref Rmsg.Flush(m.tag);
	* =>
		r = nil;
	}
	return (r, 0);
}

replyproc()
{
	for(;;){
		r := <-srv.replychan;
		if(r == nil)
			break;
		srv.replydirect(r);
		r = nil;
	}
}

fs(c: chan of int, fd: ref FD)
{
	styx->init();
	styxs->init(styx);
	if(c != nil)
		pctl(FORKNS|NEWPGRP|NEWFD, list of {0,1,2,fd.fd});
	else
		pctl(NEWPGRP, nil);
	stderr = fildes(2);
	c <-= merocon->start();
	if(debug)
		fprint(stderr, "echo killgrp >/prog/%d/ctl\n", pctl(0,nil));
	navc := merotree->init(dat);
	nav := Navigator.new(navc);
	(reqc, fssrv) := Styxserver.new(fd, nav, big 0); # / must have qid (0,0,QTDIR)
	srv = fssrv;
	srv.replychan = chan[1] of ref Rmsg;
	spawn replyproc();
	mktree();
	for(;;) {
		req := <-reqc;
		if(req == nil)
			break;
		(rep, defer) := fsreq(req);
		if(!defer)
			if(rep == nil)
				srv.default(req);
			else
				srv.reply(rep);
		req = nil;
		rep = nil;
	}
	srv = nil;
	fprint(stderr, "o/mero: exiting\n");
	kill(pctl(0, nil),"killgrp");	# be sure to quit
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	str = checkload(load String String->PATH, String->PATH);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxs = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	nametree = checkload(load Nametree Nametree->PATH, Nametree->PATH);
	names = checkload(load Names Names->PATH, Names->PATH);
	nametree->init();
 	daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	tbl = checkload(load Tbl Tbl->PATH, Tbl->PATH);
	lists = checkload(load Lists Lists->PATH, Lists->PATH);
	merop = checkload(load Merop Merop->PATH, Merop->PATH);
	blks = checkload(load Blks Blks->PATH, Blks->PATH);
	dat = load Dat "$self";
	if(dat == nil)
		error(sprint("can't load dat: %r"));
	panels = checkload(load Panels Panels->PATH, Panels->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	panels = checkload(load Panels Panels->PATH, Panels->PATH);
	merotree = checkload(load Merotree Merotree->PATH, Merotree->PATH);
 	merocon = checkload(load Merocon Merocon->PATH, Merocon->PATH);
	user = getenv("user");
	if(user == nil)
		user = readdev("/dev/user", "none");
	arg->init(args);
	arg->setusage("o/mero [-abcdi] [-m mnt]");
	mnt = "/mnt/ui";
	flag := MREPL|MCREATE;
	while((opt := arg->opt()) != 0) {
		case opt{
		'b' =>
			flag = MBEFORE;
		'a' =>
			flag = MAFTER;
		'c' =>
			flag |= MCREATE;
		'i' =>
			mnt = nil;
		'm' =>
			mnt = arg->earg();
		'd' =>
			blks->debug = merop->debug = ++debug;
			if(debug > 1)
				styxs->traceset(1);
		* =>
			usage();
		}
	}
	args = arg->argv();
	if(len args != 0)
		usage();
	panels->init(dat, "/dis/o/mero");
	merocon->init(dat);
	blks->init();
	merop->init(sys, blks);
	# merocon is init'ed from the fs proc,
	# to use its name space and FDGRP
	c := chan[1] of int;
	if(mnt == nil)
		fs(c, fildes(0));
	else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("o/mero: pipe: %r"));
		spawn fs(c, pfds[0]);
		if(<-c < 0)
			exit;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("o/mero: mount: %r"));
		pfds[0] = nil;
	}
}
