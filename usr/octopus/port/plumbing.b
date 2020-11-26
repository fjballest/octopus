implement Plumbing;
include "sys.m";
	sys: Sys;
	fprint, sprint: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "sh.m";
	sh: Sh;
	Context: import sh;
include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

Plumbing: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

verbose := 0;

plumbing(rc: chan of string, dctx: ref Draw->Context, port: string, argv: list of string)
{
	sys->pctl(Sys->FORKFD, nil);
	ctxt := Context.new(dctx);

	if(plumbmsg->init(0, port, 512) < 0){
		rc <-= sprint("plumbinit: %r");
		raise "fail: plumb";
	}
	# make sure the shell command is parsed only once.
	cmd := sh->stringlist2list(argv);
	if((hd argv) != nil && (hd argv)[0] == '{'){
		(c, e) := sh->parse(hd argv);
		if(c == nil){
			rc <-= e;
			raise "fail: " + e;
		}
		cmd = ref Sh->Listnode(c, hd argv) :: tl cmd;
	}
	rc <-= nil;
	for(;;) {
		m := Msg.recv();
		if(m == nil)
			break;
		if(m.kind != "text"){
			fprint(stderr, "plumbing: non-text message\n");
			continue;
		}
		val := list of {ref Sh->Listnode(nil, string m.data)};
		if(verbose)
			fprint(stderr, "plumbing: %s: %s\n", port, string m.data);
		ctxt.set("msg", val);
		ctxt.run(cmd, 0);
		m = nil; val = nil;
	}
	error("plumbing: can't read plumb port");
}

init(dctx: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	sh = checkload(load Sh Sh->PATH, Sh->PATH);
	plumbmsg = checkload(load Plumbmsg Plumbmsg->PATH, Plumbmsg->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(argv);
	arg->setusage("plumbing [-v] port cmd [arg...]");
	while((opt := arg->opt()) != 0) {
		case opt {
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(len argv < 2)
		arg->usage();
	c := chan of string;
	spawn plumbing(c, dctx, hd argv, tl argv);
	e := <- c;
	if(e != nil)
		error(e);
}

