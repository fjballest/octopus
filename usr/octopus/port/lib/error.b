implement Error;
include "sys.m";
	sys: Sys;
include "error.m";


kill(pid: int, msg: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", msg) < 0)
		return -1;
	return 0;
}

checkload[T](x: T, p: string): T
{
	if(x == nil)
		error(sys->sprint("cannot load %s: %r", p));
	return x;
}

error(e: string)
{
	sys->fprint(sys->fildes(2), "%s\n", e);
	raise "fail:error";
}

panic(e: string)
{
	sys->fprint(sys->fildes(2), "panic: %s\n", e);
	raise "abort";
}

init(s: Sys)
{
	sys = s;
	stderr = sys->fildes(2);
}
