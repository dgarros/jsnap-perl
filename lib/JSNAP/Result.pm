  
package JSNAP::Result;

use Data::Dumper;

use Mouse;

has 'status'        => ( is  => 'ro', isa => 'Int', );
has 'data'          => ( is  => 'ro', isa => 'HashRef', );

has 'msg'           => ( is  => 'ro', isa => 'Str',  reader => 'get_msg', default => '' );
has 'failed_msg'    => ( is  => 'ro', isa => 'ArrayRef',  );

has 'nbr_match'     => ( is  => 'ro', isa => 'Int', reader => 'get_nbr_match',  default => 0 );
has 'nbr_failed'    => ( is  => 'ro', isa => 'Int', reader => 'get_nbr_failed', default => 0 );

sub BUILD {
    my $self = shift;
    
    $self->{nbr_match}  += $self->{data}{nbr_match}             if ( defined $self->{data}{nbr_match}     );
    $self->{nbr_failed} += $self->{data}{nbr_failed}            if ( defined $self->{data}{nbr_failed}    );
    push @{$self->{failed_msg}}, @{$self->{data}{failed_msg}}   if ( defined $self->{data}{failed_msg}    );
    
    return 1;
}

sub has_failed {
    my $self    = shift; 
           
    return 1 if ( defined $self->{status} and $self->{status} == 0 );
    return 0;
}

sub has_skipped {
    my $self    = shift; 
           
    return 1 if ( defined $self->{status} and $self->{status} == -1 );
    return 0;
}

sub has_passed {
    my $self    = shift; 
           
    return 1 if ( defined $self->{status} and $self->{status} == 1 );
    return 0;
}

sub get_failed_msgs {
    my $self    = shift;
    
    my @msgs; 
    foreach ( @{$self->{failed_msg}} ) {
        push @msgs, $_ ; 
    }
      
    return @msgs;
}

__PACKAGE__->meta->make_immutable();
no Mouse;
1;