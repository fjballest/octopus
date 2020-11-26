Netutil: module {
	PATH: con "/dis/o/netutil.dis";

	Client, Server: con iota;

	netmkaddr: fn(addr, net, svc: string): string;
	authfd:	fn(fd: ref Sys->FD, role: int, alg, kfile, addr: string): (ref Sys->FD, string);
};
