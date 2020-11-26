Xproc: module {
	PATH: con "/dis/o/xproc.dis";

	# See Acme/Rio Xfids
	# "A concurrent window system", Rob Pike.
	# Computing Systems, 1989
	# This defines auxiliary processes to attend
	# requests of type R which are answered by replies of type R.
	# This variant also knows how to interrupt an ongoing request.

	# Fx is a client function used to process each request
	# A sepate xproc attends each request, and is represented by an Xproc.
	# the init function returns channels where to send requests and interrupt
	# requests

	# Sent to Xproc.wc
	Run, Abort: con iota;

	# Special tags sent to the request channel to request...
	Terminate : con -1;
	Shrink:	con -2;

	Fx:	type ref fn[T,R](x: T): R;

	Proc: adt[T,R] {
		wc:	chan of int;	# to await for requests
		pid:	int;		# of helper process
		tag:	int;		# id for current request
		t:	T;		# current request
		r:	R;		# reply to it, after serve()
		rc:	chan of R;		# where to reply for current request
		serve:	ref fn(x: T): R;	# user function to attend requests
		flush:	ref fn(x: T): R;	# to reply to interrupted requests

		init:	fn(p: self ref Proc[T,R]): (chan of (int, T, chan of R), chan of (int, chan of T));

		xproc:	fn(p: ref Proc[T,R], idlec: chan of ref Proc[T,R], pidc: chan of int);
		xctlproc:	fn(p: self ref Proc[T,R], xc: chan of (int, T, chan of R), fc: chan of (int, chan of T));
	};

	# testing
	init:	fn(nil: ref Draw->Context, nil: list of string);

};
