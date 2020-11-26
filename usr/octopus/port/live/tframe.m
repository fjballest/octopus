Tframe: module {
	PATH:	con "/dis/o/live/tframe.dis";

	# Uses BACK, TEXT, HIGH colors from gui

	Tickwid:	con 3;
	Beofwid:	con 50;	# max width of begin/end of file marks

	Tbox: adt {
		sep:	int;			# 0 or \t or \n
		pos:	int;			# in frame blks
		nr:	int;			# len Tbox.text, save typing.
		pt:	Draw->Point;		# absolute coords for box
		wid:	int;			# width in pixels
		dirty:	int;			# must be drawn.
		txt:	string;			# text in box.
		text:	fn(b: self ref Tbox): string;	# debug dump
	};

	Frame:	adt {
		blks:	ref Tblks->Tblk;	# the source for shown text
		boxes:	array of ref Tbox;	# text boxes on screen (text, or \t, or \n)
		nboxes:	int;
		pos:	int;		# in blks for first rune in frame
		nr:	int;
		ss, se:	int;
		showsel:	int;
		showbeof:	int;
		cols:	array of ref Draw->Image;
		font: 	ref Draw->Font;
		tabsz:	int;
		tabwid:	int;		# tabsz * spwid
		spwid:	int;		# space width (min width for tabs)
		r:	Draw->Rect;
		i:	ref Draw->Image;
		lni:	ref Draw->Image;	# line buffer to draw boxes (double buffering).
		tick:	ref Draw->Image;
		sz:	Draw->Point;	# width, height in runes (aprox.)
		sbeof:	int;		# start of begin/end of file mark (x)
		ebeof:	int;		# end of mark (x)
		debug:	int;

		# primary interface
		new:	fn(r: Draw->Rect, i: ref Draw->Image,
			f: ref Draw->Font, cols: array of ref Draw->Image, beof: int): ref Frame;
		init:	fn(fr: self ref Frame, blks: ref Tblks->Tblk, pos: int);
		ins:	fn(fr: self ref Frame, pos: int, nr: int): int;
		del:	fn(fr: self ref Frame, pos: int, nr: int);
		sel:	fn(fr: self ref Frame, ss: int, se: int);
		resize:	fn(fr: self ref Frame, r: Draw->Rect, i: ref Draw->Image): int;
		pt2pos:	fn(fr: self ref Frame, pt: Draw->Point): int;
		pos2pt:	fn(fr: self ref Frame, pos: int): Draw->Point;
		scroll:	fn(fr: self ref Frame, nlines: int);

		# auxiliary tools
		move:	fn(fr: self ref Frame, at: Draw->Point);
		redraw:	fn(fr: self ref Frame, force: int);

		# implementation
		fill:	fn(fr: self ref Frame);
		mktick:	fn(fr: self ref Frame);
		seek:	fn(fr: self ref Frame, pos: int): (int, int);
		findnl:	fn(fr: self ref Frame, bi: int): int;
		addboxes:fn(fr: self ref Frame, bi: int, boxes: array of ref Tbox, renum: int);
		delboxes:	fn(fr: self ref Frame, bi: int, nb: int, renum: int);
		splitbox:	fn(fr: self ref Frame, bi: int, ri: int);
		fixselins:	fn(fr: self ref Frame, pos: int, nr: int);
		fixseldel:	fn(fr: self ref Frame, pos: int, nr: int);
		fmt:	fn(fr: self ref Frame, bi: int): int;
		placebox:	fn(fr: self ref Frame, bi: int);
		combinebox:fn(fr: self ref Frame, bi: int): int;
		wrapbox:	fn(fr: self ref Frame, bi: int): int;
		sizebox:	fn(fr: self ref Frame, bi: int);
		drawbox:	fn(fr: self ref Frame, bi: int);
		drawtick:	fn(fr: self ref Frame, i: ref Draw->Image, pt: Draw->Point);
		draw:	fn(fr: self ref Frame, bi: int, be:int, force: int);
		boxtext:	fn(fr: self ref Frame, bi: int): string;
		chk:	fn(fr: self ref Frame);
		dump:	fn(fr: self ref Frame);
		panic:	fn(fr: self ref Frame, s: string);
	};

	init:	fn(d: Livedat, b: Tblks, dbg: int);
};
