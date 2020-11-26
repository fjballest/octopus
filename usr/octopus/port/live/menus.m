Menus: module {
	PATH:	con "/dis/o/live/menus.dis";

	Opt:	adt {
		name:	string;
		φ:		real;				# angle to center
		si:		ref Draw->Image;	# image when set
		ci:		ref Draw->Image;	# image when clear
		pt:		Draw->Point;		# opt. center pos, relative to menu center
		sr:		Draw->Rect;		# area used in screen, for draw
	};

	Menu: adt {
		opts:		array of  Opt;
		nsects:		int;					# number of sectors
		∆φ:		real;					# angle for each opt.
		r:		Draw->Rect;				# for menu image
		sr:		Draw->Rect;				# used in screen
		saved:	ref Draw->Image;			# backing store

		last:		int;
		new:		fn(opts: array of string): ref Menu;
		run:		fn(mn: self ref Menu, m: ref Gui->Cpointer, mc: chan of ref Gui->Cpointer): string;

		# internal use
		mk:		fn(mn: self ref Menu);
		draw:		fn(mn: self ref Menu, pt: Draw->Point, set: int, first: int);
		optat:		fn(mn: self ref Menu, pt: Draw->Point): int;
		mouse:	fn(mn: self ref Menu, pt: Draw->Point,
					mp: ref Gui->Cpointer, mc: chan of ref Gui->Cpointer): string;
	};

	init:		fn(d: Livedat);

};
