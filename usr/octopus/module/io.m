Io: module {
	PATH: con "/dis/o/io.dis";

	readn:	fn(fd: ref Sys->FD, buf: array of byte, n: int): int;
	readfile:	fn(fd: ref Sys->FD): array of byte;
	readdev:	fn(fname: string, dflt: string): string;
	copy:	fn(dfd, sfd: ref Sys->FD): int;
};
