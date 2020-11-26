# Translation from styx to op for ofs.
# Either use the Cache or Op to operate on remote files.
# See the comment in stop.b for a description.

Stop: module {
	PATH: con "/dis/o/ofs/stop.dis";

	MAXNMSGS:	con 4;
	MAXCACHED:	con MAXNMSGS * Op->MAXDATA;


	Creq: adt {
		tag:	int;	# styx (client's) tag
		qid:	big;	# qid for file we are asking about
		pick {
		Dump or Remove or Stat or Sync =>
		Validate  =>
			path:	string;
		Walk1 =>
			name:	string;
		Readdir or Pread =>
			cnt:	int;
			off:	big;
		Pwrite =>
			data:	array of byte;
			off:	big;
		Wstat or Create =>
			d:	ref Sys->Dir;
		Flush =>
			oldtag:	int;
		}

		text:	fn(r: self ref Creq): string;
	};

	Crep: adt {
		err : string;		# for failed requests
		pick {
		Validate or Create or Walk1 or Stat or Wstat =>
			d: ref Sys->Dir;	# copy. no races.
		Remove or Sync or Op or Dump or Flush=>
		Readdir =>
			sons: list of Sys->Dir;
		Pread =>
			data: array of byte;
		Pwrite =>
			count: int;
		}

		text: fn(r: self ref Crep): string;
	};

	# styx for unpackdir
	init:		fn(s: Styx, m: Opmux, cdir: string, lag: int) : string;
	validate:	fn(tag: int, qid: big, path: string): (ref sys->Dir, string);
	create:	fn(tag: int, qid: big, d: ref Sys->Dir): (ref Sys->Dir, string);
	remove:	fn(tag: int, qid: big) : string;
	walk1:	fn(tag: int, qid: big, elem: string): (ref Sys->Dir, string);
	readdir:	fn(tag: int, qid: big, cnt, off: int): (list of Sys->Dir, string);
	pread:	fn(tag: int, qid: big, cnt: int, off: big): (array of byte, string);
	pwrite:	fn(tag: int, qid: big, data: array of byte, off: big) : (int, string);
	stat:		fn(tag: int, qid: big): (ref Sys->Dir, string);
	wstat:	fn(tag: int, qid: big, d: ref Sys->Dir): (ref Sys->Dir, string);
	sync:	fn(tag: int, qid: big): string;
	flush:	fn(tag: int, oldtag: int) : string;
	term:		fn();
	dump:	fn();
	debug:	int;
};
