Oxload: module {
	PATH: con "/dis/o/x/load.dis";

	init:	fn(d: Oxdat);
	loadui:	fn(path: string): chan of ref Panels->Pev;
};

