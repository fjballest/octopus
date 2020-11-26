Opmux: module {
	PATH: con "/dis/o/opmux.dis";

	init:	fn(ofd: ref Sys->FD, op: Op, endc: chan of string);
	rpc:	fn(t: ref Op->Tmsg) : chan of ref Op->Rmsg;
	term: fn();
	dump: fn();

	recoverfn:	ref fn(): ref Sys->FD;
	debug: int;
};
