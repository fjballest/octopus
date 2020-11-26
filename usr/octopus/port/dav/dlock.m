Dlock: module {
	PATH: con "/dis/o/dav/dlock.dis";

	Lfree, Lread, Lwrite, Lrenew: con iota;

	Lease:	con 3600;

	init:	fn(d: Dat);
	locked:	fn(fname: string, depth: int, excl: list of string): int;
	canlock:	fn(fname, owner: string, depth, kind: int): string;
	unlock:	fn(lck: string);
	rmlocks:	fn(fname: string);
	renew:	fn(lck: string): (string, string);

	debug:	int;
};