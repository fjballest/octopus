# convenience library for o/mero applications

Panels: module {
	PATH: con "/dis/o/panel.dis";

	Elook:	con "look";
	Eexec:	con "exec";
	Eclose:	con "close";
	Eclean:	con "clean";
	Edirty:	con "dirty";
	Eintr:	con "interrupt";
	Eclick:	con "click";
	Ekeys:	con "keys";
	Efocus:	con "focus";

	Pev: adt {
		id:	int;
		path:	string;
		ev:	string;
		arg:	string;
	};

	Panel: adt {
		id:	int;
		name: 	string;
		path:	string;
		gcfd:	ref Sys->FD;
		rpid:	int;
		init:	fn(name: string): ref Panel;
		evc:	fn(p: self ref Panel): chan of ref Pev; #(path id ev ...)
		new:	fn(p: self ref Panel, name: string, id: int): ref Panel;
		newnamed:	fn(p: self ref Panel, name: string, id: int): ref Panel;
		ctl:	fn(p: self ref Panel, ctl: string): int;
		attrs:	fn(p: self ref Panel): ref Attrs;
		close:	fn(p: self ref Panel);
	};

	Attrs: adt {
		tag:	int;
		show:	int;
		col:	int;
		applid:	int;
		applpid:	int;
		clean:	int;
		font:	int;
		sel:	(int, int);
		mark:	int;
		scroll:	int;
		tab:	int;
		attrs:	list of list of string;	# list of other attrs
	};

	init:	fn();
	userscreen:	fn(): string;
	screens:	fn(): list of string;
	cols:	fn(scr: string): list of string;
	rows:	fn(scr: string): list of string;
	sel:	fn(): string;
	omero:	string;

};
