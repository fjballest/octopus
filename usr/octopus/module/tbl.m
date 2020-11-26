Tbl: module {
	PATH: con "/dis/o/tbl.dis";

	# Taken from styxpersist.b

	Table: adt[T] {
		items:	array of list of (int, T);
		nilval:	T;
	
		new: fn(nslots: int, nilval: T): ref Table[T];
		add:	fn(t: self ref Table, id: int, x: T): int;
		del:	fn(t: self ref Table, id: int): T;
		find:	fn(t: self ref Table, id: int): T;
	};
};
