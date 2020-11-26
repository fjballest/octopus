# Connections to o/live
# event handling

Merocon: module {

	PATH: con "/dis/o/mero/merocon.dis";

	Event: adt {
		pid:	int;		# of appl
		p:	ref Panels->Panel;
		r:	ref Panels->Repl;
		m:	ref Merop->Msg;
	};
	
	Con: adt {
		fid:	int;
		vers:	int;
		top:	string;
		req:	ref Styx->Tmsg.Read;
		evs:	list of ref Event;
		rblk:	ref Blks->Blk;	# buffer for user reads
		wblk:	ref Blks->Blk;	# buffer for user writes

		new:	fn(fid: int): ref Con;
		lookup:	fn(fid: int): ref Con;
		close:	fn(c: self ref Con);
		read:	fn(c: self ref Con, m: ref Styx->Tmsg.Read);
		write:	fn(c: self ref Con, m: ref Styx->Tmsg.Write);
		ctl:	fn(c: self ref Con):
				(ref Panels->Panel, ref Panels->Repl, string, array of byte);
		flush:	fn(tag: int);
		text:	fn(c: self ref Con): string;
	};

	init:	fn(d: Dat);
	start:	fn(): int;
	hold:	fn(p: ref Panels->Panel);
	rlse:	fn(p: ref Panels->Panel);
	post:	fn(pid: int, p: ref Panels->Panel, r: ref Panels->Repl, ev: string);
	fsread:	fn(c: ref Con);
	dump:	fn();
};
