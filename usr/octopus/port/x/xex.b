implement Oxex;
include "mods.m";
	fsdir, sharedns, fsname, ui, trees, seled, debug, Tree, Edit: import oxedit;
	tolower, splitr: import str;
	copy: import io;
	basename: import names;

# Xcmd start and end events are coordinated by eventproc, that means
# that it is safe to use xcmds within a direct call from eventproc. However,
# the list is kept synchronized by xcmdproc, which coordinates command
# execution.

xsc, xec: chan of ref Xcmd;
xqc, xsqc: chan of chan of string;
xctx: ref Draw->Context;

mknscmd: string;

init(d: Oxdat, c: chan of int)
{
	cmds := array[] of {
		"mount -c /srv/pc /n/pc",
		"bind -c /n/pc/mnt/terms /mnt/terms",
		"bind -c /n/pc/mnt/view /mnt/view",
		"bind -c /n/pc/mnt/ports /mnt/ports",
		"bind -c /n/pc/mnt/voice /mnt/voice",
		"bind -c /n/pc/mnt/print /mnt/print",
		"bind -c /n/pc/mnt/ui /mnt/ui"
	};
	initmods(d->mods);
	xsc = chan[1] of ref Xcmd;
	xec = chan[10] of ref Xcmd;	# make completion async
	xqc = chan[1] of chan of string;
	xsqc = chan[1] of chan of string;
	spawn xcmdproc(xsc, xec, xqc, xsqc, c);
	if(os->emuhost == "Plan9" && getenv("OCTOPUS") != nil)
	for(i := 0; i < len cmds; i++)
		if(sharedns)
			system(xctx, "os " + cmds[i]);
		else
			mknscmd += cmds[i] + "; ";
}

fatal(s: string)
{
	kill(pctl(0,nil), "killgrp");
	error(s);
}

postxe(c: chan of int, i: int)
{
	c <-= i;
}

# The process asking us to run commands
# may need to execute other commands before
# waiting for us to complete.
# We notify of completion asynchronously
# and put buffers to avoid blocking while notifying exits.
xcmdproc(xsc, xec: chan of ref Xcmd, xqc, xsqc: chan of chan of string, ec: chan of int)
{
	for(;;){
		alt {
		x := <-xsc =>
			if(!x.done)
				xcmds = x::xcmds;
			ec <-= x.tid;
		x := <-xec =>
			nl: list of ref Xcmd;
			for(nl = nil; xcmds != nil; xcmds = tl xcmds)
				if((xx := hd xcmds) != x)
					nl = xx::nl;
			xcmds = nl;
			spawn postxe(ec, x.tid);
		qc := <-xsqc =>
			qc <-= ftext(1);
		qc := <-xqc =>
			qc <-= ftext(0);
		}
	}
}

cmdname(s: string): string
{
	(s, nil) = splitl(s, "\n");
	if(len s > 30)
		s = s[0:30] + "...";
	return s;
}

bufwriteproc(buf: string, fd: ref FD, c: chan of int)
{
	pid := pctl(NEWFD, 0::1::2::fd.fd::nil);
	stderr = fildes(2);
	fd = fildes(fd.fd);
	c <-= pid;
	d:= array of byte buf;
	buf = nil;
	write(fd, d, len d);
	write(fd, array[0] of byte, 0);
	fd = nil;
}

bufreadproc(fd: ref FD, c: chan of int, rc: chan of string)
{
	pid := pctl(NEWFD, 0::1::2::fd.fd::nil);
	stderr = fildes(2);
	fd = fildes(fd.fd);
	c <-= pid;
	d := readfile(fd);
	fd = nil;
	if(d == nil)
		rc <-= "";
	else
		rc <-= string d;
}

pipein(buf: string): ref FD
{
	p := array[2] of ref FD;
	if(pipe(p) < 0){
		fprint(stderr, "pipe: %r\n");
		return nil;
	}
	c := chan of int;
	spawn bufwriteproc(buf, p[1], c);
	<-c;
	p[1] = nil;
	return p[0];
}

pipeout(): (ref FD, chan of string)
{
	p := array[2] of ref FD;
	if(pipe(p) < 0){
		fprint(stderr, "pipe: %r\n");
		return (nil, nil);
	}
	c := chan of int;
	rc:= chan of string;
	spawn bufreadproc(p[0], c, rc);
	<-c;
	p[0] = nil;
	return (p[1], rc);
}

voicedone()
{
	fd := open("/mnt/voice/speak", OWRITE);
	if(fd != nil)
		fprint(fd, "completed\n");
	fd = nil;
}

xoutwriteproc(x: ref Xcmd, c: chan of string)
{
	edfd: ref FD;
	name := sprint("[%s %s %d]", x.dir, cmdname(x.cmd), x.pid);
	some := 0;
	when := now();
	for(;;){
		s := <-c;
		if(s == nil)
			break;
		ns: string;
		done := 0;
		do {
			alt {
			ns = <-c =>
				if(ns != nil)
					s += ns;
				else
					done = 1;
			* =>
				ns = nil;
			}
		} while(ns != nil);
		for(i:= 0; i < 2; i++){
			if(edfd == nil){
				# this is a race, potentially.
				tr := Tree.find(x.tid);
				if(tr != nil){
					ed := newedit(tr, name, 1, 0);
					if(ed != nil)
						edfd = open(ed.body.path+"/data", OWRITE);
				}
			}
			if(edfd == nil)
				edfd = stderr;
			seek(edfd, big 0, 2);
			d := array of byte s;
			some++;
			nw := write(edfd, d, len d);
			if(nw == len d)
				break;
			# try once more by recreating the panel
			edfd = nil;
		}
		if(done)
			break;
	}
	if(now() - when > 2)
		spawn voicedone();
}

xoutproc(x: ref Xcmd, xfd: ref FD, c: chan of int)
{
	pid := pctl(NEWFD, 0::1::2::xfd.fd::nil);
	stderr = fildes(2);
	xfd = fildes(xfd.fd);
	c <-= pid;
	buf := array[8192] of byte;
	sc := chan[32] of string;
	spawn xoutwriteproc(x, sc);
	for(;;){
		nr := read(xfd, buf, len buf);
		if(nr <= 0){
			sc <-= nil;
			break;
		}
		sc <-= string buf[:nr];
	}
	x.done = 1;
	xec <-= x;
}

# can't spawn copy, which returns a value
xcopy(fd1, fd2: ref FD, c: chan of int)
{
	c <-= pctl(0, nil);
	copy(fd1, fd2);
}

xproc(x: ref Xcmd, c: chan of int)
{
	pid := pctl(NEWPGRP|NEWFD, 0::1::2::x.in.fd::x.out.fd::x.err.fd::nil);
	stderr = fildes(2);
	x.in = fildes(x.in.fd);
	x.out = fildes(x.out.fd);
	x.err = fildes(x.err.fd);
	c <-= pid;
	# This executes the command in a new environment,
	# we should preserve the environment, so that o/live is indeed
	# a typescript. Each tree could be its own environment.

	if(x.host){
		dup(x.in.fd, 0);
		dup(x.out.fd, 1);
		dup(x.err.fd, 2);
		x.in = x.out = x.err = nil;
		cmd := x.cmd;
		host := getenv("emuhost");
		if(len x.file == 0)
			x.file = x.dir;
		case host {
		"Plan9" =>
			file := x.file;
			dir := x.dir;
			if(fsdir == ""){
				file = os->filename(file);
				dir = os->filename(dir);
			}
			if(mknscmd != nil)
				cmd = mknscmd + cmd;
			cmd = "file='"+file+"';" + cmd;
			cmd = str->quoted(list of {cmd});
			cmd = "os -d " + dir + " rc -c " + cmd;
			system(xctx, cmd);
		"Nt" =>
			cmd = "os -d " + os->filename(x.dir) + cmd;
			system(xctx, cmd);
		* =>
			cmd = str->quoted(list of {cmd});
			cmd = "os -d " + os->filename(x.dir) + " sh -c " + cmd;
			system(xctx, cmd);
		}
	} else {
		dup(x.in.fd, 0);
		dup(x.out.fd, 1);
		dup(x.err.fd, 2);
		x.in = x.out = x.err = nil;
		chdir(x.dir);
		system(xctx, x.cmd);
	}
	
}

Xcmd.new(cmd: string, file, dir: string, in, out: ref FD, tid: int, host: int): ref Xcmd
{
	x := ref Xcmd(tid, -1, -1, cmd, host, file, dir, in, out, nil, 0);
	if(x.in == nil)
		x.in = open("/dev/null", OREAD);
	if(x.in == nil){
		fprint(stderr, "/dev/null: %r\n");
		return nil;
	}
	p := array[2] of ref FD;
	if(pipe(p) < 0){
		fprint(stderr, "pipe: %r\n");
		return nil;
	}
	x.err = p[1];
	if(x.out == nil)
		x.out = p[1];
	c := chan of int;
	spawn xproc(x, c);
	x.pid = <-c;
	p[1] = nil;
	spawn xoutproc(x, p[0], c);
	x.rpid = <-c;
	p[0] = nil;
	xsc <-= x;
	return x;
}

ftext(short: int): string
{
	text := "";
	nl: list of ref Xcmd;
	for(nl = xcmds; nl != nil; nl = tl nl)
		if(short)
			text += sprint("%d ", (hd nl).pid);
		else if(!(hd nl).host)
			text += sprint("%%echo killgrp >/prog/%d/ctl\t# %s\n",
				(hd nl).pid, (hd nl).cmd);
		else if(os->emuhost == "Plan9")
			text  += sprint("!kill %s|rc\t# %d\n",
			basename((hd nl).cmd, nil),(hd nl).pid);
		else
			text  += sprint("!killall %s\t# %d\n",
				(hd nl).cmd, (hd nl).pid);
	if(text == "")
		text = "none";
	return text;
}

Xcmd.ftext(short: int): string
{
	c := chan of string;
	if(short)
		xsqc <-= c;
	else
		xqc <-= c;
	return <-c;
}

# Directories are always shown at the tree given.
# Files from other trees are moved to the tree (and screen) given.
# Otherwise, a new edit is created.
# Some files, eg. pdfs, are copied to /mnt/view instead.
newedit(tr: ref Tree, path: string, ismsg: int, force: int): ref Edit
{
	ed: ref Edit;
	ed = nil;
	if(!ismsg)
		path = names->cleanname(path);
	if(viewdoc(path))
		return nil;
	ed = tr.findedit(path);
	if(ed == nil && !force)
		for(trl := trees; trl != nil && ed == nil; trl = tl trl)
			ed = (hd trl).findedit(path);
	if(ed == nil || (tagof ed == tagof Edit.Dir && tr.tid != ed.tid)){
		ed = Edit.new(path, tr.tid, ismsg);
		if(ed == nil && !ismsg){
			msg(tr, tr.path, path + ": new file\n");
			fd := create(fsname(path), OWRITE, 8r664);
			if(fd == nil)
				msg(tr, tr.path, sprint("%s: %r\n", path));
			fd = nil;
			ed = Edit.new(path, tr.tid, ismsg);
		}
		if(ed != nil){
			tr.addedit(ed);
			ed.mk();
			ed.get();
		}
		return ed;
	}
	pick edp := ed {
	Dir =>
		ed.get();		# refresh contents
		tr.col.ctl("show\n");	# unhide, if hidden.
	* =>
		if(ed.tid != tr.tid){
			otr := Tree.find(ed.tid);
			otr.deledit(ed);
			tr.addedit(ed);
			cols := panels->cols(tr.scr);
			if(len cols == 0)
				return ed;
			mc := sprint("moveto %s\nshow\n", hd cols);
			if(ed.col.ctl(mc) < 0)
				fprint(stderr, "o/x: ctl: %r\n");
		} else
			ed.col.ctl("show\n");
	}
	return ed;
}

# ignore files that o/open should deal with.
viewdoc(path: string): int
{
	(nil, ext) := splitr(tolower(path), ".");
	if(ext != nil)
		case tolower(ext) {
		"pdf" or "ps" or "eps" or
		"gif" or "jpg" or "jpeg" or "png" or "tiff" or
		"doc" or "xls" or "ppt" =>
			return 1;
		}
	return 0;
}

msgfd(tr: ref Tree, path: string): ref FD
{
	name := sprint("[%s]", path);
	ed := newedit(tr, name, 1, 0);
	if(ed == nil || ed.body == nil)
		return stderr;
	fd := open(ed.body.path + "/data", OWRITE);
	if(fd != nil)
		seek(fd, big 0, 2);
	return fd;
}

msg(tr: ref Tree, dir: string, s: string)
{
	fd :=msgfd(tr, dir);
	if(fd == nil){
		s = "(no panel, using stderr) " + s;
		fd = stderr;
	}
	data := array of byte s;
	write(fd, data, len data);
}

deledit(ed: ref Edit)
{
	tr := Tree.find(ed.tid);
	if((e := ed.cleanto("Close", nil)) != nil)
		msg(tr, ed.dir, sprint("%s: %s\n", ed.path, e));
	else
		ed.close();
}

putedit(ed: ref Edit, where: string)
{
	tr := Tree.find(ed.tid);
	cmd := "Put";
	if(where != ed.path)
		cmd = "New";
	if((e := ed.cleanto(cmd, where)) != nil)
		msg(tr, ed.dir, sprint("%s: %s\n", ed.path, e));
	else
		ed.put(where);
}

findedit(t: ref Edit, s: string): ref Edit
{
	tr := Tree.find(t.tid);
	ed := tr.findedit(s);
	if(ed == nil)
		for(trl := trees; trl != nil; trl = tl trl)
			ed = (hd trl).findedit(s);
	if(ed == nil)
		msg(tr, nil, sprint("%s: no such edit", s));
	return ed;
}

