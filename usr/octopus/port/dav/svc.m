Svc: module {
	PATH: con "/dis/o/dav/svc.dis";

	init:	fn(d: Dat, fsdir: string, rdonly: int);
	run:	fn(m: ref Msgs->Msg): ref Msgs->Msg;

	debug:	int;
};
