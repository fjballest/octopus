implement Io;
include "sys.m";
	sys: Sys;
include "io.m";

init()
{
	if(sys != nil)
		return;
	sys = load Sys Sys->PATH;
}

readn(fd: ref Sys->FD, buf: array of byte, nb: int): int
{
	init();
	for(nr := 0; nr < nb;){
		n := sys->read(fd, buf[nr:], nb-nr);
		if(n <= 0){
			if(nr == 0)
				return n;
			break;
		}
		nr += n;
	}
	return nr;
}

readfile(fd: ref Sys->FD): array of byte
{
	init();
	buf := array[2048] of byte;
	tot := 0;
	for(;;){
		nr := sys->read(fd, buf[tot:], len buf - tot);
		if(nr < 0){
			sys->fprint(sys->fildes(2), "Io: read: %r\n");
			return nil;
		}
		if(nr == 0)
			return buf[0:tot];
		tot += nr;
		if(tot > 64 * 1024 * 1024){
			sys->fprint(sys->fildes(2), "Io: file too large. fix me.\n");
			return nil;
		}
		# When only one Kbyte is left in the buffer we grow it.
		# directory reads may need enough room for a directory entry
		# even though we still have less than len buf bytes in buf.
		if(tot > len buf - 1024){
			nbuf := array[2 * len buf] of byte;
			nbuf[0:] = buf;
			buf = nbuf;
		}
	}
}

readdev(n: string, dfl: string) : string
{
	init();
	fd := sys->open(n, Sys->OREAD);
	if(fd == nil)
		return dfl;
	data := readfile(fd);
	fd = nil;
	if(data == nil)
		return dfl;
	s := string data;
	if(len s > 0 && s[len s - 1] == '\n')
		s = s[0:len s - 1];
	return s;
	
}

copy(dfd, sfd: ref Sys->FD): int
{
	init();
	buf := array[16*1024] of byte;
	for(tot := nr := 0;; tot += nr){
		nr = sys->read(sfd, buf, len buf);
		if(nr < 0)
			return -1;
		if(nr == 0)
			return tot;
		if(sys->write(dfd, buf, nr) != nr)
			return -1;
	}
}
