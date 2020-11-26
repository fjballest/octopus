# Cached file information.

Tree: module {
	PATH: con "/dis/o/nopi/tree.dis";

	# file flags (first three bits are the lease)
	Clease:	con 3;		# OREAD/OWRITE/ONONE
	Corphan,			# not yet attached to the tree
	Ccreated,			# must be created/truncated on server
	Cdata,			# file/dir data was read
	Cdirtyd,			# stat must be pushed
	Cdead,			# file being removed (safety check)
	Cbusy:	con 4<<iota;	# operation on progress, must wait.


	Cfile: adt {
		fd:	ref Sys->FD;	# used to update the cache
		path:	string;
		d:	ref Sys->Dir;
		nawrites:	int;	# nb. of async bytes put
		parentqid:	big;
		child:	cyclic ref Cfile;
		sibling:	cyclic ref Cfile;

		hash:	cyclic ref Cfile;

		flags:	int;
		oldname:	string;		# for rename in wstats
		ltime: int;			# time of last lease

		orphan:	fn(path: string): ref Cfile;
		find:	fn(q: big): ref Cfile;
		adopt:	fn(f: self ref Cfile);
		dirwrite:	fn(f: self ref Cfile, data: array of byte);
		walk:	fn(fh: self ref Cfile, name: string): ref Cfile;
		children:	fn(f: self ref Cfile) : array of ref Sys->Dir;
		wstat:	fn(fh : self ref Cfile, d: ref Sys->Dir): string;
		write:	fn(fh: self ref Cfile, data: array of byte, off: big): int;
		read:	fn(fh : self ref Cfile, data: array of byte, off: big): int;
		remove:	fn(f: self ref Cfile): string;
		dump:	fn(f: self ref Cfile, t: int, pref: string);
		text:	fn(fh: self ref Cfile): string;
	};

	init:	fn(s: Sys, str: String, e: Error, n: Names, r: Readdir);
	mk:	fn(root: big, cdir: string): string;
	debug:	int;
};
