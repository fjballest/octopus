Cache: module {
	PATH: con "/dis/o/nopi/cache.dis";

	Lmax:	con 3600;	# max nb of seconds for a lease.

	Crep: adt {
		err: string;
		cf: ref Tree->Cfile;
		pick {
		Children =>
			dirs: array of ref Sys->Dir;
		Parent or Stat or Walk or Open or Create =>
			dir: ref Sys->Dir;
		Read =>
			data: array of byte;
		Write =>
			cnt: int;
		Clunk or Remove or Error or Inval  or Wstat =>
		}
	};

	Creq: adt {
		q: big;
		rc: chan of ref Crep;
		pick {
		Children or Parent or Stat or Remove or Done =>
		Open =>
			fid: ref Ssrv->Fid;
		Walk =>
			els: array of string;
			fetch: int;
		Create =>
			fid: ref Ssrv->Fid;
			dir: ref Sys->Dir;
		Read =>
			fid: ref Ssrv->Fid;
			cnt: int;
			off: big;
		Write =>
			fid: ref Ssrv->Fid;
			data: array of byte;
			off: big;
		Wstat =>
			dir: ref Sys->Dir;
		Clunk =>
			fid: ref Ssrv->Fid;
		Inval =>
			path: array of string;
		Update =>
			dir: ref Sys->Dir;
			data: array of byte;
			off: big;
			sts: string;
			lease: int;
		}
	};

	init:	fn(s: Sys, e: Err, n: Nop, b: Blks, fd: ref Sys->FD, cdir: string);

	attach:	fn(fd: ref Sys->FD, cdir: string): string;
	root:	fn(): big;
	children:	fn(q: big): array of ref Sys->Dir;
	parent:	fn(q: big): ref Sys->Dir;
	stat:	fn(q: big): (ref Sys->Dir, string);
	walk:	fn(q: big, els: array of string, fetch: int): (ref Sys->Dir, string);
	open:	fn(q: big, fid: ref Ssrv->Fid, mode: int): (ref Sys->Dir, string);
	create:	fn(q: big, fid: ref Ssrv->Fid, d: ref Sys->Dir, mode: int):
			(ref Sys->Dir, string);
	read:	fn(q: big, fid: ref Ssrv->Fid, cnt: int, off: big): (array of byte, string);
	write:	fn(q: big, fid: ref Ssrv->Fid, a: array of byte, off: big): (int, string);
	clunk:	fn(q: big, fid: ref Ssrv->Fid);
	remove:	fn(q: big): string;
	wstat:	fn(q: big, d: ref Sys->Dir): string;
	debug:	int;
};
