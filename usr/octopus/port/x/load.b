implement Oxload;
include "mods.m";
	Dir: import sys;
	readdev: import io;
	ui, debug, Tree, Edit: import oxedit;
	fatal: import oxex;
	prefix, splitr: import str;
	dirname: import names;

init(d: Oxdat)
{
	initmods(d->mods);
}

lsnames(dirs: array of ref Dir, pref: string): list of string
{
	l: list of string;
	for(i := 0; i < len dirs; i++)
		if(prefix(pref, dirs[i].name))
			l = dirs[i].name::l;
	return l;
}

loadtreeedit(tr: ref Tree, path: string, nm: string)
{
	(nil, ids) := splitr(nm, ".");
	tpath := path + "/" + nm;
	tags := readdev(tpath+"/data", nil);
	if(len tags == 0)
		fatal("o/x: "+tpath+": read failed");
	if(tags[0] == '[')
		tags = tags[1:];
	(nt, toks) := tokenize(tags, " \t\n");
	if(nt < 1)
		fatal("o/x: no path in edit tag");
	edname := hd toks;
	if(debug)
		fprint(stderr, "o/x: loading edit %s\n", edname);
	ed := Edit.new(edname, tr.tid, edname[0] == '[');
	ed.tag = ui.new(tpath, ed.id);
	if(ed.tag == nil)
		fprint(stderr, "edit tag: %s: %r\n", tpath);
	bpath: string;
	if(tagof ed == tagof Edit.Dir){
		ed.col = tr.col;
		bpath = path + "/" + "tbl:body." + ids;
	} else {
		ed.col = ui.new(path, ed.id);
		bpath = path + "/" + "text:file." + ids;
	}
	ed.body = ui.new(bpath, ed.id);
	if(ed.body == nil)
		fprint(stderr, "edit body: %s: %r\n", bpath);
	if(ed.col == nil || ed.tag == nil || ed.body == nil)
		fatal("o/x: dir being loaded is gone?");
	tr.addedit(ed);
	if(tagof ed == tagof Edit.File)
		ed.get();	# update contents
}

loadtree(path: string): ref Tree
{
	(dirs, n) := readdir->init(path, readdir->NONE);
	if(n < 0)
		fatal("o/x: failed to load tree");
	tagl := lsnames(dirs, "tag:tree.");
	cmdl := lsnames(dirs, "tag:cmds.");
	if(tagl == nil || cmdl == nil)
		fatal("o/x: no tree label");
	tagpath := path + "/" + hd tagl;
	cmdpath := path + "/" + hd cmdl;
	ttag := readdev(tagpath+"/data", nil);
	if(len ttag == 0)
		fatal("o/x: can't read tree tag");
	(nt, toks) := tokenize(ttag, " \t\n");
	if(nt < 3)
		fatal("o/x: short tree tag: "+ttag);
	dir := hd tl tl toks;
	if(debug)
		fprint(stderr, "loading tree %s\n", dir);
	tr := Tree.new(dir);
	tr.col = ui.new(path, tr.tid);
	if(tr.col == nil)
		fprint(stderr, "edit col: %s: %r\n", path);
	tr.tag = ui.new(tagpath, tr.tid);
	if(tr.col == nil)
		fprint(stderr, "edit tag: %s: %r\n", tagpath);
	tr.xtag = ui.new(cmdpath, tr.tid);
	if(tr.col == nil)
		fprint(stderr, "edit xtag: %s: %r\n", cmdpath);
	if(tr.col == nil || tr.tag == nil || tr.xtag == nil)
		fatal("o/x: can't load tree ui");
	for(dl := lsnames(dirs, "tag:file."); dl != nil; dl = tl dl)
		loadtreeedit(tr, path, hd dl);
	return tr;
}

loadedit(tr: ref Tree, path: string, nm: string)
{
	path += "/" + nm;
	(dirs, n) := readdir->init(path, readdir->NONE);
	if(n < 0)
		fatal("o/x: failed to read edit dir");
	l := lsnames(dirs, "tag:file.");
	if(l == nil)
		fatal("o/x: no edit tag");
	loadtreeedit(tr, path, hd l);
}

loadui(path: string): chan of ref Panels->Pev
{
	path = names->rooted(workdir->init(), path);
	path = names->cleanname(path);
	ui = Panel.init(path);
	if(ui == nil)
		fatal("o/x: failed to load ui");
	evc := ui.evc();
	(dirs, n) := readdir->init(path, readdir->NONE);
	if(n < 0)
		fatal("o/x: failed to load ui");
	# load trees first, then their edits.
	tr: ref Tree;
	for(l := lsnames(dirs, "col:tree."); l != nil; l = tl l)
		tr = loadtree(path + "/" + hd l);
	for(l = lsnames(dirs, "col:ox."); l != nil; l = tl l)
		loadedit(tr, path, hd l);
	return evc;
}


