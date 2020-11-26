#
# snoop o/x events to open files o/x does not
# know how to open (urls, pdfs, etc.).
# use $home/lib/open as the default config file.
# this file contains lines
#	regexp	cmd
# and the first regexp matching the event leads to execution of cmd
# on a shell environment.
#
implement Open;
include "sys.m";
	sys: Sys;
	sleep, sprint, create, pctl, read, open, FD, OWRITE, NEWPGRP,
	ORDWR, ORCLOSE, fprint, OTRUNC, OREAD, write: import sys;
include "draw.m";
	Point: import Draw;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "string.m";
	str: String;
	in, prefix, tolower, drop, splitl: import str;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "regex.m";
	regex: Regex;
	Re: import regex;
include "env.m";
	env: Env;
	getenv: import env;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "sh.m";
	sh: Sh;
	system: import sh;

Open: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;
xctx: ref Draw->Context;

Oexp: adt{
	exptext:	string;
	exp:	Re;
	cmd:	string;
};

openevent(cmd: string, what: string)
{
	if(debug)
		fprint(stderr, "openevent: [%s] [%s]\n", cmd, what);
	system(xctx, cmd);
}

expand(c, s: string, match: array of (int, int)): string
{
	ns := "";
	for(i := 0; i < len c; i++){
		if(c[i] != '\\' || len c - i == 1 || !str->in(c[i+1], "0-9"))
			ns[len ns] = c[i];
		else {
			digit := " ";
			digit[0] = c[i+1];
			i++;
			(nb, es) := str->toint(digit, 10);
			if(es == nil && nb >= 0 && nb < len match)
				ns += s[match[nb].t0:match[nb].t1];
		}
	}
	return ns;
}

event(s: string, d: string, ocfg: list of ref Oexp): list of ref Oexp
{
	if(debug > 1)
		fprint(stderr, "open: [%s] at [%s]\n", s, d);
	for(cfg := ocfg; cfg != nil; cfg = tl cfg){
		cent := hd cfg;
		match := regex->execute(cent.exp, tolower(s));
		if(len match != 0){
			openevent(expand(cent.cmd, s, match), s);
			break;
		}
	}
	if(s == "!reload"){
		if(debug)
			fprint(stderr, "o/open: re-reading configuration\n");
		return parseconf();
	} else
		return ocfg;
}

parseconf(): list of ref Oexp
{
	fname := getenv("home") + "/lib/open";
	cin := bufio->open(fname, OREAD);
	if(cin == nil)
		error(sprint("o/open: parseconf: %r"));
	l: list of ref Oexp;
	while((ln := cin.gets('\n')) != nil){
		(ln, nil) = splitl(ln, "#");
		while(len ln > 0)
			if(str->in(ln[len ln-1], "\n \t"))
				ln = ln[:len ln-1];
			else
				break;
		if(len ln == 0)
			continue;
		(exp, cmd) := splitl(ln, "\t");
		if(len cmd > 0)
			cmd = cmd[1:];	# drop \t
		if(len exp == 0 || len cmd == 0)
			fprint(stderr, "o/open: bad config line [%s]\n", ln);
		else {
			if(debug > 1)
				fprint(stderr, "o/open: config: %s %s\n", exp, cmd);
			(re, rerr) := regex->compile(exp, 1);
			if(rerr != nil)
				fprint(stderr, "o/open: regexp [%s]: %s\n", exp, rerr);
			else
				l = ref Oexp(exp, re, cmd)::l;
		}
	}
	cin.close();
	if(len l == 0)
		error(sprint("o/open: no expressions in config file"));
	return l;
}

ereader(rc: chan of int, cfg: list of ref Oexp)
{
	if(debug)
		fprint(stderr, "echo kill>/prog/%d/ctl\n", pctl(0, nil));
	fname := sprint("/mnt/ports/open.%d", pctl(0, nil));
	fd := create(fname, ORDWR|ORCLOSE, 8r664);
	if(fd == nil){
		fprint(stderr, "ports: %r");
		rc <-= -1;
		exit;
	}
	rc <-= 0;
	expr := array of byte "^exec: Open .*";
	write(fd, expr, len expr);
	buf := array[1024] of byte;	# enough for events of interest
	for(;;){
		nr := read(fd, buf, len buf);
		if(nr <= 0)
			break;
		s := string buf[0:nr];
		l := len "exec: Open ";
		if(len s > l && s[0:l] == "exec: Open "){
			s = drop(s[l:], " \t");
			(s, nil) = splitl(s, "\n");
			(e, dir) := splitl(s, "#");
			cfg = event(e, dir, cfg);
		}
	}
	if(debug)
		fprint(stderr, "o/open: exiting\n");
}

init(ctx: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	xctx = ctx;
	bufio = checkload(load Bufio Bufio->PATH, Bufio->PATH);
	str = checkload(load String String->PATH, String->PATH);
	regex = checkload(load Regex Regex->PATH, Regex->PATH);
	sh = checkload(load Sh Sh->PATH, Sh->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(argv);
	arg->setusage("o/oh [-d]");
	while((opt := arg->opt()) != 0)
		case opt {
		'd' =>
			debug++;
		* =>
			arg->usage();
		}
	if(len arg->argv() != 0)
		arg->usage();
	rc := chan of int;
	pctl(NEWPGRP, nil);
	spawn ereader(rc, parseconf());
	if(<-rc < 0)
		raise "fail: errors";
}
