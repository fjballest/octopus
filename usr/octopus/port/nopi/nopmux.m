Nopmux: module {
	PATH: con "/dis/o/nopi/nopmux.dis";

	All: con ~0;	# get retrieves everything if cnt is ~0

	init:	fn(s: Sys, e: Error, n: Nop, fd: ref Sys->FD);
	get:	fn(path: string, ofd, mode, cnt: int, off: big):
			(int, ref Sys->Dir, array of byte, string);
	put:	fn(path:string, ofd, mode: int, d: ref Sys->Dir,
			a: array of byte, off: big, async: int):
			(int, ref Sys->Dir, string);
	clunk:	fn(ofd: int);
	remove:	fn(path: string, async: int): string;
};
