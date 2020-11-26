Tundo: module {
	PATH:	con "/dis/o/live/tundo.dis";

	Edit: adt {
		synced:	int;	# done in o/mero
		closed:	int;	# edit completed (synced or undone)
		bundle:	int;	# edits with same bundle are a single one
		pos:	int;	# where to insert/delete
		s:	string;	# text inserted/deleted

		name:	fn(edit: self ref Edit): string;
		text:	fn(edit: self ref Edit): string;
		pick {
		Ins =>
		Del =>
		}
	};

	Edits: adt {
		e:	array of ref Edit;	# edit operations
		pos:	int;		# where to put next edit in e
		cpos:	int;		# pos in e for a clean edit
		gen:	int;		# generator for Edit.bundle
		new:	fn(): ref Edits;
		ins:	fn(edits: self ref Edits, s: string, pos: int): int;
		del:	fn(edits: self ref Edits, s: string, pos: int): int;
		sync:	fn(edits: self ref Edits): list of ref Edit;
		synced:	fn(edits: self ref Edits);
		undo:	fn(edits: self ref Edits): list of ref Edit;
		redo:	fn(edits: self ref Edits): list of ref Edit;
		mkpos:	fn(edits: self ref Edits): int;
		dump:	fn(edits: self ref Edits);
	};

	init:	fn(sysm: Sys, e: Error, l: Lists, t: Tblks, dbg: int);
	dtxt:	fn(s: string): string;
};
