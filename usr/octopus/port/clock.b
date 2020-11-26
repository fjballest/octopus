implement Clock;
include "sys.m";
	sys: Sys;
	sleep, sprint, open, FD, OWRITE,
	fprint, OTRUNC, write: import sys;
include "math.m";
	math: Math;
	Pi, cos, sin: import math;
include "draw.m";
	Point: import Draw;
include "panel.m";
	panels: Panels;
	Panel: import panels;
include "daytime.m";
	daytime: Daytime;
	Tm, now, local: import daytime;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;


Clock: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

ui: ref Panel;
drw: ref Panel;

circlept(c: Point, r, degrees: int): Point
{
	rad := Pi *  (real degrees) /180.0;
	c.x += int (cos(rad)* real r);
	c.y -= int (sin(rad)* real r);
	return c;
}

oanghr := 666;	# any invalid angle
oangmin:= 666;	# any invalid angle

update(await: int)
{
	tms := local(now());
	anghr := 90-(tms.hour*5 + tms.min/10)*6;
	angmin := 90-tms.min*6;
	if (oanghr != anghr || oangmin != angmin){
		oanghr = anghr;
		oangmin= angmin;
		c := Point(40,40);
		rad := 35;
		s := sprint("fillellipse %d %d %d %d back\n",
			c.x, c.y, rad, rad);
		s += sprint("ellipse %d %d %d %d\n", c.x, c.y, rad, rad);
		cpt: Point;
		for(i :=0; i<12; i++){
			cpt = circlept(c, rad - 8, i*(360/12));
			s += sprint("fillellipse %d %d %d %d mback\n",
				cpt.x,  cpt.y, 2, 2);
		}
		cpt = circlept(c, (rad*3)/4, angmin);
		s += sprint("line %d %d %d %d 0 2 1 bord\n",
			c.x, c.y, cpt.x, cpt.y);
		cpt = circlept(c, rad/2, anghr);
		s += sprint("line %d %d %d %d 0 2 1 bord\n",
			c.x, c.y, cpt.x, cpt.y);
		s += sprint("fillellipse %d %d 3 3 bord\n", c.x, c.y);
		dt := array of byte s;
		drw.ctl("hold\n");
		fd := open(drw.path + "/data", OWRITE|OTRUNC);
		if(fd == nil)
			error(sprint("o/clock: open: %r"));
		if(write(fd, dt, len dt) != len dt)
			error(sprint("o/clock: write: %r"));
		fd = nil;
		drw.ctl("release\n");
	}
	if(await){
		d := 60 - tms.sec;
		if(d < 1)
			d = 1;
		sleep(d * 1000);
	}
}

mkclock()
{
	drw = ui.new("draw:clock", 0);
	if(drw == nil)
		error("o/clock: can't create ui");
	scrs := panels->screens();
	if(len scrs == 0)
		error("o/clock: no screens");
	update(0);
	drw.ctl("tag\n");
	showctl := sprint("copyto %s/row:stats\n", hd scrs);
	if(drw.ctl(showctl) < 0)
		error("o/clock: can't show");
}

clock()
{
	for(;;)
		update(1);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	math = checkload(load Math Math->PATH, Math->PATH);
	panels = checkload(load Panels Panels->PATH, Panels->PATH);
	panels->init();
	ui = Panel.init("clock");
	if(ui == nil)
		error("o/clock: can't initialize panels");
	mkclock();
	spawn clock();
}
