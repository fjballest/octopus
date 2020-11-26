Oxdat: module {
	PATH: con "/dis/o/x/xdat.dis";

	Mods: adt {
		sys: Sys;
		err: Error;
		daytime: Daytime;
		env: Env;
		io: Io;
		names: Names;
		oxedit: Oxedit;
		oxex: Oxex;
		oxload: Oxload;
		panels: Panels;
		readdir: Readdir;
		regx: Regx;
		sam: Sam;
		samcmd: Samcmd;
		samlog: Samlog;
		sh: Sh;
		str: String;
		tblks: Tblks;
		workdir: Workdir;
		os: Os;
	};

	loadmods:	fn(s: Sys, e: Error);

	mods: Mods;
};
