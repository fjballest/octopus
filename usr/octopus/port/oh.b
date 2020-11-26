#
# o/mero history (recent commands)
# this is an example of how to snoop on o/x commands
# and how to ask it to execute some.
# It's probably more convenient to keep an "edit" file
# with the frequent commands.
#
implement Oh;
include "sys.m";
	sys: Sys;
	sleep, sprint, create, pctl, read, open, FD, OWRITE,
	ORDWR, ORCLOSE, fprint, OTRUNC, write: import sys;
include "draw.m";
	Point: import Draw;
include "panel.m";
	panels: Panels;
	Panel: import panels;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "string.m";
	str: String;
	in, prefix, drop, splitl: import str;
include "readdir.m";
	readdir: Readdir;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;


Oh: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

Cmd: adt {
	r: int;
	p: ref Panel;
	c: string;
};

ui: ref Panel;
cmds: array of Cmd;
debug := 0;
oxctl: string;

locateox()
{
	(dirs, nd) := readdir->init("/mnt/ui/appl", 0);
	for(i := 0; i < nd; i++)
		if(prefix("col:ox.", dirs[i].name)){
			oxctl = "/mnt/ui/appl/" + dirs[i].name + "/ctl";
			return;
		}
	fprint(stderr, "o/oh: no o/x\n");
	terminate();
	
}

update(i: int)
{
	fd := open(cmds[i].p.path + "/data", OWRITE|OTRUNC);
	if(fd == nil)
		error(sprint("o/oh: open: %r"));
	c := cmds[i].c;
	if(len c > 30)
		c = c[0:30] + "...";
	fprint(fd, "%s\n", c);
}

mkui()
{
	ui = Panel.init("oh");
	if(ui == nil)
		error("o/oh: can't initialize panels");
	for(i := 0; i < len cmds; i++){
		name := sprint("button:%d", i);
		cmds[i].r = 0;
		cmds[i].p = ui.new(name, i+1);
		if(cmds[i].p == nil)
			error("o/oh: can't create button");
		cmds[i].p.ctl("font S");
		cmds[i].c = "";
		update(i);
	}
	scr := panels->userscreen();
	if(scr == nil)
		if((scrs := panels->screens()) != nil)
			scr = hd scrs;
	if(scr == nil)
		error("o/oh: no screens");
	ui.ctl("tag\n");
	if(ui.ctl(sprint("copyto %s/row:stats\n", scr)) < 0)
		error("o/oh: can't show");
}

lasti := 0;
event(s: string)
{
	if(len s > 2 && in(s[0], "A-Z") && in(s[1], "a-z"))	# ignore builtins
		return;
	for(i := 0; i < len cmds; i++)
		if(s == cmds[i].c){
			cmds[i].r++;
			return;
		}
	for(;;){
		if(cmds[lasti].r > 0)
			cmds[lasti].r--;
		else {
			cmds[lasti].r++;
			cmds[lasti].c = s;
			update(lasti);
			break;
		}
		lasti = ++lasti % len cmds;
	}
}
runcmd(c: string)
{
	fd := open(oxctl, OWRITE);
	if(fd == nil)
		locateox();
	fd = open(oxctl, OWRITE);
	if(fd == nil){
		fprint(stderr, "o/oh: no ox: %r\n");
		terminate();
	}
	fprint(fd, "exec %s\n", c);
	fd = nil;
}


ereader(ec: chan of string)
{
	fname := sprint("/mnt/ports/oh.%d", pctl(0, nil));
	fd := create(fname, ORDWR|ORCLOSE, 8r664);
	if(fd == nil){
		ec <-= nil;
		exit;
	}
	expr := array of byte "^exec:.*";
	write(fd, expr, len expr);
	buf := array[512] of byte;	# enough for events of interest
	for(;;){
		nr := read(fd, buf, len buf);
		if(nr <= 0){
			ec <-= nil;
			break;
		}
		s := string buf[0:nr];
		if(len s > 5 && s[0:5] == "exec:"){
			s = drop(s[5:], " \t");
			(s, nil) = splitl(s, "\n");
			ec <-= s;
		}
	}
}

terminate()
{
	fprint(stderr, "o/oh: exiting\n");
	kill(pctl(0, nil), "killgrp");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	str = checkload(load String String->PATH, String->PATH);
	panels = checkload(load Panels Panels->PATH, Panels->PATH);
	readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(argv);
	arg->setusage("o/oh [-d] [-n ncmds]");
	ncmds := 4;
	while((opt := arg->opt()) != 0)
		case opt {
		'd' =>
			debug = 1;
		'n' =>
			ncmds = int arg->earg();
		* =>
			arg->usage();
		}
	if(len arg->argv() != 0)
		arg->usage();
	panels->init();
	cmds = array[ncmds] of Cmd;
	mkui();
	locateox();
	cec := chan of string;
	spawn ereader(cec);
	pec := ui.evc();
	for(;;) alt {
	s := <-cec =>
		if(s == nil)
			terminate();
		if(debug)
			fprint(stderr, "o/oh: event %s\n", s);
		event(s);
	e := <-pec =>
		if(e == nil)
			terminate();
		e.id--;
		if(e.id < 0 || e.id >= len cmds){
			fprint(stderr, "o/oh: bad event id\n");
			continue;
		}
		case e.ev {
		"close" =>
			terminate();
		"exec" =>
			if(debug)
				fprint(stderr, "o/oh: exec %s\n", e.arg);
			runcmd(cmds[e.id].c);
		}
	}
}
