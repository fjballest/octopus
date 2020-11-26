# Notify (via plumber) new imports and gone imports
# made through ofs.

Ofsnotify: module {
	PATH: con "/dis/o/ofs/ofsnotify.dis";

	init:	fn(what: string);
	arrived:	fn();
	gone:	fn();
};
