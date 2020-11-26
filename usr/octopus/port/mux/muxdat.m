#
# Multiplexed fs fids and qids handling, for octopus mux.
#
Muxdat: module {
	PATH: con "/dis/o/muxdat.dis";

	Qroot :	con Qid(big 0, 0, QTDIR);
	NOQID:	con big ~0;
	Empty:	con "/mnt/empty";
	
	Fid: adt {
		fid:		int;			# fid known by client
		fd:		ref FD;		# for real file, while open.
		broken:	int;			# true for broken fids
		omode:	int;
		qid:		Qid;			# qid reported to client
		path:		string;
	};

	init:	fn(s: Sys, e: Error, n: Names, args: list of string);
	renametree:	fn(path:string, nname: string);
	addqid:		fn(path:string): big;
	getqid:		fn(path:string): big;
	delqid:		fn(path:string);
	fixqid:		fn(path:string, uqid: Qid): Qid;
	addfid:		fn(fid: ref Fid): int;
	delfid:		fn(fid: ref Fid);
	getfid:		fn(fid: int): ref Fid;

	bindrootdir:	fn();
	rebind:		fn();
	maybebroken:	fn(estr: string);

	rootdir:	string;
	debug:	int;
	qgen:	int;
	brokenfs: int;

};
