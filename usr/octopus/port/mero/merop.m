# O/mero <-> O/live protocol support
Merop: module {
 
	PATH: con "/dis/o/mero/merop.dis";

	BIT8SZ:	con 1;
	BIT32SZ:	con 4;
	NODATA:	con int ~0;
	HDRSZ:	con BIT32SZ+BIT8SZ; # size[4] type[1]

	Tupdate,
	Tctl,
	Tmax:	con 1+iota;

	Msg: adt {
		path:	string;
		pick {
		Update =>
			vers:	int;
			ctls:	string;
			data:	array of byte;
			edits:	string;
		Ctl =>
			ctl:	string;
		}

		bread:		fn(b: ref Blks->Blk): ref Msg;
		unpack:		fn(a: array of byte): (int, ref Msg);
		pack:		fn(t: self ref Msg): array of byte;
		packedsize:	fn(t: self ref Msg): int;
		text:		fn(t: self ref Msg): string;
		mtype: 		fn(t: self ref Msg): int;
		name:		fn(t: self ref Msg): string;
	};

	init:	fn(s: Sys, b: Blks);
	debug:	int;
};
