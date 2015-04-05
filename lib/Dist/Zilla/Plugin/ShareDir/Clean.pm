package Dist::Zilla::Plugin::ShareDir::Clean;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use utf8;

use Moose;
use namespace::autoclean;

use File::Find;
use IPC::System::Options qw(backtick);
use List::Util qw(first);

with (
    'Dist::Zilla::Role::InstallTool',
);

has dir => (is=>'rw', default=>'share');
has clean_tarball => (is=>'rw', default=>1);

sub setup_installer {
  my ($self) = @_;

  my %mentioned_files;
  my @cmd = ("git", "log", "--numstat", $self->dir);
  my @res = backtick({die=>1}, @cmd);
  for (@res) {
      /^\d+\t\d+\t(.+)/ or next;
      $mentioned_files{$1}++;
  }

  my %current_files;
  find sub {
      return unless -f;
      $current_files{"$File::Find::dir/$_"}++;
  }, $self->dir;

  my @old_files;
  for (keys %mentioned_files) {
      next if $current_files{$_};
      my $name = $_;
      $name =~ s!.+?/!!; # remove share dir name
      push @old_files, $name unless $current_files{$_};
  }
  return unless @old_files;

  push @old_files, "shared-files.tar.gz" if $self->clean_tarball;

  $self->log_debug(["old files: %s", \@old_files]);

  # first, try MakeMaker
  my $build_script = first { $_->name eq 'Makefile.PL' }
      @{ $self->zilla->files };
  $self->log_fatal('No Makefile.PL found. Using [MakeMaker] is required')
      unless $build_script;

  my $content = $build_script->content;

  no strict 'refs';
  my $header = "# modify generated Makefile to remove old shared files from previous versions. this piece is generated\n" .
      "#  by " . __PACKAGE__ . " version " .
      (${__PACKAGE__ ."::VERSION"} // 'dev').".\n";

  my $body = <<'_';
CLEAN_SHARE_DIR:
{
    #require Perl::osnames;
    #last unless Perl::osnames::is_posix();

    print "Modifying Makefile to remove old shared files from previous versions on install\n";
    open my($fh), "<", "Makefile" or die "Can't open generated Makefile: $!";
    my $content = do { local $/; ~~<$fh> };

    $content =~ s/^(install :: pure_install doc_install)/$1 clean_sharedir/m
        or die "Can't find pattern in Makefile (1)";

    $content .= qq|\nclean_sharedir :\n\t| .
        q|$(RM_F) {{files}}| .
        qq|\n\n|;

    open $fh, ">", "Makefile" or die "Can't write modified Makefile: $!";
    print $fh $content;
}
_


  my $dist_name = $self->zilla->name;
  my $files = join(
      " ",
      map {(
          qq{"\$(SITELIBEXP)/auto/share/dist/$dist_name/$_"},
      )} @old_files);

  $body =~ s/\{\{files\}\}/$files/;
  $content .= $header . $body;
  $self->log_debug(["adding section in Makefile.PL to clean old shared files"]);
  return $build_script->content($content);
}

no Moose;
1;
# ABSTRACT: Delete shared files from older versions when distribution is installed

=for Pod::Coverage ^(setup_installer)$

=head1 SYNOPSIS

In your dist.ini:

 [ShareDir]

 [ShareDir::Clean]
 ;dir=share
 ;clean_tarball=1


=head1 DESCRIPTION

This plugin is an alternative to using L<Dist::Zilla::Plugin::ShareDir::Tarball>
(please read the documentation of that module first). With this plugin, you can
keep using L<Dist::Zilla::Plugin::ShareDir>, but eliminate the problem of
lingering old files.

What this plugin does is search for old shared files (currently the only method
used is by performing a C<git log --numstat> on your repository and comparing
the files to what is currently in the working directory). A section will then be
added to the generated C<Makefile.PL> to remove the old files during
installation.

Some caveats/current limitations:

=over

=item * Your project must use git.

=item * Only Makefile.PL is currently supported.

=item * Windows (or other non-POSIX) build system is not yet supported. Patches welcome.

Path separator assumed to be C</>. Besides, I don't know yet what C<git log>
uses for path separator on those systems.

=item * Windows (or other non-POSIX) installation target system is not yet supported. Patches welcome.

The commands in the generated C<Makefile.PL> is currently Unix-style (shell
quoting style, use of C<rm> command, ...).

=item * When user downgrades, files from newer version won't be deleted.

=back


=head1 CONFIGURATION

=head2 dir => str (default: share)

Name of shared directory.

=head2 clean_tarball => bool (default: 1)

If set to 1, will also try to clean C<shared-files.tar.gz> produced by
L<Dist::Zilla::Plugin::ShareDir::Tarball>.


=head1 SEE ALSO

L<Dist::Zilla::Plugin::ShareDir>

L<Dist::Zilla::Plugin::ShareDir::Tarball>

=cut
