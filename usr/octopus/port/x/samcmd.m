Samcmd: module {

	PATH: con "/dis/o/x/samcmd.dis";

	init : fn(d: Oxdat);

	Inactive, Inserting, Collecting: con iota;
	editing:	int;


	cmdexec: fn(a0: ref Oxedit->Edit, a1: ref Sam->Cmd): int;
	resetxec: fn();
	cmdaddress: fn(ap: ref Sam->Addr, a: Sam->Address, sign: int): Sam->Address;
	edittext: fn(f: ref Oxedit->Edit, q: int, r: string): string;

	readloader: fn(f: ref Oxedit->Edit, q0: int, r: string): int;
};