# Generic panel coordination
# One process coordinates operations within the tree, so that
# there are no races.
Wtree: module {
	PATH: con "/dis/o/live/wtree.dis";

	# Operations sent to the tree from I/O processes
	Treeop: adt {
		pick {
		Kbd =>
			s:	string;
		Mouse =>
			m:	ref Gui->Cpointer;
			mc:	chan of ref Gui->Cpointer;
			rc:	chan of int;
		Layout =>
			path:	string;
			auto:	int;
		Insdel =>
			path:	string;
			ctl:	string;
		Close or Focus =>
			path:	string;
		Tags =>
		Update =>
			path:	string;
			vers:	int;
			ctls:	string;
			data:	array of byte;
			edits:	string;
		}
	};

	More, Max, Full: con iota;	# for Tree.size and Treeop.Size.to

	Tree: adt {
		root:	string;		# path in o/mero for our /
		slash:	ref Wpanel->Panel;	# "/" for the entire tree
		dslash:	ref Wpanel->Panel;	# "/" for the shown portion
		opc:	chan of ref Treeop;	# internal use only
		kbdfocus:	ref Wpanel->Panel;
		sel:	ref Wpanel->Panel;

		start:	fn(name: string): ref Tree;

		path:	fn(t: self ref Tree, p: ref Wpanel->Panel): string;
		walk:	fn(t: self ref Tree, path: string): ref Wpanel->Panel;
		ptwalk:	fn(t: self ref Tree, xy: Draw->Point,
				atomok: int): ref Wpanel->Panel;
		size:	fn(t: self ref Tree, p: ref Wpanel->Panel, op: int);
		layout:	fn(t: self ref Tree, p: ref Wpanel->Panel, auto: int);
		tags:	fn(t: self ref Tree);
		focus:	fn(t: self ref Tree, p: ref Wpanel->Panel);
		dump:	fn(t: self ref Tree, p: ref Wpanel->Panel);
	};

	init:	fn(d: Livedat);
	panelmouse:	fn(t: ref Tree, p: ref Wpanel->Panel, m: ref Gui->Cpointer,
			cm: chan of ref Gui->Cpointer): int;
	panelkbd:	fn(t: ref Tree, p: ref Wpanel->Panel, k: int);
	tagmouse:	fn(t: ref Tree, p: ref Wpanel->Panel,
			m: ref Gui->Cpointer, mc: chan of ref Gui->Cpointer);
	panelctl:		fn(t: ref Tree, p: ref Wpanel->Panel, s: string): int;
};
