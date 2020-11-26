Livedat: module {
	PATH: con "/dis/o/live/livedat.dis";

	# modules and globals
	# (auxiliary modules used for particular panels
	#  are not shared in this adt).

	Mods: adt {
		# loaded first, and init'd
		sys: Sys;
		math: Math;
		arg: Arg;
		readdir: Readdir;
		err: Error;
		io: Io;
		str: String;
		wmcli: Wmclient;
		draw: Draw;
		random: Random;
		names: Names;
		menus: Menus;
		layout: Layout;
		merop: Merop;
		blks: Blks;

		# then generic panel support
		wpanel:	Wpanel;
		wtree:	Wtree;
		gui: 		Gui;
	};

	loads:	fn();
	debug:	array of int;
	win: 		ref Wmclient->Window;
	tree:		ref Wtree->Tree;
	mods:	ref Mods;

};
