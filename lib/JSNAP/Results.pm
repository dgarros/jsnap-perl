  
package JSNAP::Results;

use FAN::Core;
use Data::Dumper;

use Mouse;

has 'name'          => ( is  => 'ro', isa => 'Str' );

has 'results'       => ( is  => 'ro', isa => 'ArrayRef' );

has 'nbr_result'    => ( is  => 'ro', isa => 'Int', reader => 'get_nbr_result',         default => 0);
has 'nbr_skipped'   => ( is  => 'ro', isa => 'Int', reader => 'get_nbr_result_skipped', default => 0);
has 'nbr_failed'    => ( is  => 'ro', isa => 'Int', reader => 'get_nbr_result_failed',  default => 0);
has 'nbr_passed'    => ( is  => 'ro', isa => 'Int', reader => 'get_nbr_result_passed',  default => 0);

sub BUILD {
    my $self    = shift; 
                    
    return 1;
}

sub has_failed {
    my $self    = shift; 
           
    return 1 if ( $self->get_nbr_result_failed );
    return 0;
}

sub has_passed {
    my $self    = shift; 
           
    return 1 unless ( $self->get_nbr_result_failed );
    return 0;
}

sub add_result {
    my $self    = shift; 
    my $result  = shift;

    die "JSNAP::Results::add_result you must provide a result object" if ( ( not defined $result ) or ref $result ne 'JSNAP::Result' );
    
    ## Save the results object
    push @{$self->{results}}, $result;
    
    $self->{nbr_result}++;
    $self->{nbr_failed}++   if ( $result->has_failed );
    $self->{nbr_skipped}++  if ( $result->has_skipped );
    $self->{nbr_passed}++   if ( $result->has_passed );
    
    return 1;
}

sub get_failed_msgs {
    my $self    = shift; 
    
    my @msgs;
    
    foreach ( @{$self->{results}} ) {
        push @msgs, $_->get_failed_msgs;
    }

    return @msgs;
}

__PACKAGE__->meta->make_immutable();
no Mouse;

1;