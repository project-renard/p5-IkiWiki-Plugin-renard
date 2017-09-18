#!/usr/bin/env perl
# ABSTRACT: Generate pages for document

use FindBin;
use lib "$FindBin::Bin/../lib";

use IkiWiki::Command::GenDoc;

sub main() {
	IkiWiki::Command::GenDoc->new_with_options->run;
}

main;
