#
# Execution processes.
# See Acme/Rio Xfids
# "A concurrent window system", Rob Pike.
# Computing Systems, 1989
#

implement Xproc;
include "sys.m";
	sys: Sys;
	fprint, create, stat, sprint, QTDIR, pwrite, fwstat, OTRUNC, fildes, FD, ORCLOSE, Dir, 
	read, DMDIR, NEWPGRP, FORKNS,
	open, pctl, sleep, nulldir, fstat, pread,
	dial, remove, write, OREAD, OWRITE: import sys;
include "draw.m";
include "xproc.m";

xabort := 0;	# make xprocs exit when done


# Initialize by starting a control proc, which creates xprocs
# as needed. Return channels to send (tag, requests, replychan) and to send
# (flushedtag, replychan ) (this last one gets a copy of the flushed request).

Proc[T,R].init(p: self ref Proc[T,R]):  (chan of (int, T, chan of R), chan of (int, chan of T))
{
	sys = load Sys Sys->PATH;
	xc := chan of (int, T, chan of R);
	fc:= chan of (int, chan of T);
	spawn p.xctlproc(xc, fc);
	return (xc, fc);
}

Proc[T,R].xctlproc(p: self ref Proc[T,R], xc: chan of (int, T, chan of R), fc: chan of (int, chan of T))
{
	tprocs: list of ref Proc[T,R];	# procs avail for transanctions
	bprocs: list of ref Proc[T,R];	# busy procs
	tprocs = nil;
	bprocs = nil;
	donec := chan of ref Proc[T,R];
	pidc:= chan of int;

	for(;;){
		alt {
		(tag, t, rc) := <- xc =>
			if(t == nil && (tag == Terminate || tag == Shrink)){
				xabort = (tag == Terminate);
				for(; tprocs != nil; tprocs = tl tprocs)
					(hd tprocs).wc <-= Abort;
				if(tag == Terminate)
					exit;
				else
					continue;
			}
			tp: ref Proc[T,R];
			if(tprocs != nil){
				tp = hd tprocs;
				tprocs = tl tprocs;
			} else {
				wc := chan of int;
				tp = ref Proc[T,R](wc, -1, -1, nil, nil, nil, p.serve, p.flush);
				spawn Proc[T,R].xproc(tp, donec, pidc);
				tp.pid = <-pidc;
			}
			tp.tag = tag;
			tp.rc = rc;
			tp.t = t;
			tp.wc <-= Run;
			bprocs = tp::bprocs;

		tp := <- donec =>
			tp.tag = -1;
			tp.t = nil;
			if(tp.rc != nil)
				tp.rc <-= tp.r;
			tp.rc = nil;
			tp.r = nil;
			bprocs = delproc(bprocs, tp);
			tprocs = tp::tprocs;

		(ftag,frc) := <-fc =>
			tp := findproc(bprocs, ftag);
			if(tp == nil)
				frc <-= nil;
			else {
				if((trc := tp.rc) != nil && (tr := tp.r) != nil){
					# If we already have a reply
					# deliver it and then respond to flush
					# but allow the process to become idle again.
					tp.rc = nil;
					tp.r = nil;
					trc <-= tr;
					frc <-= nil;
				} else {
					# Racing part. Kill the process and hope
					# it did not have a chance to reply while
					# we reach kill() [it does not in Inferno].
					tp.rc = nil;
					pid := tp.pid;
					ft := tp.t;
					tp.t = nil;
					tp.pid = -1;
					kill(pid, "kill");
					bprocs = delproc(bprocs, tp);
					trc <-= p.flush(ft);
					frc <-= ft;
				}
			}
		}
	}
}

Proc[T,R].xproc(p: ref Proc[T,R], donec: chan of ref Proc[T,R], pidc: chan of int)
{
	pidc <-= pctl(0, nil);
	for(;;){
		x := <-p.wc;
		if(x == Abort){
			p.pid = p.tag = -1;
			exit;
		}
		p.r = p.serve(p.t);
		if(xabort){
			p.pid = p.tag = -1;
			exit;
		}
		donec <-= p;
	}
}

kill(pid: int, msg: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", msg) < 0)
		return -1;
	return 0;
}

delproc[T,R](l: list of ref Proc[T,R], up: ref Proc[T,R]): list of ref Proc[T,R]
{
	nl: list of ref Proc[T,R];
	for(nl = nil; l != nil; l = tl l){
		p := hd l;
		if(p.pid != up.pid)
			nl = p::nl;
	}
	return nl;
}

findproc[T,R](l: list of ref Proc[T,R], tag: int): ref Proc[T,R]
{
	for(; l != nil; l = tl l){
		p := hd l;
		if(p.tag == tag)
			return p;
	}
	return nil;
}

#
# Testing
#

Req: adt {
	nb:	int;
	name:	string;
};

Rep: adt {
	nb:	int;
	name:	string;
};

xserve(t: ref Req): ref Rep
{
	sleep(1000);
	return ref Rep(t.nb, "r." + t.name);
}

xflush(t: ref Req): ref Rep
{
	return ref Rep(t.nb, "f." + t.name);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	reps := array[10] of chan of ref Rep;

	for(i := 0; i < len reps; i++)
		reps[i] = chan[1] of ref Rep;
	p := ref Proc[ref Req, ref Rep];
	p.serve = xserve;
	p.flush = xflush;
	(rc, fc) := p.init();
	for(i = 0; i < len reps; i++)
		rc <-= (i, ref Req(i, sprint("do%d", i)), reps[i]);
	f1 := chan[1] of ref Req;
	f2 := chan[1] of ref Req;
	fc <-= (4, f1);
	fc <-= (4, f2);
	for(i = 0; i < len reps; i++){
		rep := <-reps[i];
		if(rep != nil)
			sys->print("->rep %d %s\n", rep.nb, rep.name);
	}
	rep := <-f1;
	if(rep != nil)
		sys->print("flush %s\n", rep.name);
	rep = <-f2;
	if(rep != nil)
		sys->print("flush %s\n", rep.name);
	rc <-= (-2, nil, nil);
	sys->print("ps\n");
	sleep(5*1000);
	rc <-= (-1, nil, nil);
}
