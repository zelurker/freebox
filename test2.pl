open(F,">fifo");
print "pipe ouverte\n";
for (my $n=4; $n<=6; $n++) {
	print F "$n\n";
	sleep(5);
}
close(F);

