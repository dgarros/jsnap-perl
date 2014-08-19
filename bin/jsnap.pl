#!/volume/perl/bin/perl -w

use strict;
use warnings; 

my $lib_to_load;
BEGIN { 
    if ( defined $ENV{S3BU_DIR} ) { $lib_to_load = $ENV{S3BU_DIR} }  
    else { $lib_to_load = "/volume/labtools/lib/Testsuites/S3BU/lib"; } 
}
use lib '../lib';
use lib '/volume/labtools/lib';
use lib "$lib_to_load";

use Data::Dumper;
use File::Basename;
use Net::Netconf::Manager;
use Getopt::Long;
use JSNAP;

## Variable declaration
my %opt;
my $r;
my $conf; 
my %snaps;  ## Can be type LOCAL or REMOTE
my $need_device_access;

GetOptions( 't|target:s'    => \$opt{'target'},
            'l|login:s'     => \$opt{'login'},
            'p|password:s'  => \$opt{'password'},
            'c|conf:s'      => \$opt{'conf'},
            'snap:s'        => \@{$opt{'snap'}}, 
            'check:s'       => \@{$opt{'check'}}, 
            'snapcheck:s'   => \@{$opt{'snapcheck'}}, 
            'll:s'          => \$opt{'log-level'},
            'h|help'        => \$opt{'h'},
        );
            
## make sure a config file and a device name is provided
if ( not defined $opt{target} or not defined $opt{conf} ){
    print usage(); 
    exit;
}

## Make sure only one option is specified
die "At least one action (--snap, --check or --snapcheck ) need to be defined"          if ( ( not scalar @{$opt{snap}} ) and ( not scalar @{$opt{check}} ) and ( not scalar @{$opt{snapcheck}} ) );
die "All options : --snap, --snapcheck and --check are selected, only one is supported" if ( ( scalar @{$opt{snap}} ) and ( scalar @{$opt{check}} ) and ( scalar @{$opt{snapcheck}} ) );
die "Both --snap and --check option are selected, only one is supported"                if ( scalar @{$opt{snap}}     and scalar @{$opt{check}} );
die "Both --snap and --snapcheck option are selected, only one is supported"            if ( scalar @{$opt{snap}}     and scalar @{$opt{snapcheck}} );
die "Both --snapcheck and --check option are selected, only one is supported"           if ( scalar @{$opt{check}}    and scalar @{$opt{snapcheck}} ); 
      
## Assign default value if not defined
$opt{'log-level'}   = 'INFO'        if ( not defined $opt{'log-level'} );
$opt{'login'}       = 'root'        if ( not defined $opt{'login'} );  
$opt{'password'}    = 'Embe1mpls'   if ( not defined $opt{'password'} );

## Load configuration
$conf   = JSNAP::load_conf_file( $opt{'conf'} );

if ( scalar @{$opt{snap}} ) {
    ## Check size of SNAP
    die "Only one Snapshot name is needed for --snap" if( scalar @{$opt{snap}} != 1 ); 
    
    ## Setup the SNAPSHOT as remote
    $snaps{$opt{snap}[0]} = { type => 'REMOTE', results => {} };
    $need_device_access = 1;
}
elsif ( scalar @{$opt{snapcheck}} ) {
    
    ## Check size of SNAPCHECK
    die "Maximun of two Snapshot name are needed for --snapcheck" if( scalar @{$opt{snapcheck}} > 2 ); 
    
    ## If only one setup than its remote
    ## IF Two setup than first is local and second is remote
    if( scalar @{$opt{snapcheck}} == 1 ) {
        $snaps{'PRE'}   = { type => 'NONE', results => {} };
        $snaps{'POST'}  = { name => $opt{snapcheck}[0], type => 'REMOTE', results => {} };
    }
    elsif ( scalar @{$opt{snapcheck}} == 1 ) {
        $snaps{'PRE'}   = { name => $opt{snapcheck}[0], type => 'LOCAL',  results => {}};
        $snaps{'POST'}  = { name => $opt{snapcheck}[1], type => 'REMOTE', results => {}};
    } 
    $need_device_access = 1;
}
elsif ( scalar @{$opt{check}} ) {
    ## Check size of CHECK
    die "Maximun of two Snapshot name are needed for --check" if( scalar @{$opt{check}} > 2 ); 
    
    if ( scalar @{$opt{check}} == 2 ) {
        $snaps{'PRE'}   = { name => $opt{check}[0], type => 'LOCAL', pos => 'PRE',  results => {}};
        $snaps{'POST'}  = { name => $opt{check}[1], type => 'LOCAL', pos => 'POST', results => {}};
    }
    else {
        $snaps{'POST'}  = { name => $opt{check}[0], type => 'LOCAL', pos => 'POST', results => {}};
        $snaps{'PRE'}   = { type => 'NONE', results => {} };
    }
}
    
## -- Open netconf sessions to device if needed
if ( defined $need_device_access ) {
    
    print "Will open Netconf connection to $opt{target} .... "; 
    ## Open the Netconf connection
    $r = new Net::Netconf::Manager( 
            access 		=> 'ssh',
            login 		=> $opt{login},
            password	=> $opt{password},
            hostname 	=> $opt{target},
            port		=> 22,
        );
        
    if( not $r ) {
        print STDERR "Unable to connect to device \n";
        exit 1;
    } 
    
    print "DONE\n"; 
}

## -- Get list of all commands from configuration
my $commands = JSNAP::get_list_commands( conf => $conf );

## -- for each SNAPSHOT, retrieve main commands results 
foreach my $key ( keys %snaps ) {
    next if $snaps{$key}{type} eq 'NONE'; 
    
    if ( $snaps{$key}{type} eq 'REMOTE' ) {
        my $tmp_results = JSNAP::retrieve_commands_remote( snapname => $snaps{$key}{name}, commands => $commands, handle => $r );
        %{$snaps{$key}{results}} = ( %{$snaps{$key}{results}}, %{$tmp_results} ); 
        
        ## if name is defined and not empty, 
        ## -- save results locally
        if ( defined $snaps{$key}{name} and $snaps{$key}{name} ne '' ) {
            JSNAP::save_commands_local( target => $opt{target}, snapname => $snaps{$key}{name},  results => $tmp_results );
        }
    }
    elsif ( $snaps{$key}{type} eq 'LOCAL' ) {
        my $tmp_results = JSNAP::retrieve_commands_local( target => $opt{target}, snapname => $snaps{$key}{name}, commands => $commands  ); 
        %{$snaps{$key}{results}} = ( %{$snaps{$key}{results}}, %{$tmp_results} ); 
    } 
}

## -- For each SNAPSHOT, get additional commands (with-each) and retrieve results 
foreach my $key ( keys %snaps ) {
    next if $snaps{$key}{type} eq 'NONE'; 
    
    my $commands_more = JSNAP::get_list_commands_with_each( conf => $conf, results => $snaps{$key}{results} );
    
    ## -- if we have nothing to retrieve, go next
    next unless ( scalar @{$commands_more} );
    
    if ( $snaps{$key}{type} eq 'REMOTE' ) {
        my $tmp_results = JSNAP::retrieve_commands_remote( snapname => $snaps{$key}{name}, commands => $commands_more, handle => $r );
        %{$snaps{$key}{results}} = ( %{$snaps{$key}{results}}, %{$tmp_results} );
    
        ## if name is defined and not empty, 
        ## -- save results locally
        if ( defined $snaps{$key}{name} and $snaps{$key}{name} ne '' ) {
            JSNAP::save_commands_local( target => $opt{target}, snapname => $snaps{$key}{name},  results => $tmp_results );
        }            
    }
    elsif ( $snaps{$key}{type} eq 'LOCAL' ) {
        my $tmp_results = JSNAP::retrieve_commands_local( target => $opt{target}, snapname => $snaps{$key}{name}, commands => $commands  ); 
        %{$snaps{$key}{results}} = ( %{$snaps{$key}{results}}, %{$tmp_results} ); 
    }
}

## -- IF type = Remote and if name is defined, saved results to file


print "---\n\n";

### Execute Test On Screen
JSNAP::execute_yml_to_screen( snapshot => \%snaps, conf => $conf );

sub usage {

    print "Usage: $0 (--snap|--check|--snapcheck) [NAME1, NAME2] -t target -l login -p password -c config_file [ -ll LOG_LEVEL ]\n\n";
    exit 1;

}





