Query: module {
	PATH: con "/dis/o/query.dis";

	init:	fn(nil: ref Draw->Context, args: list of string);
	lookup: fn(what: list of string): (list of string, string);
};

