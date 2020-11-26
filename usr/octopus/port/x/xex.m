Oxex: module {
	PATH: con "/dis/o/x/xex.dis";

	Xcmd: adt {
		tid:	int;	# tree id
		rpid:	int;	# reader proc pid
		pid:	int;	# proc pid
		cmd:	string;
		host:	int;	# true if to be run using /cmd
		file:	string;
		dir:	string;
		in:	ref FD;
		out:	ref FD;
		err:	ref FD;
		done:	int;
		new:	fn(cmd, file, dir: string, in, out: ref Sys->FD, tid, host: int): ref Xcmd;
		ftext:	fn(short: int):string;
	};

	init:	fn(d: Oxdat, upc: chan of int);
	deledit:	fn(ed: ref Oxedit->Edit);
	putedit:	fn(ed: ref Oxedit->Edit, s: string);
	findedit:	fn(ed: ref Oxedit->Edit, s: string): ref Oxedit->Edit;
	newedit:	fn(tr: ref Oxedit->Tree, path: string, msg: int, force: int): ref Oxedit->Edit;
	msg:	fn(tr: ref Oxedit->Tree, dir: string, s: string);
	fatal:	fn(s: string);

	# To provide fds for Xcmd.new when doing <>|
	pipein:	fn(buf: string): ref Sys->FD;
	pipeout:	fn(): (ref Sys->FD, chan of string);

	xcmds: list of ref Xcmd;
};
