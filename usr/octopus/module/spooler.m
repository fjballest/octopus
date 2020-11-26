# file spooler interface
#
Spooler: module {

	Sfile: adt {
		fd:	ref Sys->FD;	# avail to be used by spooler
		path:	string;
		sval:	string;		# avail to be used by spooler

		start:		fn(path: string, endc: chan of string): (ref Sfile, string);
		stop: 	fn(file: self ref Sfile);
		status:	fn(file: self ref Sfile): string;
	};

	init:		fn(args: list of string);
	status:	fn(): string;
	debug:	int;
};
