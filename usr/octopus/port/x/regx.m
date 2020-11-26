Regx : module {
	PATH : con "/dis/o/x/regx.dis";

	NRange : con 10;
	Range : adt {
		q0 : int;
		q1 : int;
	};

	Rangeset : type array of Range;
	Infinity : con 16r7fffffff; 	# huge value for regexp address

	init : fn(d: Oxdat);

	rxinit : fn();
	rxcompile: fn(r : string) : int;
	rxexecute: fn(t : ref Tblks->Tblk, r: string, startp : int, eof : int) : (int, Rangeset);
	rxbexecute: fn(t : ref Tblks->Tblk, startp : int) : (int, Rangeset);
	isaddrc : fn(r : int) : int;
	isregexc : fn(r : int) : int;
	address : fn(t : ref Tblks->Tblk, lim, ar : Range, a0 : ref Tblks->Tblk,
			a1 : string, q0, q1, eval : int) : (int, int, Range);
};