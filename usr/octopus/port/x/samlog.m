Samlog: module {

	PATH: con "/dis/o/x/samlog.dis";

	init :			fn(d: Oxdat);
	eloginsert:	fn(a0: ref Oxedit->Edit, a1: int, a2: string);
	elogdelete:	fn(a0: ref Oxedit->Edit, a1: int, a2: int);
	elogreplace:	fn(a0: ref Oxedit->Edit, a1: int, a2: int, a3: string);
	elogapply:		fn(a0: ref Oxedit->Edit): int;
	elogterm:		fn(a0: ref Oxedit->Edit);

};
