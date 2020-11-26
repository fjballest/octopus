Blks: module {

	PATH: con "/dis/o/blks.dis";

	Blk: adt {
		data:	array of byte;
		rp:	int;
		wp:	int;

		read:	fn(b: self ref Blk, fd: ref Sys->FD, max: int): int;
		blen:	fn(b: self ref Blk): int;
		grow:	fn(b: self ref Blk, n: int);
		put:	fn(b: self ref Blk, data: array of byte);
		get:	fn(b: self ref Blk, cnt: int): array of byte;
		dump:	fn(b: self ref Blk);
	};

	BIT8SZ:	con 1;
	BIT16SZ:	con 2;
	BIT32SZ:	con 4;
	BIT64SZ:	con 8;
	NODATA:	con int ~0;


	init:	fn();
	utflen:	fn(s: string): int;
	pstring:	fn(a: array of byte, o: int, s: string): int;
	gstring:	fn(a: array of byte, o: int): (string, int);
	p16:	fn(a: array of byte, o: int, v: int): int;
	g16:	fn(f: array of byte, i: int): int;
	p32:	fn(a: array of byte, o: int, v: int): int;
	g32:	fn(f: array of byte, i: int): int;
	p64:	fn(a: array of byte, o: int, v: big): int;
	g64:	fn(f: array of byte, i: int): big;
	dtxt:	fn(s: string): string;

	debug:	int;
};
