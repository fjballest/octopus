Browsercmd: module {
	debug:		int;
	PATH:		con "/dis/o/MacOSX/browsercmd.dis";
	putbookmarks:	fn(bm: string): int;
	getbookmarks:	fn():string ;
	puthistory:	fn(bm: string): int;
	gethistory:	fn():string;
	getopen:		fn():string;
	openurls:		fn(urls: string): int;
	closebrowser:	fn(): int;
	startbrowser:	fn(): int;
	restartbrowser:	fn(): int;
	getstatus:		fn(): string;
	init:			fn(): string;
};
