Sam: module {

	PATH: con "/dis/o/x/sam.dis";

	# Sam address
	Addr: adt{
		typex: int;			# # (char addr), l (line addr), / ? . $ + - , ;
		num: int;
		next: cyclic ref Addr;		# or right side of , and ; 
		re: string;
		left: cyclic ref Addr;		# left side of , and ; 
	};

	# Sam command, 
	Cmd: adt{
		addr: ref Addr;		# address (range of text)
		re: string;			# regular expression for e.g. 'x'
		next: cyclic ref Cmd;		# pointer to next element in {}
		num: int;
		flag: int;
		cmdc: int;			# command character; 'x' etc.
		cmd: cyclic ref Cmd;		# target of x, g, {, etc.
		text: string;		# text of a, c, i; rhs of s
		mtaddr: ref Addr;		# address for m, t
	};

	# Entry in the command tab
	Cmdt: adt{
		cmdc: int;			# command character
		text: int;			# takes a textual argument?
		regexp: int;		# takes a regular expression?
		addr: int;			# takes an address (m or t)?
		defcmd: int;		# default command; 0==>none
		defaddr: int;		# default address
		count: int;			# takes a count e.g. s2///
		token: string;		# takes text terminated by one of these
		fnc: int;			# function to call with parse tree
	};

	cmdtab: array of Cmdt;

	BUFSIZE: con 16 * 1024 * 1024;

	# Interface to text
	Range : adt {
		q0 : int;
		q1 : int;
	};
	Address: adt{
		r: Range;
		f: ref Oxedit->Edit;
	};

	aNo, aDot, aAll: con iota;	# default addresses

	ALLLOOPER, ALLTOFILE, ALLMATCHFILE, ALLFILECHECK,
	ALLELOGTERM, ALLEDITINIT, ALLUPDATE: con iota;

	C_nl, C_a, C_b, C_c, C_d, C_B, C_D, C_e, C_f,
	C_g, C_i, C_k, C_m, C_n, C_p, C_s, C_u, C_w,
	C_x, C_X, C_P, C_pipe, C_eq: con iota;

	editing: int;
	warnc: chan of string;

	init : fn(d: Oxdat);

	getregexp: fn(a0: int): string;
	editcmd: fn(t: ref Oxedit->Edit, r: string);
	editerror: fn(a0: string);
	cmdlookup: fn(a0: int): int;
};
