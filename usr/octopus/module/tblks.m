Tblks: module {
	PATH:	con "/dis/o/tblks.dis";

	Maxline:	con 250;		# after so many runes, we consider it a text line.

	Str:	adt {
		s: string;
		findr:	fn(s: self ref Str, pos: int, c: int, lim: int): int;
		find:	fn(s: self ref Str, pos: int, c: int, lim: int): int;
	};

	Tblk:	adt {
		b:	array of ref Str;
		new:	fn(s: string): ref Tblk;
		pack:	fn(blks: self ref Tblk): ref Str;
		ins:	fn(blks: self ref Tblk, s: string, pos: int);
		del:	fn(blks: self ref Tblk, n: int, pos: int): string;
		seek:	fn(blks: self ref Tblk, pos: int): (int, int);	# (index in b, off in Str)
		blen:	fn(blks: self ref Tblk): int;
		getc:	fn(blks: self ref Tblk, pos: int): int;
		gets:	fn(blks: self ref Tblk, pos: int, nr: int): string;
		dump:	fn(blks: self ref Tblk);
	};

	init:		fn(sysm: Sys, strm: String, e: Error, dbg: int);
	fixpos:		fn(pos: int, n: int): int;
	fixposins:		fn(pos: int, inspos: int, n: int): int;
	fixposdel:		fn(pos: int, delpos: int, n: int): int;
	strstr:		fn(s1, s2: string): int;
	strchr:		fn(s : string, c : int) : int;
	dtxt:		fn(s: string): string;
};
