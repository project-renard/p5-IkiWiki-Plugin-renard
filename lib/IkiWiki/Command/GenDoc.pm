package IkiWiki::Command::GenDoc;
# ABSTRACT: Generate document pages

use Moo;
use Function::Parameters;
use MooX::Lsub;
use CLI::Osprey;
use List::AllUtils qw(first);

use Renard::Incunabula::Format::PDF::Document;
use YAML::XS qw(LoadFile);

option setup => (
	is => 'ro',
	required => 1,
	format => 's',
	doc => 'Path to ikiwiki configuration file',
);

option document => (
	is => 'ro',
	required => 1,
	format => 's',
	doc => 'Path to document',
);

option output => (
	is => 'ro',
	required => 1,
	format => 's',
	doc => 'Path to output directory',
);

lsub setup_path => method() {
	path($self->setup);
};

lsub config => method() {
	LoadFile($self->setup_path),
};

lsub srcdir => method() {
	path($self->config->{srcdir});
};

lsub underlays => method() {
	$self->config->{add_underlays} // [];
};

lsub search_dirs => method() {
	[ $self->srcdir, @{ $self->underlays } ];
};

method run(@) {
	my $doc_name = $self->document;
	my $filename = first
		{ -r }
		map { path($_)->child($doc_name) }
		@{ $self->search_dirs };

	die "filename @{[ $self->document ]} not found in search dirs @{ $self->search_dirs }" unless $filename;

	my $doc = Renard::Incunabula::Format::PDF::Document->new(
		filename => $filename,
	);
	my $pages = $doc->number_of_pages;
	my $padding = length $pages;

	my $output_path = path($self->output);
	if( -d $output_path ) {
		die "output path $output_path already exists";
	}

	$output_path->mkpath();
	for my $page_num (1..$pages) {
		my $page_doc_name = sprintf("%0${padding}d/index.mdwn", $page_num);
		my $page_doc = $output_path->child(qw(page), $page_doc_name);
		$page_doc->parent->mkpath;
		$page_doc->spew(<<EOF);
---
RenardDocument: $doc_name
RenardPage: $page_num
---

[[!renard action=render]]

EOF
	}
}

1;
