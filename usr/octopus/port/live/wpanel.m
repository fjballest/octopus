# Generic panel support
Wpanel: module {

	PATH: con "/dis/o/live/wpanel.dis";

	Qatom, Qrow, Qcol: con iota;	# for Panel.rowcol

	Phide,	# user does not want to show this panel
	Playout,	# layout container. reclaims space
	Pedit,	# kbd/mouse editing allowed
	Ptag,	# show the tag, accept mouse commands for tag

	Pmore,	# has hidden panels inside (containers only)
	Pdirties,	# has dirty panels inside (containers only)
	Pdirty,	# unsaved changes (for text panels, or atoms)
	Pline,	# at most one line (for text panels)

	Ptbl,	# tabulate content (for text panels)
	Pnosel,	# do not update /dev/sel for this (text) panel
	Predraw,	# must redraw
	Pdead,	# it's gone

	Pbusy,	# panel locked: being updated or doing another op.
	Pshown,	# panel shown in screen (used for redrawing tags)
	Pinsist,	# insisting on close request
	Pscroll,	# text should scroll on updates

	Ptemp,	# panel should never be considered dirty
	Pfocus,	# panel refers to /mnt/snarf/sel
	Pjump,	# make the mouse jump to it on next redraw
	Pmax:	con int (1<<iota);

	All:	con 16666;	# bigger than any screen width/height

	Panel: adt {
		parent:	cyclic ref Panel;
		child:	cyclic array of ref Panel; # Used for containers
		rowcol:	int;		# Qatom, Qrow, Qcol.
		order:	list of string;		# list of children names, for order
		nshown:	int;		# nb. of children shown (for More)
		flags:	int;		# too many, I know.
		name:	string;		# basename(path)
		path:	string;		# absolute path to panel dir
		depth:	int;		# in tree

		vers:	int;		# last version seen from o/mero

		rect:	Draw->Rect;		# rectangle used on the screen.
		orect:	Draw->Rect;
		size:	Draw->Point;	# preferred size.
		minsz:	Draw->Point;	# min. desired size.
		maxsz:	Draw->Point;	# size wanted at most.
		resized:	int;		# sized adjusted by the user.
		font:	ref Draw->Font;	# only used by text panels
					# but kept here for the future
		impl:	Pimpl;		# adt implementing the panel.
		implid:	int;		# index on impl. array.

		new:	fn(n: string, fp: ref Panel): ref Panel;
		fsctl:	fn(p: self ref Panel, s: string, async: int): int;
		fsctls:	fn(p: self ref Panel, l: list of string, async: int): int;
		fsdata:	fn(p: self ref Panel, d: array of byte, async: int): int;
		text:	fn(p: self ref Panel): string;

		# functions delegated to the panel implementor

		# Called from the tree coordinator:
		init:	fn(p: self ref Panel);
		term:	fn(p: self ref Panel);
		ctl:	fn(p: self ref Panel, s: string);
		update:	fn(p: self ref Panel, d: array of byte);
		draw:	fn(p: self ref Panel);

		# Called from other procs:
		event:	fn(p: self ref Panel, s: string);	# ins, del
		mouse:	fn(p: self ref Panel, m: ref Gui->Cpointer,
				cm: chan of ref Gui->Cpointer);
		kbd:	fn(p: self ref Panel, r: int);
	};


	init:		fn(d: Livedat, dir: string,
				c: chan of (ref Panel, list of string, chan of int),
				dc: chan of (ref Panel, array of byte, chan of int));
	intag:		fn(p: ref Panel, xy: Draw->Point): int;

	nth:		fn(l: list of string, n: int): string;
};

Pimpl: module {
	prefixes:	list of string;

	pinit:	fn(p: ref Wpanel->Panel);
	pterm:	fn(p: ref Wpanel->Panel);
	pctl:	fn(p: ref Wpanel->Panel, s: string);
	pupdate:	fn(p: ref Wpanel->Panel, d: array of byte);
	pevent:	fn(p: ref Wpanel->Panel, s: string);	# ins, del
	pdraw:	fn(p: ref Wpanel->Panel);
	pmouse:	fn(p: ref Wpanel->Panel, m: ref Gui->Cpointer,
			cm: chan of ref Gui->Cpointer);
	pkbd:	fn(p: ref Wpanel->Panel, r: int);

	init:	fn(d: Livedat) : string;
};
