open(F,">fifo_list");
print F "name 1\n";
while (<F>) {
	print "réponse $_\n";
}
close(F);


