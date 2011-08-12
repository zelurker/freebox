while (1) {
	print "ouverture fifo info...\n";
	open(F,"<fifo_info");
		eval {
			alarm(5);
			local $SIG{ALRM} = sub { die "alarm clock restart" };
			print "lecture de la fifo...\n";
			<F>;
			alarm(0);
		};
		if ($@) {
			print "timeout\n";
		} else {
			die "pas de timeout ???\n";
		}
		close(F);
	}
