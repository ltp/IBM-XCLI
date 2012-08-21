package IBM::XCLI;

use warnings;
use strict;

use Carp qw(croak);
use Fcntl;

our $VERSION	= '0.2';

=head1 NAME

IBM::XCLI - A Perl interface to the IBM XIV XCLI

=head1 VERSION

Version 0.2

=cut

=head1 SYNOPSIS

	use IBM::XCLI;
	
	my $xiv = IBM::XCLI->new(	
				ip_address	=>	$ip_address,
				username	=>	$user
				password	=>	$password,
				xcli		=>	$xcli
			);

	my @volumes	= $xiv->vol_list();

	foreach (@volumes) {
		s/^"\|"$//g;
		my(@volume) = split /","/;
		print "Volume:\t$volume[0]\tSize:\t$volume[1]\tUsed:\t$volume[6]\n";
	}
	

=head1 DESCRIPTION

This package provides an abstracted interface to the IBM XIV XCLI utility.

The IBM XIV XCLI is a utility providing a command line interface to an IBM XIV storage array
exposing complete management and administrative functionality to the system.

The primary aim of this package is to provide a simplified and abstracted interface to the XCLI
utility so as to reduce duplication of effort through reimlementation and to promote code reuse.

The larger portion of the methods exported by this package are "native" calls analagous to their
corresponding XCLI counterparts; i.e. the vol_list method returns the same data as an execution
of the native vol_list command would be expected to return.

The primary difference between the implementation of these "native" calls and their counterparts
is the abscense of the column headers in the return values.  This is done to remove the need for
any unnessecary additional client side post-processing of return values and to maintain a level
of consistency in expected return values.

All "native" calls are implemented using CSV output for deliniation of values.

The XCLI utility must be installed on the same machine as from which the script is ran.

=head1 METHODS

=head2 new

	my $xiv = IBM::XCLI->new(	
				ip_address	=>	$ip_address,
				username	=>	$user
				password	=>	$password,
				xcli		=>	$xcli
			);

Constructor method.  Creates a new IBM::XCLI object representing a connection to and an instance 
of a XCLI connection to the target XIV unit.

Required parameters are:

=over 3

=item ip_address

The IP address of a management interface on the target XIV unit.

=item username

The username with which to connect to the target XIV unit.

=item password

The password with which to connect to the target XIV unit.

=item xcli

The path to the XCLI binary.  This must be an absolute path to a local file for which the executing
user has appropriate privileges.

=back

=cut


sub new 		{
	my ($class, %args) = @_;
	my $self = (bless {}, $class);
	defined $args{ip_address}	? $self->{ip_address}	= $args{ip_address}	: croak "Constructor failed: ip_address not defined";
	defined $args{username}		? $self->{username}	= $args{username}	: croak "Constructor failed: username not defined";
	defined $args{password}		? $self->{password}	= $args{password}	: croak "Constructor failed: password not defined";
	defined $args{xcli}		? $self->{xcli}		= $args{xcli}		: croak "Constructor failed: xcli not defined";
	-x $self->{xcli}  		or croak "Constructor failed: ip_address not defined";
	open my $dummy_conn, '-|', $self->{xcli}, 'test'
					or croak "Constructor failed: XCLI dummy connection failed";
	my $output = <$dummy_conn>;
	$output eq "Missing user.\n" 	or croak "Constructor failed: XCLI dummy test failed";
	return $self;
}

=head2 host_list

Analagous to the native host_list method of the XCLI utility.  Returns an array of comma-seperated values
having the format:

	"Name","Type","FC Ports","iSCSI Ports","User Group","Cluster"

=cut

sub host_list 		{
	my ($self)	= @_;
	my @host_list	= $self->_xcli_execute(xcli_cmd => 'host_list');
	shift @host_list;
	return @host_list;
}

=head2 fc_connectivity_list

Returns a hash containing all configured host WWPNs (regarded as WWPNs not belonging to the unit itself)
and their login state.  For example; the code section shown below will yeild a list of all host WWPNs
that have been configured in the target unit and their FC connectivity state represented as a text identifier.

	my %fc_connectivity_list = $xiv->fc_connectivity_list();

	foreach my $wwpn (sort keys %fc_connectivity_list) {
		print "WWPN: $wwpn	$fc_connectivity_list{$wwpn}\n";
	}

=cut

sub fc_connectivity_list{
	my ($self)	= @_;
	my %fc_connectivity_list;
	my @fc_connectivity_list
			= $self->_xcli_execute(xcli_cmd	=> 'fc_connectivity_list');

	for (@fc_connectivity_list) {
		my @port= split /","/, $_;
		$port[4]=~ s/"//;
		$fc_connectivity_list{$port[1]} = $port[4];
	}

	return %fc_connectivity_list;
}

=head2 mirror_list

Analagous to the native mirror_list method of the XCLI utility.  Returns an array of comma-seperated values
having the format:

	"Name","Mirror Type","Mirror Object","Role","Remote System","Remote Peer","Active","Status","Link Up"

=cut

sub mirror_list		{
	my ($self)	= @_;
	my @mirror_list	= $self->_xcli_execute(xcli_cmd	=> 'mirror_list');
	shift @mirror_list;

	if ($mirror_list[0] =~ /","/) {
		return @mirror_list;
	}

	return;
}

=head2 vol_list

Analagous to the native vol_list method of the XCLI utility.  Returns an array of comma-seperated values
having the format:

	"Name","Size (GB)","Master Name","Consistency Group","Pool","Creator","Used Capacity (GB)"

=cut

sub vol_list	{
	my ($self)	= @_;
	my @vol_list	= $self->_xcli_execute(xcli_cmd	=> 'vol_list');
	shift @vol_list;
	return @vol_list;
}

=head2 mapping_list

Analagous to the native mapping_list method of the XCLI utility.  Returns an array of comma-seperated values
having the format:

	"LUN","Volume","Size","Master","Serial Number","Locked"

This method takes a single madatory parameter; the host name for which to report the mapping list.

=cut

sub mapping_list	{
	my($self,$host)	= @_;
	defined $host	or return 'mapping_list called without hostname';
	my @mapping_list= $self->_xcli_execute(	xcli_cmd => 'mapping_list',
						xcli_args=> "host=$host");
	shift @mapping_list;
	return @mapping_list;
}

=head2 fc_login_status

Returns a hash of hashes containing all configured host WWPNs (regarded as WWPNs not belonging to the unit itself)
and their login state.  This method is similar to the fc_connectivity_list method, however the returned value is
a hash of hashes keyed at the top level by host name.

For example; the code section shown below will yeild a list of all hosts that have been configured in the target 
unit and their FC connectivity state represented as a text identifier.

	my %fc_login_status = $xiv->fc_login_status();

	foreach my $host (sort keys %fc_login_status) {

		print "-"x50,"\nHost: $host\n";

		foreach my $wwpn (sort keys %{fc_login_status{$host}}) {
			print "\t$wwpn -> $fc_login_status{$wwpn}{$wwpn}\n";
		}

		print "-"x50,"\n\n"
	}

Will yeild a list similar to:

	--------------------------------------------------
	Host: host-1
		2100001B32117462 -> Yes
		2101001B32317462 -> Yes
	--------------------------------------------------
	...

=cut

sub fc_login_status	{
	my ($self)	= @_;
	my %fc_login_status;
	my %fc_connectivity_list
			= $self->fc_connectivity_list;
	my @host_list	= $self->host_list;

	foreach (@host_list) {
		my @host= split /","/, $_;
		$host[0]=~ s/^"//;
		my @ports = split /,/, $host[2];

		foreach (@ports) {
			$fc_login_status{$host[0]}{$_} = $fc_connectivity_list{$_};
		}
	}

	return %fc_login_status;
}

=head2 connected_hosts

This method returns an array containing the configured names of all connected hosts.  Note that this method
does not check host connectivity and connected hosts in this instance should be taken as hosts whom have
been configured on this unit.

	my @host_list = $xiv->connected();
	print "The following hosts have been configured for this unit: ", join /, /, $host_list, "\n";

=cut

sub connected_hosts	{
	my ($self)	= @_;
	my @connected_hosts;
	my @host_list	= $self->host_list;

	foreach (@host_list) {
		my $host= (split /","/, $_)[0];
		$host	=~ s/^"//;
		push @connected_hosts, $host;
	}

	shift @connected_hosts;
	return @connected_hosts;
}

sub _xcli_execute	{
	my ($self,%args)= @_;
	my @result;
	$self->_check_args;
	defined $args{xcli_cmd}		or croak 'XCLI called with no arguments';
	my $xcli_arg	= "-s -u $self->{username} -p $self->{password} -m $self->{ip_address} $args{xcli_cmd} $args{xcli_args}";
	open my $conn, "$self->{xcli} $xcli_arg|"
					or croak 'Couldn\'t open connection to XCLI';
	while (<$conn>) {
		chomp;
		push @result, $_;
	}

	_field_check($result[0]) or undef @result;
	return @result;
}

sub _field_check	{
	my ($fields)	= @_;
	chomp $fields;
	defined $fields			or croak 'Fields not defined';
	$fields =~ /^["\w*",?]+/	or croak 'Fields do not conform to expected format';
	return 1;
}

sub _check_args		{
	my ($self)	= @_;
	defined $self->{ip_address}	or croak 'ip_address not defined';
	defined $self->{username}	or croak 'username not defined';
	defined $self->{password}	or croak 'password not defined';
	defined $self->{xcli}		or croak 'xcli not defined';
	return 1;
}

=head1 AUTHOR

Luke Poskitt, C<< <ltp at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-ibm-xcli at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IBM-XCLI>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc IBM::XCLI


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IBM-XCLI>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IBM-XCLI>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IBM-XCLI>

=item * Search CPAN

L<http://search.cpan.org/dist/IBM-XCLI/>

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Luke Poskitt.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;
