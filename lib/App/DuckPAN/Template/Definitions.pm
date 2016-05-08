package App::DuckPAN::Template::Definitions;
# ABSTRACT: Defines available templates.

use Moo;

use Try::Tiny;
use Path::Tiny;
use YAML::XS qw(LoadFile);

use App::DuckPAN::Template;
use App::DuckPAN::TemplateSet;
use App::DuckPAN::InstantAnswer::Util qw(:predicate);
use Carp;

with qw( App::DuckPAN::Lookup );

use namespace::clean;

has _template_dir => (
	is       => 'ro',
	required => 1,
	init_arg => 'template_directory',
	default => sub {
		path($INC{'App/DuckPAN.pm'} =~ s/\.pm$//r, 'template')
	},
	doc => 'Path to directory containing all template files.',
);

my @handlers = (
	# Scalar-based
	'remainder: (default) The query without the trigger words, spacing and case are preserved.' => 'remainder',
	'query_raw: Like remainder but with trigger words intact' => 'query_raw',
	'query: Full query normalized with a single space between terms' => 'query',
	'query_lc: Like query but in lowercase' => 'query_lc',
	'query_clean: Like query_lc but with non-alphanumeric characters removed' => 'query_clean',
	'query_nowhitespace: All whitespace removed' => 'query_nowhitespace',
	'query_nowhitespace_nodash: All whitespace and hyphens removed' => 'query_nowhitespace_nodash',
	# Array-based
	'matches: Returns an array of captured expression from a regular expression trigger' => 'matches',
	'words: Like query_clean but returns an array of the terms split on whitespace' => 'words',
	'query_parts: Like query but returns an array of the terms split on whitespace' => 'query_parts',
	'query_raw_parts: Like query_parts but array contains original whitespace elements' => 'query_raw_parts',
);

my @get_config_handler = (
	ia_handler => {
		type => 'reply',
		configure => {
			prompt => 'Which handler would you like to use to process the query?',
			choices => \@handlers,
			hash    => 1,
		},
	},
	ia_handler_var => {
		configure => sub {
			my %f = @_;
			my $handler = $f{ia_handler};
			my %check = map { $_ => 1 } ('words', 'query_parts', 'query_raw_parts', 'matches');
			return $check{$handler} ? '@' : '$';
		},
	},
	ia_trigger => {
		configure => sub {
			my %f = @_;
			return $f{ia_handler} eq 'matches'
				? q{query => qr/trigger regex/}
				: q{any => 'triggerword', 'trigger phrase'};
		},
	},
);

my @cheat_sheet_templates = (
	'code', 'keyboard', 'language', 'link', 'reference', 'terminal',
);

my @get_config_cheat_sheet = (
	template_type => {
		type => 'reply',
		configure => {
			prompt => 'Template type',
			choices => \@cheat_sheet_templates,
		},
	},
	ia_name_normalized => {
		configure => sub {
			my %vars = @_;
			my $name = $vars{ia}->{name} =~ s/\s*cheat\s*sheet\s*$//ri;
			return $name;
		},
	},
);

sub _get_config_cheat_sheet {
	my %options = @_;
	my $ia = $options{ia};
	my $app = $options{app};
	my $name = $ia->{name} =~ s/\s*cheat\s*sheet\s*$//ri;
	my $cheat_sheet_template = $app->get_reply(
		"Template type", choices => \@cheat_sheet_templates,
	);
	return {
		ia_name_normalized => $name,
		template_type      => $cheat_sheet_template,
	};
}

sub _get_cheat_sheet_output_file {
	my $vars = shift;
	my $fname = $vars->{ia}{id} =~ s/_cheat_sheet$//r;
	$fname =~ s/_/-/g;
	$fname .= '.json';
	return 'share/<:$repo.share_name:>/cheat_sheets/json/' .
	($vars->{template_type} eq 'language' ? 'language/' : '')
	. $fname;
}

my %templates = (
	cheat_sheet => {
		label       => 'Cheat Sheet',
		input_file  => 'goodie/cheat_sheet.tx',
		allow       => \&is_cheat_sheet,
		configure   => [@get_config_cheat_sheet],
		output_file => \&_get_cheat_sheet_output_file,
	},
	pm => {
		label       => 'Perl Module',
		allow       => [\&is_full_goodie, \&is_spice],
		configure   => [@get_config_handler],
		input_file  => '<:$repo.template_dir:>/perl_main.tx',
		output_file => 'lib/<:$package_separated:>.pm',
	},
	min_pm => {
		label       => 'Minimal Perl Module',
		allow       => \&is_full_goodie,
		configure   => [@get_config_handler],
		input_file  => '<:$repo.template_dir:>/perl_main_basic.tx',
		output_file => 'lib/<:$package_separated:>.pm',
	},
	test => {
		label       => 'Perl Module Test',
		allow       => [\&is_full_goodie, \&is_spice],
		input_file  => '<:$repo.template_dir:>/test.tx',
		output_file => 't/<:$package_base_separated:>.t',
	},
	js => {
		label       => 'JavaScript',
		allow       => [\&is_full_goodie, \&is_spice],
		input_file  => '<:$repo.template_dir:>/js.tx',
		output_file => 'share/<:$repo.share_name:>/<:$ia.id:>/<:$ia.id:>.js',
	},
	css => {
		label       => 'CSS',
		allow       => [\&is_full_goodie, \&is_spice],
		input_file  => '<:$repo.template_dir:>/css.tx',
		output_file => 'share/<:$repo.share_name:>/<:$ia.id:>/<:$ia.id:>.css',
	},
	handlebars => {
		label       => 'Handlebars',
		allow       => [\&is_full_goodie, \&is_spice],
		input_file  => '<:$repo.template_dir:>/handlebars.tx',
		output_file => 'share/<:$repo.share_name:>/<:$ia.id:>/<:$ia.id:>.handlebars',
	},
);

has _template_definitions => (
	is => 'ro',
	doc => 'HASH of template definitions to build.',
	isa => sub { croak('Not a HASH ref') unless ref $_[0] eq 'HASH' },
	default => sub { \%templates },
);

has _templates => (
	is      => 'ro',
	lazy    => 1,
	builder => 1,
);

sub _lookup {
	my $self = shift;
	return $self->_templates;
}

sub _lookup_id { 'id' }

sub _build__templates {
	my $self = shift;
	my %templ;
	while (my ($template, $config) = each %{$self->_template_definitions}) {
		$templ{$template} = App::DuckPAN::Template->new(
			id => $template,
			template_directory => $self->_template_dir,
			%$config,
		);
	}
	my @templates = values %templ;
	return \@templates;
}

1;
