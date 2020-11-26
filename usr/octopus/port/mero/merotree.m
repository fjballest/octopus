# The glue merging panels and files.
# This provides panel ops related to their file trees, and
# adjusts the file tree according to the panels.
# Not a real module.

Merotree: module {

	PATH: con "/dis/o/mero/merotree.dis";

	init:		fn(d: Dat): chan of ref Styxservers->Navop;
	pwalk:		fn(s: string): (ref Panels->Panel, ref Panels->Repl);
	pcreate:		fn(dp: ref Panels->Panel, dr: ref Panels->Repl,
				name: string): ref Panels->Panel;
	premove:	fn(p: ref Panels->Panel, rr: ref Panels->Repl);
	pchanged:	fn(p: ref Panels->Panel);
	pheldupd:	fn(p: ref Panels->Panel, vers: int);
	pchanges:	fn(p: ref Panels->Panel, r: ref Panels->Repl,
			vers: int): (list of ref Merop->Msg, int);
	moveto:		fn(p: ref Panels->Panel, r: ref Panels->Repl,
				path: string, pos: int): string;
	copyto:		fn(p: ref Panels->Panel, r: ref Panels->Repl,
				path: string, pos: int): string;
	chpos:		fn(p: ref Panels->Panel, r: ref Panels->Repl, pos: int);
	mkcol:		fn(p: ref Panels->Panel, r: ref Panels->Repl);
	mktree:		fn();
	dump:		fn();
};
