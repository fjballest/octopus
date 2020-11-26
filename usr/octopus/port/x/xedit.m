Oxedit: module {
	PATH:	con "/dis/o/x/xedit.dis";

	Tree: adt {
		tid:	int;		# tree id, never reused.
		path:	string;		# for debug, mostly
		scr:	string;		# screen where viewed
		col:	ref Panels->Panel;
		tag:	ref Panels->Panel;
		xtag:	ref Panels->Panel;
		eds:	list of ref Edit;

		new:	fn(path: string): ref Tree;
		find:	fn(tid: int):	ref Tree;
		close:	fn(t: self ref Tree);
		mk:	fn(ed: self ref Tree, scr: string);

		findedit:	fn(t: self ref Tree, path: string): ref Edit;
		addedit:	fn(t: self ref Tree, ed: ref Edit);
		deledit: 	fn(t: self ref Tree, ed: ref Edit);
		lru:	fn(t: self ref Tree);
		dump:	fn(t: self ref Tree);
	};

	# Elog.typex
	Empty:	con 0;
	Null :	con '-';
	Delete :	con 'd';
	Insert :	con 'i';
	Replace:	con 'r';
	Filename :	con 'f';

	# support for sam
	Elog: adt{
		typex: int;			# Delete, Insert, Filename
		q0: int;			# location of change (unused in f)
		nd: int;			# number of deleted characters
		r: string;
	};

	# support for sam
	Elogbuf: adt {
		b:	array of ref Elog;
		n:	int;

		new:	fn(): ref Elogbuf;
		push:	fn(e: self ref Elogbuf, b: ref Elog);
		pop:	fn(e: self ref Elogbuf): ref Elog;
	};

	# Edit.edited (pending changes for Edit made by sam)
	Esel, Etext, Ename:	con 1<<iota;

	# Default commands
	Csam:	con '#';
	Crc:	con ';';
	Csh:	con '%';
	Ccmd:	con '!';	# ; or % depending on -9 flag

	Edit: adt {
		path:	string;		# file path or window name
		dir:	string;		# for look/exec
		id:	int;		# unique edit id
		tid:	int;		# tree id
		keep:	int;		# do not auto-collect
		dirty:	int;		# changes made. (Dirs are never dirty)
		lru:	int;		# time of last lookup
		dfltcmd:	int;
		tag:	ref Panels->Panel;
		body:	ref Panels->Panel;
		col:	ref Panels->Panel;

		# support for sam
		elog:	ref Elog;
		elogbuf:	ref Elogbuf;
		buf:	ref Tblks->Tblk;	# with edited file text
		vers:	int;		# as of getedits()
		edited:	int;		# Esel|Etext according to what changed
		q0:	int;
		q1:	int;

		pick {
		File =>
			qid:	Sys->Qid;
			lastcmd:	string;
		Msg =>
		Dir =>
			qid:	Sys->Qid;
		}
	
		new:	fn(name: string, tid: int, msg: int): ref Edit;
		close:	fn(t: self ref Edit);
		mk:	fn(ed: self ref Edit);
		get:	fn(ed: self ref Edit): int;
		put:	fn(ed: self ref Edit, where: string): int;
		cleanto:	fn(ed: self ref Edit, cmd: string, arg: string): string;
		text:	fn(ed: self ref Edit): string;

		# support for sam
		getedits:	fn(ed: self ref Edit);
		clredits:	fn(ed: self ref Edit);
	};

	init:	fn(d: Oxdat, dir: string);
	findpanel:	fn(id: int): (ref Tree, ref Edit);
	findseled:	fn(): ref Edit;
	fsname:	fn(s: string): string;

	fsdir:	string;
	trees:	list of ref Tree;
	ui:	ref Panels->Panel;
	seled:	ref Edit;		# last edit selected/in use
	scroll:	int;
	sharedns:	int;
	debug:	int;

};
