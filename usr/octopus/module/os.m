# support for host os commands
#
Os: module {
	PATH: con "/dis/o/os.dis";

	init:	fn();
	filename:	fn(name: string): string;

	run:	fn(cmd: string, dir: string): (string, string);

	Cmdio: adt {
		ifd:	ref Sys->FD;	# stdin
		ofd:	ref Sys->FD;	# stdout
		efd:	ref Sys->FD;	# stderr
		wfd:	ref Sys->FD;	# wait
		cfd:	ref Sys->FD;	# ctl
	};
	frun:	fn(cmd: string, dir: string): (ref Cmdio, string);
	emuhost:	string;
	emuroot:	string;
};
