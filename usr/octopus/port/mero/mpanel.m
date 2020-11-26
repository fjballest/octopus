# o/mero definitions.

Panels: module {

	PATH: con "/dis/o/mero/mpanel.dis";

	Tappl, Trepl: con iota;	# Application and viewer trees

	# Qid types for panels
	# Qids are panelid(16bits) replid(8bits) type(8bits)
	Qdir,		# directory for panel
	Qdata,		# data file
	Qctl,		# attributes and ctl ops
	Qolive,		# connection to viewer
	Qedits,		# editions
	Qmax: con iota;

	# Common panel attributes. Individual panels may add more.
	Atag,	# show its tag
	Ashow,	# shown in viewer (not hidden)
	Aappl,	# created by application [id [pid]]
	Amax: con iota;

	# One per actual panel.
	# while the panel should be kept alive.
	Panel: adt {
		id:	int;	# unique panel identifier
		aid:	int;	# id supplied by user to appl
		pid:	int;	# process id, when supplied by appl.
		name:	string;
		impl:	Pimpl;	# implementor
		container:	int;	# true for container
		editions:	int;	# true for panels with edits file
		editing:	int;	# between edstart/edend
		data:	array of byte;
		evers:	int;	# version for edition changes.
		edits:	string;
		repl:	array of ref Repl;
		nrepl:	int;

		ok:	fn(p: self ref Panel);
		text:	fn(p: self ref Panel) : string;

		new:	fn(name: string): ref Panel;
		lookup:	fn(id: int, rid: int): (ref Panel, ref Repl);
		newrepl:	fn(p: self ref Panel, path: string, t: int): ref Repl;
		close:	fn(p: self ref Panel);
		closerepl:	fn(p: self ref Panel, r: ref Repl);
		put:	fn(p: self ref Panel, data: array of byte, off: big): (int, string);
		newdata:	fn(p: self ref Panel): string;
		newvers:	fn(p: self ref Panel);
		ctl:	fn(p: self ref Panel, r: ref Repl, attr: string):
				(int, string, string); # (update, err, ctl)
		ctlstr:	fn(p: self ref Panel, r: ref Repl): string;

		vpost:	fn(p: self ref Panel, pid: int, ev: string);
		post:	fn(p: self ref Panel, ev: string);
		setattr:	fn(p: self ref Panel, r: ref Repl, id, glob: int, v: string): (int, string, string);
	};

	Attr: adt {
		v:	string;	# value
		vers:	int;	# version
	};

	# One per replica, including the original application panel.
	# Referenced from files referring to the replica.
	# Released when the first file drops its reference to it.
	Repl: adt {
		id:	int;		# position in p.repl array
		pos:	int;		# position in parent container
		dvers:	int;		# qid.vers for panel
		cvers:	int;		# qid.vers for replica ctl
		tree:	int;		# Tappl or Trepl
		path:	string;
		dirq:	big;
		attrs:	array of Attr;		# value and overs for attr

		ctlstr:	fn(r: self ref Repl, vers: int): string;
	};

	init:	fn(dat: Dat, dir: string);
	dump:	fn();

	mkqid:	fn(id, rid, t: int): big;
	qid2ids:	fn(q: big): (int, int, int);
	escape:	fn(s: string): string;
	unescape:fn(s: string): string;
	chkargs:	fn(ctl: list of string, argl: list of (string, int)): string;
};

# Panel implementation. Provided by panel modules loaded just
# to check out that updates made by the user are correct and
# to learn of new panel types.
Pimpl: module {
	init:	fn(d: Dat): list of string;
	pinit:	fn(p: ref Panels->Panel);
	rinit:	fn(p: ref Panels->Panel, r: ref Panels->Repl);
	newdata:	fn(p: ref Panels->Panel): string;
	ctl:	fn(p: ref Panels->Panel, r: ref Panels->Repl, ctl: list of string):
			(int, string, string); #upd., err, ctl
};

