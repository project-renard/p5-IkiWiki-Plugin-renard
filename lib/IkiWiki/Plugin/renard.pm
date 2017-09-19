package IkiWiki::Plugin::renard;
# ABSTRACT: Plugin

use warnings;
use strict;
use IkiWiki 3.00;

use Env qw(@PATH);
use Renard::Incunabula::Format::PDF::Document;
use Alien::pdf2htmlEX;
use Alien::Poppler;
use Capture::Tiny qw(capture);

our $tabinator_CSS = <<EOF;
.tabinator {
  background: #fff;
  padding: 40px;
}
.tabinator h2 {
  text-align: center;
  margin-bottom: 20px;
}
.tabinator input {
  display: none;
}
.tabinator label {
  box-sizing: border-box;
  display: inline-block;
  padding: 15px 25px;
  color: #ccc;
  margin-bottom: -1px;
  margin-left: -1px;
}
.tabinator label:before {
  content:'';
  display:block;
  width:100%;
  height:15px;
  background-color:#fff;
  position:absolute;
  bottom:-11px;
  left:0;
  z-index:10;
}
.tabinator label:hover {
  color: #888;
  cursor: pointer;
}
.tabinator input:checked + label {
  position: relative;
  color: #000;
  background: #fff;
  border: 1px solid #bbb;
  border-bottom: 1px solid #fff;
  border-radius: 5px 5px 0 0;
}
.tabinator input:checked + label:after {
  display: block;
  content: '';
  position: absolute;
  top: 0; right: 0; bottom: 0; left: 0;
  box-shadow: 0 0 15px #939393;
}
EOF

sub import {
	hook(type => "getsetup", id => "renard", call => \&getsetup);
	hook(type => "preprocess", id => "renard", call => \&preprocess, scan => 1);

	IkiWiki::loadplugin("field");

	push @PATH, Alien::pdf2htmlEX->bin_dir;
	push @PATH, Alien::Poppler->bin_dir;
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params = @_;

	if (! exists $params{action}) {
		error gettext("missing action parameter");
	}

	$params{included} = ($params{page} ne $params{destpage});
	my $css_prefix = $params{page} =~ s,[^A-Za-z0-9-],,gr;

	$params{renard}{document} //= IkiWiki::Plugin::field::field_get_value('RenardDocument',
		$config{preview_path} // $params{page});

	$params{renard}{page} //= IkiWiki::Plugin::field::field_get_value('RenardPage',
		$config{preview_path} // $params{page});

	error "renard plugin fields not configured" unless $params{renard}{document};

	$params{renard}{_compute}{document}    = srcfile($params{renard}{document});
	$params{renard}{_compute}{page}{first} = $params{renard}{page};
	$params{renard}{_compute}{page}{last}  =  $params{renard}{page};

	my $style = '';
	my $output = '';

	# Simple CSS tabs with shadow from <https://codepen.io/ekscentrysytet/pen/QbNdEB>
	$style .= $tabinator_CSS;
	$style .= <<EOF;
#${css_prefix}-renard-content1, #${css_prefix}-renard-content2 {
  display: none;
  border-top: 1px solid #bbb;
  padding: 15px;
}
#${css_prefix}-tab1:checked ~ #${css_prefix}-renard-content1,
#${css_prefix}-tab2:checked ~ #${css_prefix}-renard-content2 {
  display: block;
  box-shadow: 0 0 15px #939393;
}
EOF

	# Fit rendered page to container
	$style  .= <<EOF;
img.renard-render-page {
	width: 100%;
}
EOF

	$output .= '<div class="renard">';
	$output .= '<div class="tabinator">';


	$output .= <<EOF;
<input type = "radio" id = "${css_prefix}-tab1" name = "${css_prefix}-tabs" checked>
<label for = "${css_prefix}-tab1">Rendered page</label>
<input type = "radio" id = "${css_prefix}-tab2" name = "${css_prefix}-tabs">
<label for = "${css_prefix}-tab2">pdftohtml</label>
EOF
	{
		$output .= qq|<div id="${css_prefix}-renard-content1">|;
		$output .= '<div class="mupdf">';
		$output .=      mutool(%params);
		$output .= '</div>'; # .mupdf
		$output .= '</div>'; # .renard-content1
	}

	{
		$output .= qq|<div id="${css_prefix}-renard-content2">|;
		$output .= '<div class="pdftohtml">';
		$output .=      poppler_pdftohtml(%params);
		$output .= '</div>'; # .pdftohtml
		$output .= '</div>'; # .renard-content2
	}

	$output .= '</div>'; # .tabinator
	$output .= '</div>'; # .renard

	my $style_html =
		qq|<style type="text/css">\n|
		.
		join("\n", map { "\t$_" } split /\n/, $style)
		.
		qq|</style>\n|;

	$output = $style_html . $output;

	return $output;
}

sub poppler_pdftohtml {
	my %params = @_;

	my @pdftohtml_command = ( qw(pdftohtml),
			qw(-i -noframes -stdout),
			qw(-f), $params{renard}{_compute}{page}{first},
			qw(-l), $params{renard}{_compute}{page}{last},
			$params{renard}{_compute}{document}, );

	my ($pdftohtml_stdout, $pdftohtml_stderr, $exit) = capture {
		system(@pdftohtml_command);
	};
	die "pdftohtml error: $pdftohtml_stderr" if $exit;

	my ($body_inner_html) = $pdftohtml_stdout =~ m|<body[^>]*>(.*)</body|msi;

	# replace NBSP with regular space
	$body_inner_html =~ s/\Q&#160;\E/ /gs;

	$body_inner_html;
}


sub mutool {
	my %params = @_;

	my $page = $params{page};
	my $destdir = File::Spec->rel2abs($config{destdir});

        my $urltobase = $params{preview} ? undef : $params{destpage};

	my $renard_doc = Renard::Incunabula::Format::PDF::Document->new(
		filename => $params{renard}{_compute}{document},
	);

	my @page_nums = $params{renard}{_compute}{page}{first}
		..  $params{renard}{_compute}{page}{last};

	my $output = '';

	my $counter = 1;
	for my $page_num (@page_nums) {
		my $zoom = 1;
		my $renard_page = $renard_doc->get_rendered_page(
			page_number => $page_num,
			zoom_level => $zoom,
		);

		my $img = "renard-mutool-@{[ $renard_doc->filename->basename('pdf') ]}-$page_num-$counter.png";
		my $pagedir = $page . "/gfx";
		my $destimg = $pagedir . "/" . $img;

		will_render( $params{page}, $destimg );

		my $data = $renard_page->png_data;

		writefile($img, $destdir."/".$pagedir, $data, 1) || die "$!";

		my $imgurl = urlto($destimg, $urltobase);
		$output .= qq|
		<a href="$imgurl" target="_blank">
			<img src="$imgurl" class="renard-render-page">
		</a>\n|;

		$counter++;
	}

	return $output;
}

1;
