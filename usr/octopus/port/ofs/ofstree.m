# Tree maintenance for ofs
# and disk cache

Ofstree: module {
	PATH: con "/dis/o/ofs/ofstree.dis";

	Cfile: adt {
		oprdfd:	int;					# Op fd in Tgets.
		opwrfd:	int;					# Op fd in Tputs.
		fsfd:		ref Sys->FD;			# on disk cache fd
		d:		ref Sys->Dir;
		data:	array of byte;				# null if not read, array[0] of byte when empty
		dirreaded:	int;					# directory was read (but might be empty!)
		dirtyd:	int;
		created:	int;
		busy:	int;					# we're speaking Op, must wait.
		oldname:	string;				# for rename in wstats
		parentqid:	big;
		serverqid:	Sys->Qid;			# coherency
		time: int;						# when last known to be coherent
		child:	cyclic ref Cfile;
		sibling:	cyclic ref Cfile;
		hash:	cyclic ref Cfile;

		create:	fn(parent: ref Cfile, d: ref Sys->Dir): ref Cfile;
		find:		fn(q: big): ref Cfile;
		updatedirdata: fn(f: self ref Cfile, data: array of byte);
		getpath:	fn(f: self ref Cfile): string;
		walk:		fn(fh: self ref Cfile, name: string): ref Cfile;
		walkorcreate:		fn(fh: self ref Cfile, name: string, d: ref Dir): (ref Cfile, int);
		children:	fn(f: self ref Cfile, cnt, off: int) : list of Sys->Dir;
		wstat:	fn(fh : self ref Cfile, d: ref Sys->Dir): string;
		pwrite:	fn(fh: self ref Cfile, data: array of byte, off: big): int;
		pread:	fn(fh : self ref Cfile, cnt: int, off: big): array of byte;
		remove:	fn(f: self ref Cfile): string;
		dump:	fn(f: self ref Cfile, t: int, pref: string);
		text:		fn(fh: self ref Cfile): string;
	};

	init:	fn(msys: Sys, mstr: String, mstyx: Styx, merr: Error, n: Names, dir: string): string;
	debug: int;
};
