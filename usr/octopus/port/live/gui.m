Gui: module {
	PATH: con "/dis/o/live/gui.dis";

	# Sizes
	Inset:	con 3;	# empty space for inner elements
	Tagwid:	con 10;	# size of the window tag box
	Taght:	con 10;

	# Color ids. indexes in cols[]
	# See gui.b for actual colors used.
	BACK, HIGH, BORD,			# these are from Frame,
	TEXT, HTEXT, NCOL : con iota;		# to use for text panels

	BACK2,		# Panels use backgrounds
	BACK1,		# back2, back1, back0, back, back, ...
	BACK0,		# to emphasize container nesting

	HBORD,		# highlight border (modified tag)
	FBORD,		# focus border

	SET,		# gauges set color
	CLEAR,		# gauges clear color
	MSET,		# menu set color (text)
	MCLEAR,		# menu clear color (text)
	MBACK,		# menu back color

	SHAD,		# Shadow
	MAXCOL:	con iota + NCOL;

	# border (and tag) image ids and depth ids
	# These are precomputed to get images ready to be put in place.
	# bord[image id][depth id] == image for the border at that level in tree.

	Bback,	# background
	Btag,	# tag image
	Bdtag,	# dirty tag
	Bmtag,	# maximized tag
	Bdmtag,	# maximized dirty tag
	NBORD:	con iota;

	# border and tag depth ids, to change them depending on panel depth in the tree
	B0,
	B1,
	B2,
	Bany,
	NBKIND:	con iota;

	# Font ids
	FR,		# regular font
	FB,		# bold font
	FT,		# teletype
	FL,		# large
	FS,		# small
	FI,		# italics
	NFONT:	con iota;


	CMdouble,
	CMtriple:	con 1 + iota;

	Cpointer: adt {
		buttons:	int;
		xy:	Draw->Point;
		msec:	int;
		flags:	int;

		text:	fn(p: self ref Cpointer): string;
	};

	# Args to setcursor
	Arrow, Drag, Waiting, Resize: con iota;

	init: fn(dat: Livedat, ctx: ref Draw->Context):  (chan of int, chan of ref Cpointer, chan of int);
	terminate: 	fn(msg: string);
	lastxy:	fn(): Draw->Point;
	cookclick:	fn(m: ref Cpointer, mc: chan of ref Cpointer): int;
	setcursor:	fn(c: int);
	drawtag:	fn(p: ref Wpanel->Panel);
	getfont:	fn(name: string): ref Draw->Font;
	borderkind:	fn(p: ref Wpanel->Panel): int;
	panelback:	fn(p: ref Wpanel->Panel): ref Draw->Image;
	maxpt:	fn(p1, p2: Draw->Point): Draw->Point;
	minpt:	fn(p1, p2: Draw->Point): Draw->Point;
	readsnarf:	fn(): string;
	writesnarf:	fn(s: string);
	cols: 	array of ref Draw->Image;
	bord: 	array of array of ref Draw->Image;

	exiting:	int;
};
