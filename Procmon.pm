# vim: filetype=perl sw=2 foldmethod=marker commentstring=\ #\ %s
package Procmon;
use Getopt::Long;
use Pod::Usage;
use Pod::Find qw(pod_where);


sub doc { # {{{
  my ($self,$doc) = @_;
  if (ref($doc)) {
    $self->{xml} = $doc;
  }
  $self->{xml};
} # }}}

sub new { # {{{
  my ($class,%self) = @_;
  return bless \%self,$class;
} # }}}

sub _simple_dump_unique { # {{{
  my ($self,$xpath) = @_;
  my $nodelist = $self->doc->findnodes($xpath);
  my %hash =  map { $_->toString(2) => 1 } $nodelist->get_nodelist;
  print map { "$_\n" } keys %hash;
} # }}}

sub _simple_dump { # {{{
  my ($self,$xpath) = @_;
  my $nodelist = $self->doc->findnodes($xpath);
  print map { $_->toString(2),"\n" } $nodelist->get_nodelist;
} # }}}

my $intersection = sub (\@\@) { # {{{
  my ($array_left,$array_right) = @_;
  my %hash_left = map { ($_,1) } @$array_left;
  grep { defined( $hash_left{$_} ) } @$array_right;
}; # }}}

=pod

=head1 COMMANDS

=cut

# COMMAND: xpath {{{

=head2 xpath

Search with a freeform XPath expression.

  xpath --expression="/xpath/node[criteria='selection']"

=cut

sub xpath {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"expression=s","event=s","help|?");
  if ($opts->{help} || !($opts->{expression} || $opts->{event})) { # {{{
    pod2usage(
      -msg=> "XPath Help ",
      -verbose => 99,
      -sections => [ qw(COMMANDS/xpath) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

  my $xpath;
  if ($opts->{event}) {
    $xpath = sprintf("/procmon/eventlist/event[%s]",$opts->{event})
  } else {
    $xpath = $opts->{expression};
  }

  $self->_simple_dump($xpath);
} # }}}

# COMMAND: newpids {{{ 

=head2 newpids

Search a procmon log file for new processes started.  Takes no arguments.

  newpids

=cut

sub newpids {
  my ($self,@args) = @_;

  my $opts = {} ;
  my $ret = GetOptions($opts,"help|?");

  my $xpath = '/procmon/eventlist/event[Operation="Process Start"]';
  my $nodelist = $self->doc->findnodes($xpath);
  my $hash;

  if ($opts->{help}) { # {{{
    pod2usage(
      -msg => "NewPIDS help",
      -verbose => 99,
      -sections => [ qw(COMMANDS/newpids) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

($^,$~) = qw(NEWPIDS_TOP NEWPIDS);
format NEWPIDS_TOP =
 IDx   PID  PPID Command
.

format NEWPIDS =
@>>> @>>>> @>>>> @*
@$hash{qw(IDx PID PPID Command)}
.
  foreach my $node ($nodelist->get_nodelist) {
    @$hash{qw(IDx PID)} = map { $node->findvalue($_) } qw(./ProcessIndex ./PID );
    ($hash->{PPID}) = $node->findvalue('./Detail') =~ m/Parent PID:\s+(\d+)/;
    ($hash->{Command}) = $self->doc->findvalue(
      sprintf('/procmon/eventlist/event[Operation="Process Create" and contains(./Detail,"PID: %d")]',@$hash{qw(PID)})
    ) =~ m/Command line: (.+)$/;
    write;
  }
} # }}}

# COMMAND: children {{{

=head2 children

Display child processes by parent PID

  children --pid 404

=cut

sub children {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"pid=i","help|?");
  my $xpath;
  if ($opts->{pid}) {
    $xpath = sprintf('/procmon/eventlist/event[Operation="Process Start" and contains(./Detail,"Parent PID: %d")]/PID/child::text()',$opts->{pid});
  } else {
    pod2usage(
      -msg=> "Children Help",
      -verbose => 99,
      -sections => [ qw(COMMANDS/children) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  }
  
  $self->_simple_dump($xpath);
} # }}}

# COMMAND: operations {{{

=head2 operations

Display all operations, or operations performed by PID.

  operations

  operations -p 404

=cut

sub operations {
  my ($self,@args) = @_;
  my $xpath;
  my $opts = {} ;
  my $ret = GetOptions($opts,"pid=i","unique!");
  if ($opts->{pid}) {
    $xpath = sprintf('/procmon/eventlist/event[PID=%d]/Operation/child::text()',$opts->{pid});
  } else {
    $xpath = '/procmon/eventlist/event/Operation/child::text()'
  }

  if ($opts->{unique}) { # {{{
    $self->_simple_dump_unique($xpath);
  } else {
    $self->_simple_dump($xpath);
  } # }}}
} # }}}

# COMMAND: files {{{

=head2 files

Show file activity from a process

  files --pid 404

=cut

sub files {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"help|?",
    "pid=i",
  );
  if ($opts->{help}) { # {{{
    pod2usage(
      -msg=> "files Help ",
      -verbose => 99,
      -sections => [ qw(COMMANDS/files) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

  my $xml = $self->doc;
  my $xpath = sprintf('/procmon/eventlist/event[PID=%d and contains(./Operation,"File")]',$opts->{pid});
  my $nodelist = $xml->findnodes($xpath);
  my $hash = {};

($^,$~) = qw(FILES_TOP FILES);
format FILES_TOP =
 IDx  PID Process          Operation               Result
.

format FILES =
@>>> @>>> @<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<... @<<<<<<<<<<<<<<<
@$hash{qw(IDx PID Process_Name Operation Result)}
Path: @*
$hash->{Path}
Detail: ^*~~
@$hash{Detail}
---------------------------------------------------------------------------

.

  foreach my $node ($nodelist->get_nodelist) {
    @$hash{qw(IDx PID Process_Name Operation Result Path Detail)} = map { $node->findvalue($_) } qw(./ProcessIndex ./PID ./Process_Name ./Operation ./Result ./Path ./Detail);
    write;
  }
  #print map { $_->toString(2),"\n" } $nodelist->get_nodelist;
} # }}}

# COMMAND: newfiles {{{

=head2 newfiles

Show file activity from a process

  files --pid 404

=cut

sub newfiles {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"help|?",
    "pid=i",
  );
  if ($opts->{help}) { # {{{
    pod2usage(
      -msg=> "New Files Help ",
      -verbose => 99,
      -sections => [ qw(COMMANDS/newfiles) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

  my $xml = $self->doc;
  my $compound = 'contains(Operation,"File") and contains(Detail,"Created")';
  if ($opts->{pid}) {
    $compound .= sprintf(" and PID=%d",$opts->{pid});
  }
  my $xpath = sprintf('/procmon/eventlist/event[%s]/Path/child::text()',$compound);
  $self->_simple_dump($xpath);
} # }}}

# COMMAND: selfload {{{

=head2 selfload

Show process that load files they wrote as modules (libraries)

  selfload --pid 404

=cut

sub selfload {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"help|?",);
  if ($opts->{help} ) { # {{{
    pod2usage(
      -msg=> "Process Info Help ",
      -verbose => 99,
      -sections => [ qw(COMMANDS/selfload) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

  my @pids = map { $_->to_literal } $self->doc->findnodes('/procmon/processlist/process/ProcessId/child::text()');
  foreach my $pid (@pids) {
    my @modules = map { $_->to_literal } $self->doc->findnodes(
      sprintf('/procmon/processlist/process[ProcessId=%d]/modulelist/module/Path/child::text()',$pid)
    );
    my @written = map { $_->to_literal } $self->doc->findnodes(
      sprintf('/procmon/eventlist/event[contains(Operation,"File") and contains(Detail,"Created") and PID=%d]/Path/child::text()',$pid)
    );
    my @intersection = $intersection->(\@modules,\@written);
    printf("Pid: %d\nSelfloaded modules:\n%s\n",$pid,join("\n",map { "  $_" } @intersection)) if scalar @intersection;
  }

} # }}}

# COMMAND: pinfo {{{

=head2 pinfo

Show process info by pid

  pinfo --pid 404

=cut

sub pinfo {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"help|?",
    "pid=i",
  );
  if ($opts->{help} || !($opts->{pid}) ) { # {{{
    pod2usage(
      -msg=> "Process Info Help ",
      -verbose => 99,
      -sections => [ qw(COMMANDS/pinfo) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

  my $xpath = sprintf('/procmon/processlist/process[ProcessId=%d]',$opts->{pid});
  $self->_simple_dump($xpath);
} # }}}

# COMMAND: skeleton {{{

=begin comment

Search with a freeform XPath expression.

  xpath --expression="/xpath/node[criteria='selection']"

=cut

sub skeleton {
  my ($self,@args) = @_;
  my $opts = {} ;
  my $ret = GetOptions($opts,"help|?",
    "expression=s",
  );
  if ($opts->{help} || !($opts->{expression})) { # {{{
    pod2usage(
      -msg=> "skeleton Help ",
      -verbose => 99,
      -sections => [ qw(COMMANDS/skeleton) ],
      -exitval=>0,
      -input => pod_where({-inc => 1}, __PACKAGE__),
    );
  } # }}}

  my $xml = $self->doc;
  my $nodelist = $xml->findnodes($opts->{expression});
  print map { $_->toString(2),"\n" } $nodelist->get_nodelist;
} # }}}

1;
