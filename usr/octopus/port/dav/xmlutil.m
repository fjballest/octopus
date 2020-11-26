Xmlutil: module {
	PATH: con "/dis/o/dav/xmlutil.dis";

	Attr: type Xml->Attribute;

	Rootname:	con "##xml##";	# name for top-level tag.
	Textname:	con "##text##";	# fake tags to hold text.

	Tag: adt {
		name:	string;
		attrs:	list of Attr;
		tags:	list of ref Tag;
		txt:	string;

		parse:	fn(b: ref Bufio->Iobuf, lcase: int): ref Tag;
		text:	fn(t: self ref Tag): string;
	};

	init:	fn(d: Dat);

	debug:	int;
};
