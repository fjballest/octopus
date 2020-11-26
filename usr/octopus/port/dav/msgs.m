Msgs: module {
	PATH: con "/dis/o/dav/msgs.dis";

	# status codes and default messages
	Cok:	con 200;
	Ccreated:	con 201;
	Cnone:	con 204;
	Cmulti:	con 207;
	Cbad:	con 400;
	Cnotfound:	con 404;
	Cnotallow:	con 405;
	Cperm:	con 407;
	Cprecond:	con 412;
	Clocked:	con 423;
	Csto:	con 507;

	Sok:	con "ok";
	Screated:	con "created";
	Snone:	con "no content";
	Smulti:	con "Multi-Status";
	Sbad:	con "bad request";
	Snotfound:	con "file does not exist";
	Snotallow:	con "method not allowed";
	Sperm:	con "forbidden";
	Sprecond:	con "precondition failed";
	Slocked:	con "resource is locked";
	Ssto:	con "insufficient storage";

	Hdr: adt {
		iobin:	ref Bufio->Iobuf;		# input buffer
		iobout:	ref Bufio->Iobuf;	# output buffer
		cdir:	string;		# line directory (debug)
		keep:	int;
		clen:	big;		# ignored for replies
		enc:	string;
		opts:	list of (string, string);	# key, val
		pick {
		Req =>
			method:	string;
			uri:	string;
			proto:	string;
		Rep =>
			proto:	string;
			code:	int;
			msg:	string;
		}

		parsereq:	fn(iobin, iobout: ref Bufio->Iobuf, cdir: string): ref Hdr;
		getopt:	fn(h: self ref Hdr, o: string): string;
		putopt:	fn(h: self ref Hdr, k,v: string);
		mkrep:	fn(h: self ref Hdr, c: int, msg: string): ref Hdr;
		dump:	fn(h: self ref Hdr, verb: int);	# 0: silent; 1: normal; 2: verbose

		# internal
		parseopt:	fn(h: self ref Hdr): int;
		lookopt:	fn(h: self ref Hdr);
	};

	Msg:	adt {
		hdr:	ref Hdr;
		body:	array of byte;
		getreq:	fn(iobin, iobout: ref Bufio->Iobuf, cdir: string): ref Msg;
		putrep:	fn(r: self ref Msg): int;
	};

	init:	fn(d: Dat);
	readall:	fn(iob: ref Iobuf): array of byte;
	debug: int;
};
