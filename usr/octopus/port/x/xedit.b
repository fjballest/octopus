implement Oxedit;
include "mods.m";
	msg, fatal, newedit: import oxex;
	readdev: import io;
	cleanname, rooted, basename: import names;
	elogapply: import samlog;

pidgen := 1;	# panel id generator

init(d: Oxdat, dir: string)
{
	initmods(d->mods);
	fsdir = dir;
}

Edit.text(ed: self ref Edit): string
{
	text: string;
	if(ed == nil)
		return "<nil edit>";
	pick edp := ed {
	Dir =>
		text = sprint("d %s [%s]", ed.path, ed.dir);
	Msg =>
		text = sprint("m %s [%s]", ed.path, ed.dir);
	File =>
		text = sprint("f %s [%s]", ed.path, ed.dir);
		if(edp.dirty)
			text += " dirty";
		else
			text += " clean";
		text += sprint(" q0 %d q1 %d", edp.q0, edp.q1);
	}
	return text;
}

Tree.new(path: string): ref Tree
{
	tid := ++pidgen;
	if(debug)
		fprint(stderr, "o/x: new tree %s id %d\n", path, tid);
	tr := ref Tree(tid, path, nil, nil, nil, nil, nil);
	trees = tr::trees;
	return tr;
}

Tree.find(tid: int): ref Tree
{
	for(trl := trees; trl != nil; trl = tl trl){
		tr := hd trl;
		if(tr.tid == tid)
			return tr;
	}
	return nil;
}

Tree.close(tr: self ref Tree)
{
	edl := tr.eds;		# File.close will try to tr.deledit()
	tr.eds = nil;		# Avoid that while we are scanning that list.
	for(; edl != nil; edl = tl edl)
		(hd edl).close();
	if(tr.tag != nil){
		tr.tag.close();
		tr.tag = nil;
	}
	if(tr.col != nil){
		tr.col.close();
		tr.col = nil;
	}
	tr.tid = -1;	# posion
	nl: list of ref Tree;
	nl = nil;
	for(trl := trees; trl != nil; trl = tl trl)
		if(hd trl != tr)
			nl = hd trl :: nl;
	if(debug)
		fprint(stderr, "o/x: close tree %s\n", tr.path);
	trees = nl;
}

Tree.mk(tr: self ref Tree, scr: string)
{
	id := tr.tid;
	tr.col = ui.new("col:tree", id);
	if(tr.col == nil)
		error("o/x: ui.new");
	tr.tag = tr.col.new("tag:tree", id);
	fd := open(tr.tag.path+"/data", OWRITE|OTRUNC);
	if(fd == nil)
		error("o/x: tag open");
	text := sprint("Ox %d", pctl(0, nil));
	text += sprint(" %s Dup ", tr.path);
	data := array of byte text;
	if(write(fd, data, len data) != len data)
		error("o/x: tag write");
	tr.tag.ctl(sprint("sel %d %d\n", len text, len text));
	tr.xtag = tr.col.new("label:cmds", id);
	if(tr.xtag == nil)
		error("o/x: ui.new");
	fd = open(tr.xtag.path+"/data", OWRITE|OTRUNC);
	if(fd == nil)
		error("o/x: tag open");
	data = array of byte "no cmds";
	if(write(fd, data, len data) != len data)
		error("o/x: tag write");
	tr.scr = showit(tr.col, scr, tagof Edit.Dir);
}

Tree.findedit(tr: self ref Tree, name: string): ref Edit
{
	for(edl := tr.eds; edl != nil; edl = tl edl){
		ed := hd edl;
		if(ed.path == name)
			return ed;
	}
	return nil;
}

lrul(edl: list of ref Edit, k: int): (ref Edit, int)
{
	led: ref Edit;
	led = nil;
	ltime := now();
	n := 0;
	for(; edl != nil; edl = tl edl){
		ed := hd edl;
		if(tagof(ed) == k){
			if(!ed.keep && !ed.dirty && ed.lru < ltime){
				n++;
				led = ed;
				ltime = ed.lru;
			}
		}
	}
	return (led, n);
}

keepatmost(tr: ref Tree, max: int, tag: int)
{
	for(;;){
		(ed, n) := lrul(tr.eds, tag);
		if(ed == nil || n <= max)
			break;
		ed.close();
	}
}

Tree.lru(tr: self ref Tree)
{
	Ndirs: con 3;
	Neds: con 8;
	Nmsgs: con 2;

	keepatmost(tr, Ndirs, tagof(Edit.Dir));
	keepatmost(tr, Neds, tagof(Edit.File));
	keepatmost(tr, Nmsgs, tagof(Edit.Msg));
}

Tree.addedit(tr: self ref Tree, ed: ref Edit)
{
	ed.keep = 1;
	tr.eds = ed::tr.eds;
	tr.lru();
	ed.tid = tr.tid;
	ed.keep = 0;
}

Tree.deledit(tr: self ref Tree, ed: ref Edit)
{
	nl: list of ref Edit;
	nl = nil;
	for(edl := tr.eds; edl != nil; edl = tl edl){
		if(hd edl != ed)
			nl = hd edl :: nl;
	}
	tr.eds = nl;
}

Tree.dump(tr: self ref Tree)
{
	fprint(stderr, "tree %s\n", tr.path);
	for(edl := tr.eds; edl != nil; edl = tl edl)
		fprint(stderr, "\t%s\n", (hd edl).text());
}

msgpath(n: string): string
{
	(p, nil) := splitl(n[1:], "] ");
	if(p == nil || p == "")
		p = n[1:];
	return p;
}

Edit.new(name: string, tid: int, msg: int): ref Edit
{
	ed: ref Edit;
	if(msg){
		path := name;
		if(name[0] == '[')
			path = msgpath(name);
		else
			name = sprint("[%s]", name);
		ed = ref Edit.Msg(name, path, ++pidgen,
			tid, 0, 0, now(), Csam, nil, nil, nil, nil, nil, nil, 0, 0, 0, 0);
	} else {
		(e, d) := stat(fsname(name));
		if(e < 0)
			return nil;
		if(d.qid.qtype&QTDIR)
			ed = ref Edit.Dir(name, name, ++pidgen,
				tid, 0, 0, now(), Csam, nil, nil, nil, nil, nil, nil,
				0, 0, 0, 0, Qid(big 0, 0, QTDIR));
		else
			ed = ref Edit.File(name, names->dirname(name), ++pidgen,
				tid, 0, 0, now(), Csam, nil, nil, nil, nil, nil, nil, 
				0, 0, 0, 0, Qid(big 0, 0, 0), nil);
	}
	if(debug)
		fprint(stderr, "o/x: new edit %s tid %d\n", name, tid);
	return ed;
}

Edit.close(ed: self ref Edit)
{
	tid := ed.tid;
	if(tid == -1) # already closed
		return;
	ed.tid = -1;
	if(ed.col != nil)
		ed.col.close();
	if(ed.tag != nil)
		ed.tag.close();
	if(ed.body != nil)
		ed.body.close();
	ed.col = ed.tag = ed.body = nil;
	if(debug)
		fprint(stderr, "o/x: close edit %s tid %d\n", ed.path, ed.tid);
	tr := Tree.find(tid);
	tr.deledit(ed);
}

showit(p: ref Panel, scr: string, tag: int): string
{
	if(scr == nil){
		scrs := panels->screens();
		if(len scrs == 0){
			omero := getenv("omero");
			create(omero+"/main", OREAD, 8r775|DMDIR);
			scrs = panels->screens();
		}
		if(len scrs == 0)
			fatal("o/x: no screens");
		scr = hd scrs;
	}
	cols := panels->cols(scr);
	if(len cols == 0)
		fatal("o/x: no columns");
	# dirs and messages shown on the rightmost column
	# files shown on the leftmost column.
	if(tag != tagof Edit.File)
		while(cols != nil && tl cols != nil)
			cols = tl cols;
	p.ctl(sprint("copyto %s\n", hd cols));
	return scr;
}

Edit.mk(ed: self ref Edit)
{
	col: ref Panel;
	tagtext := "";
	id := ed.id;
	col = ed.col = ui.new("col:ox", id);
	if(col == nil)
		error(sprint("o/x: ui.new: %r"));
	body :=  "text:file";
	if(tagof ed == tagof Edit.Dir)
		body = "tbl:body";
	tagtext += " ";
	ed.tag = col.newnamed(sprint("tag:file.%d", id), id);
	ed.body = col.newnamed(sprint("%s.%d", body, id), id);
	if(ed.tag == nil || ed.body == nil)
		error(sprint("o/x: ui.new: %r"));
	if(tagof ed == tagof Edit.Msg){
		ctl := "font T\n" + "temp\n";
		if(scroll)
			ctl += "scroll\n";
		ed.body.ctl(ctl);
	}
	fd := open(ed.tag.path+"/data", OWRITE|OTRUNC);
	if(fd == nil)
		error (sprint("o/x: new: %r\n"));
	tagtext = sprint("%s %s", ed.path, tagtext);
	data := array of byte tagtext;
	if(write(fd, data, len data) != len data)
		error (sprint("o/x: new: write: %r\n"));
	ed.tag.ctl(sprint("sel %d %d\n", len tagtext, len tagtext));
	tr := Tree.find(ed.tid);
	showit(ed.col, tr.scr, tagof ed);
}

Edit.put(ed: self ref Edit, where: string): int
{
	ffd: ref FD;
	tr := Tree.find(ed.tid);
	pick edp := ed {
	Msg =>
		ffd = create(fsname(where), OWRITE, 8r664);
		if(ffd == nil){
			msg(tr, ed.dir, sprint("%s: %r\n", where));
			return -1;
		}
		fd := open(ed.body.path+"/data", OREAD);
		if(fd == nil){
			msg(tr, ed.dir, sprint("open %s/data: %r\n", ed.body.path));
			return -1;
		}
		if(io->copy(ffd, fd) < 0){
			msg(tr, ed.dir, sprint("put %s: %r\n", where));
			return -1;
		}
		if(debug)
			fprint(stderr, "o/x: put %s\n", where);
	File =>
		if(where != ed.path)
			ffd = create(fsname(where), OWRITE, 8r664);
		else
			ffd = open(fsname(where), OWRITE|OTRUNC);
		if(ffd == nil){
			msg(tr, ed.dir, sprint("%s: %r\n", where));
			return -1;
		}
		fd := open(ed.body.path+"/data", OREAD);
		if(fd == nil){
			msg(tr, ed.dir, sprint("open %s/data: %r\n", ed.body.path));
			return -1;
		}
		if(io->copy(ffd, fd) < 0){
			msg(tr, ed.dir, sprint("put %s: %r\n", where));
			return -1;
		}
		if(debug)
			fprint(stderr, "o/x: put %s\n", where);
		ffd = nil;
		fd = nil; 		# forze stat to see new qid
		if(where == ed.path){
			(e, d) := stat(fsname(ed.path));
			if(e < 0){
				msg(tr, ed.dir, sprint("stat %s: %r\n", ed.path));
				return -1;
			}
			edp.qid = d.qid;
			edp.dirty = 0;
			edp.body.ctl("clean");
		} else
			msg(tr, ed.dir, sprint("%s: new file\n", where));
	}
	return 0;
}

Edit.get(ed: self ref Edit): int
{
	if(tagof(ed) == tagof(Edit.Msg))
		return 0;
	tr := Tree.find(ed.tid);
	fd := open(ed.body.path+"/data", OWRITE|OTRUNC);
	if(fd == nil){
		msg(tr, ed.dir, sprint("open: %s/data: %r\n", ed.body.path));
		return -1;
	}
	pick edp := ed {
	File =>
		ffd := open(fsname(ed.path), OREAD);
		if(io->copy(fd, ffd) < 0){
			msg(tr, ed.dir, sprint("get %s: %r\n", ed.path));
			return -1;
		}
		(e, d) := fstat(ffd);
		if(e < 0){
			msg(tr, ed.dir, sprint("fstat %s: %r\n", ed.path));
			return -1;
		}
		edp.qid = d.qid;
		edp.dirty = 0;
		edp.body.ctl("clean");
	Dir =>
		(dirs, n) := readdir->init(fsname(ed.path), NAME);
		if(n < 0){
			msg(tr, ed.dir, sprint("open: %s: %r\n", ed.path));
			return -1;
		} else if(n == 0)
			fprint(fd, "none\n");
		else {
			text := "";
			for(i := 0; i < n; i++)
				text += dirs[i].name + "\n";
			data := array of byte text;
			if(write(fd, data, len data) != len data){
				msg(tr, ed.dir, sprint("write: %s/data: %r\n", ed.body.path));
				return -1;
			}
		}
	}
	if(debug)
		fprint(stderr, "o/x: get %s\n", ed.path);
	return 0;
}

Edit.getedits(ed: self ref Edit)
{
	if(ed == nil)
		return;
	fd := open(ed.body.path + "/data", OREAD);
	if(fd != nil){
		if((s := readfile(fd)) != nil)
			ed.buf = Tblk.new(string s);
		(nil, d) := fstat(fd);
		ed.vers= d.qid.vers;
	}
	if(ed.buf == nil)
		ed.buf = Tblk.new("");
	attrs := ed.body.attrs();
	if(attrs != nil)
		(ed.q0, ed.q1) = attrs.sel;
	else
		fprint(stderr, "%s: no attrs\n", ed.body.path);
	ed.edited = 0;
}

Edit.clredits(ed: self ref Edit)
{
	ed.buf = nil;
	ed.edited = 0;
	ed.elog = nil;
	ed.elogbuf = nil;
}

lastid := 0;
findpanel(id: int): (ref Tree, ref Edit)
{
	# when id is 0 we select the last tree required, which
	# correspond to the last tree with activity.
	# this makes echos to /mnt/ui/appl/col:ox*/ctl use
	# the last screen used.

	if(id == 0 && lastid != 0)
		id = lastid;
	for(trl := trees; trl != nil; trl = tl trl){
		tr := hd trl;
		for(edl := tr.eds; edl != nil; edl = tl edl){
			ed := hd edl;
			if(ed.tag != nil && ed.tag.id == id){
				lastid = id;
				return (tr, ed);
			}
		}
		if(tr.col != nil && tr.col.id == id){
			lastid = id;
			return (tr, nil);
		}
	}
	return (nil, nil);
}

findseled(): ref Edit
{
	path := readdev("/mnt/snarf/sel", nil);
	if(path == nil)
		return nil;
	name := basename(path, nil);
	for(trl := trees; trl != nil; trl = tl trl){
		tr := hd trl;
		for(edl := tr.eds; edl != nil; edl = tl edl){
			ed := hd edl;
			if(ed.body != nil && basename(ed.body.path, nil) == name)
				return ed;
		}
	}
	return nil;
}

fsname(s: string): string
{
	if(fsdir == "")
		return s;
	if(s[0] == '/')
		return fsdir + s;
	cwd := workdir->init();
	return fsdir + cleanname(rooted(cwd, s));
}

Edit.cleanto(ed: self ref Edit, cmd: string, arg: string): string
{
	pick edp := ed {
	Msg =>
		if(cmd == "Put"){
			(e, nil) := stat(fsname(ed.path));
			if(e >= 0)
				return "file already exists";
		}
	File =>
		if(edp.lastcmd == cmd)
			return nil;
		edp.lastcmd = cmd;
		case cmd {
		"Put" =>
			(e, d) := stat(fsname(ed.path));
			if(e < 0)
				return nil;
			if(d.qid.path != edp.qid.path || d.qid.vers != edp.qid.vers)
				return sprint("file changed by %s", d.muid);
		"New" =>
			(e, nil) := stat(fsname(arg));
			if(e >= 0)
				return sprint("%s: file exists", arg);
		* =>
			if(edp.dirty)
				return "put changes first";
		}
	}
	return nil;
}

Elogbuf.new(): ref Elogbuf
{
	return ref Elogbuf(array[0] of ref Elog, 0);
}

Elogbuf.push(e: self ref Elogbuf, b: ref Elog)
{
	if(e.n == len e.b){
		nb := array[len e.b + 16] of ref Elog;
		nb[0:] = e.b[0:len e.b];
		for(i := len e.b; i < len nb; i++)
			nb[i] = nil;
		e.b = nb;
	}
	e.b[e.n++] = ref *b;
}

Elogbuf.pop(e: self ref Elogbuf): ref Elog
{
	if(e.n == 0)
		return nil;
	b := e.b[--e.n];
	e.b[e.n] = nil;		# poison
	return b;
}
