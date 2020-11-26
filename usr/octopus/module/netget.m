Netget: module {
	PATH: con "/dis/o/netget.dis";

	init:	fn(nil: ref Draw->Context, args: list of string);
	announce: fn(name: string, spec: string) : string;
	ndb:	fn() : string;
	terminate: fn();
};
