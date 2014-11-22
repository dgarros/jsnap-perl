
package JSNAP;

use strict;

use Try::Tiny;
use Data::Dumper;
use File::Basename;
use Storable;
use XML::XPath; 
use XML::XPath::XMLParser; 
use YAML::Syck qw(LoadFile DumpFile);
use constant { TRUE => 1, FALSE => 0 };

our $dir    = "$ENV{HOME}/.jsnap";

sub execute {
    my %arg  = ( 
                operator    => undef,   
                msg_success => undef, 
                msg_failed  => undef, 
                @_ 
            );
 
    my $sub     = sub { eval  "$arg{'operator'}( \%arg )" };
    my ( $pass, $results )    = $sub->();
    
    if ( $@ ) {    
        printf(" \e[0;33m%-5s\e[m | An error occured while executing sub %s \n", 'WARN', "$arg{'operator'} .. ");
        printf(" \t %s: %s \n", "ERROR MSG", $@);
       
        return FALSE;
    }
    
    if ( $pass ) { printf(" \e[0;32m%-5s\e[m | %s %s \n", 'PASS', $arg{'msg_success'}, "($results->{'nbr_match'} match)" )  }
    else {
        printf(" \e[0;31m%-5s\e[m | %s %s \n", 'FAIL', $arg{'msg_success'}, "($results->{'nbr_match'} match / $results->{'nbr_failed'} failed)");
        
        my @failed_msg_list = build_failed_msg_list( $arg{'msg_failed'}, $results->{'failed'});
       
        foreach (@failed_msg_list) {
            print("\t$_\n");
        }
    }

    return 1;
}

#### 

sub execute_yml_test {
    my %arg  = ( test => undef, @_ ); 
          
    ## Re-initialize arguments
    ## Identify the operator
    ## extract operator && value
    ## Extract err msg and output
    $arg{'operator'}    = undef; 
    $arg{'element'}     = undef; 
    $arg{'value'}       = undef; 
    $arg{'msg_success'} = undef; 
    $arg{'msg_failed'}  = undef; 
    $arg{'output'}      = undef; 
    $arg{'min'}         = undef; 
    $arg{'max'}         = undef;    

    foreach my $key ( keys %{$arg{'test'}} ) {
        next if $key eq 'err';
        next if $key eq 'info';
        next if $key eq 'max';
        next if $key eq 'min';
        next if $key eq 'xml';
        next if $key eq 'xml2';
        next if $key eq 'iterate_on';
         
        $arg{'operator'} = validate_operator_name( $key );
        
        if ( not defined $arg{'operator'} ) {
            print "WARN | Operator $key is not valid\n";
            next;
        }
        
        ## Make a local copy of element_value and err_msg_output to avoid unexpected sharing arrayRef
        
        my @element_values = @{ $arg{'test'}->{$key} };
        
        $arg{'element'}     = shift @element_values;
        $arg{'value'}       = \@element_values;
        $arg{'msg_success'} = $arg{'test'}->{info};
        
        $arg{'min'} = $arg{'test'}->{min} if ( defined $arg{'test'}->{min} );
        $arg{'min'} = $arg{'test'}->{max} if ( defined $arg{'test'}->{max} );

        $arg{'xml'}         = $arg{'test'}->{xml};
        $arg{'xml2'}        = $arg{'test'}->{xml2};
        $arg{'iterate_on'}  = $arg{'test'}->{iterate_on};
        
        if ( defined $arg{'test'}->{err} ) {
            my @err_msg_output = @{ $arg{'test'}->{err} };
        
            $arg{'msg_failed'} = shift @err_msg_output;
            $arg{'output'}     = \@err_msg_output;
        }
        
        return JSNAP::execute( %arg );
    }
}

sub execute_yml_section_tests {
    my %arg     = (
        snapshot        => undef,
        tests           => undef,
        iterate_on      => undef,
        xml             => undef,
        xml2            => undef,
        prefix          => undef,
        info            => undef,
        @_ );
             
    foreach my $glo_test ( @{$arg{tests}} ) {
        
        ## Clone $test 
        my $test = Storable::dclone( $glo_test );
        
        ## Add iterate_on, XML and XML2 on the configuration
        $test->{iterate_on} = $arg{iterate_on};
        $test->{xml}        = $arg{xml};
        $test->{xml2}       = $arg{xml2};
        
        ## If prefix is defined, add the prefix before INFO and ERR Message
        if( defined $arg{prefix} and defined $test->{info} ) {
            my $tmp_info    = $test->{info};
            $test->{info}   = $arg{prefix}.' - '.$tmp_info;
        }
        
        if( defined $arg{prefix} and defined $test->{err}[0] ) {
            my @tmp_tests   = @{$test->{err}};
            $tmp_tests[0]   = $arg{prefix}.' - '.$tmp_tests[0];
            $test->{err}    = \@tmp_tests;
        }
        
        JSNAP::execute_yml_test( test => $test );
    }
}

sub execute_yml_section_with_each {
    my %arg     = (
        snapshot        => undef,
        with_each       => undef,
        iterate_on      => undef,
        xml             => undef,
        xml2            => undef,
        @_ );
             
    foreach my $with_each ( @{$arg{with_each}} ) {
        next if ( defined $with_each->{command} );
        
        ## -- Find the command with in each with_each section
        my $init_command = JSNAP::find_command_in_section( section => $arg{with_each} );
        
        ## -- Get the list of value from the initial command
        my $nodevalues  = $arg{xml}->find($arg{iterate_on}); 

        foreach my $nodevalue ( $nodevalues->get_nodelist ) {
            my $value = $nodevalue->string_value;
            
            ## -- Replace %s in the string by this value and store the new command
            my $tmp_cmd =  $init_command; 
            $tmp_cmd    =~ s/\%s/$value/g;
            
            ## -- Once find get the result of this command
            ## Pre-store XML results and make sure at least the result for POST is available
            if ( not defined $arg{snapshot}->{POST}{results}{$tmp_cmd} ) {
                print "ERROR - Command results not available for $arg{snapshot}->{POST}{name} - $tmp_cmd \n"; 
                next; 
            }
            
            my $PRE_xml; 
            my $POST_xml    = $arg{snapshot}{POST}{results}{$tmp_cmd};
            $PRE_xml        = $arg{snapshot}{POST}{results}{$tmp_cmd} if defined $arg{snapshot}->{PRE}{results}{$tmp_cmd};

            foreach my $iterate_block ( @{$arg{with_each}} ) {
                
                ## For each iterate block with a tests section
                if ( defined $iterate_block->{tests} ) {
                
                    JSNAP::execute_yml_section_tests(   iterate_on  => $iterate_block->{iterate},   
                                                        xml         => $POST_xml,
                                                        xml2        => $PRE_xml,
                                                        tests       => $iterate_block->{tests},
                                                        prefix      => $value,
                                                    );
                }
            }
        }
    }
}

sub execute_yml_to_screen {
    my %arg     = (
            snapshot    => undef,
            conf        => undef,
            @_ );
    
    ## For all Section
    # -- Defined in DO section and with value ea TRUE
    foreach my $section ( keys %{$arg{conf}} ) {
        next if ( $section eq 'do' );
        next if ( $section eq 'variables' );
        next if ( defined $arg{conf}->{do} and ( not defined $arg{conf}->{do}{$section} ) );
        next if ( defined $arg{conf}->{do} and ( $arg{conf}->{do}{$section} !~ /true/i ) );
        
        ## Find the command for this section
        my $command = JSNAP::find_command_in_section( section => $arg{conf}->{$section} );

        ## Pre-store XML results and make sure at least the result for POST is available
        if ( not defined $arg{snapshot}->{POST}{results}{$command} ) {
            print "ERROR - Command results not available for $arg{snapshot}->{POST}{name} - $command \n"; 
            next; 
        }
        
        my $PRE_xml; 
        my $POST_xml    = $arg{snapshot}{POST}{results}{$command};
        $PRE_xml        = $arg{snapshot}{POST}{results}{$command} if defined $arg{snapshot}->{PRE}{results}{$command};

        foreach my $iterate_block ( @{$arg{conf}->{$section}} ) {
            
            ## For each iterate block with a tests section
            if ( defined $iterate_block->{tests} ) {
            
                JSNAP::execute_yml_section_tests(   iterate_on  => $iterate_block->{iterate},
                                                    info        => $iterate_block->{info},
                                                    xml         => $POST_xml,
                                                    xml2        => $PRE_xml,
                                                    tests       => $iterate_block->{tests},
                                                    snapshot    => $arg{snapshot},
                                                );
            }
            
            ## For each iterate block with a with-each
            if ( defined $iterate_block->{'with-each'} ) {
                
                JSNAP::execute_yml_section_with_each(   iterate_on  => $iterate_block->{iterate},
                                                        info        => $iterate_block->{info},
                                                        xml         => $POST_xml,
                                                        xml2        => $PRE_xml,
                                                        with_each   => $iterate_block->{'with-each'},
                                                        snapshot    => $arg{snapshot},
                                                    );
            }
        }
    }
}

#### Operator Direct, Only one XML needed       ####

sub element_exists {
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## NOT NEEDED FOR THIS TEST
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP exists: Mandatory parameter 'xml' is missing"        if ( ! defined $arg{'xml'} );
    die "JSNAP exists: Mandatory parameter 'iterate_on' is missing" if ( ! defined $arg{'iterate_on'} );
    die "JSNAP exists: Mandatory parameter 'element' is missing"    if ( ! defined $arg{'element'} );
    
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) {
        my $ret = clean_string( $item->find( $arg{'element'} ) ); 
        
        ## if not present, than collect all output information
        unless ( $ret ){
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        $results{'nbr_match'}++;
    }
    
    ## Return FALSE, 
    ##      if number of failed is not 0
    ##      if the number of match is lower than min_res
    ##      if the number of match is higher than max_res
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    
    ## Return True otherwise
    return ( TRUE,  \%results );
}  

sub not_exists {
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## NOT NEEDED FOR THIS TEST
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP not_exists: Mandatory parameter 'xml' is missing"        if ( ! defined $arg{'xml'} );
    die "JSNAP not_exists: Mandatory parameter 'iterate_on' is missing" if ( ! defined $arg{'iterate_on'} );
    die "JSNAP not_exists: Mandatory parameter 'element' is missing"    if ( ! defined $arg{'element'} );
    
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) {
        my $ret = clean_string( $item->find( $arg{'element'} ) ); 

        ## if present, than collect all output information
        if ( $ret ){        
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        $results{'nbr_match'}++;
    }
    
    ## Return FALSE, 
    ##      if number of failed is not 0
    ##      if the number of match is lower than min_res
    ##      if the number of match is higher than max_res
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    
    ## Return True otherwise
    return ( TRUE,  \%results );
}  

sub is_equal {
		
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## mandatory, XML element value or string to check
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will fail if no match
            max         => undef,   ## optional, define a maximum number of results expected, will fail if exceed
            @_ );

    die "JSNAP is_equal: Mandatory parameter 'xml' is missing"        if ( not defined $arg{'xml'} );
    die "JSNAP is_equal: Mandatory parameter 'iterate_on' is missing" if ( not defined $arg{'iterate_on'} );
    die "JSNAP is_equal: Mandatory parameter 'element' is missing"    if ( not defined $arg{'element'} );
    #xml element to test
    die "JSNAP is_equal: Mandatory parameter 'value' is missing"      if ( not defined $arg{'value'} );
    die "JSNAP is_equal: Parameter 'value' has to be a Ref ARRAY"     if ( ref $arg{'value'} ne 'ARRAY' );
    die "JSNAP is_equal: Parameter 'value' size has to be one"        if ( scalar @{$arg{'value'}} != 1 );
    #base value used for doing less than check

    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});

    ## Initiate the structure that will be returned
    my %results = init_result_hash();  
	
    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) {
        my $temp    = clean_string( $item->findvalue( $arg{'element'} ) );
      
        my $do_fail = undef;
        
        if ( defined get_numeric_part( $temp ) ) 
        {
            ## input value is a numeric, doing numeric check
            $do_fail = 1    if ( get_numeric_part($temp) != get_numeric_part($arg{'value'}[0]) );
        }
        else {
            ## doing string check
            #with regard to case sensitive case converting all characters to upper case one 
             $do_fail = 1   if ( uc($temp) ne uc($arg{'value'}[0]) );
        }
        
        ## if present, then collect all output information
        if ( $do_fail ){
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        
        $results{'nbr_match'}++;       
    } 

    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    
	return ( TRUE,  \%results );
} 

sub not_equal {

    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## mandatory, XML element value or string to check
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,   ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP not_equal: Mandatory parameter 'xml' is missing"         if ( not defined $arg{'xml'} );
    die "JSNAP not_equal: Mandatory parameter 'iterate_on' is missing"  if ( not defined $arg{'iterate_on'} );
    die "JSNAP not_equal: Mandatory parameter 'element' is missing"     if ( not defined $arg{'element'} );
    die "JSNAP not_equal: Mandatory parameter 'value' is missing"       if ( not defined $arg{'value'} );
    die "JSNAP not_equal: Parameter 'value' has to be a Ref ARRAY"      if ( ref $arg{'value'} ne 'ARRAY' );
    die "JSNAP not_equal: Parameter 'value' size has to be one"         if ( scalar @{$arg{'value'}} != 1 );
    
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});

    ## Initiate the structure that will be returned
    my %results = init_result_hash();

    #From the obtained child node XML element get the value(either its a numeric or string) and check the condition is-equal, not-equal

    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) {
        my $temp    = clean_string( $item->findvalue( $arg{'element'} ) );

        my $do_fail = undef;
        
        if ( defined get_numeric_part( $temp ) ) {
            ## input value is a numeric, doing numeric check
            $do_fail = 1    if ( get_numeric_part($temp) == get_numeric_part($arg{'value'}[0]) );
        }
        else {
            ## doing string check
            #with regard to case sensitive case converting all characters to upper case one 
             $do_fail = 1   if ( uc($temp) eq uc($arg{'value'}[0]) );
        }
        
        ## if present, than collect all output information
        if ( $do_fail ){
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        
        $results{'nbr_match'}++;       
    } 

    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );

}
 
sub contains {

    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## mandatory
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,   ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP contains: Mandatory parameter 'xml' is missing"        if ( ! defined $arg{'xml'} );
    die "JSNAP contains: Mandatory parameter 'iterate_on' is missing" if ( ! defined $arg{'iterate_on'} );
    die "JSNAP contains: Mandatory parameter 'element' is missing"    if ( ! defined $arg{'element'} );
    die "JSNAP contains: Mandatory parameter 'value' is missing"      if ( ! defined $arg{'value'} );
 
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    #iterate to the parent node and find the child node and value. Read the whole value into a variable or array ??, here the provided value need to check
    #against the readed value, whether it contains in the readed value or not ?
    #provided value might be part of the readed value or its the same one as the readed value  good example is show version

    my $ret = "";
      
    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) { 
        $ret    = clean_string( $item->findvalue( $arg{'element'} ) ); 
        
        if ($ret !~ /$arg{'value'}/) {
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }

        $results{'nbr_match'}++;
    } 
    
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );
} 

sub is_in {
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => [],      ## At least one element is mandatory
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP is_in: Mandatory parameter 'xml' is missing"         if ( not defined $arg{'xml'} );
    die "JSNAP is_in: Mandatory parameter 'iterate_on' is missing"  if ( not defined $arg{'iterate_on'} );
    die "JSNAP is_in: Mandatory parameter 'element' is missing"     if ( not defined $arg{'element'} );
    die "JSNAP is_in: Mandatory parameter 'value' is missing"       if ( scalar @{$arg{'value'}} == 0 );
    die "JSNAP is_in: Parameter 'value' has to be a Ref ARRAY"      if ( ref $arg{'value'} ne 'ARRAY' );
    
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    my %results = init_result_hash();
    
    my @valuearray = @{$arg{'value'}}; 
    my $arrin = 0;
    my $arrlen = @valuearray;
         
    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) {
        my $ret = clean_string( $item->findvalue( $arg{'element'} ) ); 
        
        my $do_match = undef; 
        foreach my $value ( @{$arg{'value'}} ) {
            $do_match = 1 if ( $ret eq $value );
        }
        
        $results{'nbr_match'}++;
        
        next if ( $do_match );
        
        push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
        $results{'nbr_failed'}++;
    } 
    
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    
    return ( TRUE,  \%results );

}  

sub not_in {
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => [],       ## atleast one element is mandatory
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP not_in: Mandatory parameter 'xml' is missing"        if ( not defined $arg{'xml'} );
    die "JSNAP not_in: Mandatory parameter 'iterate_on' is missing" if ( not defined $arg{'iterate_on'} );
    die "JSNAP not_in: Mandatory parameter 'element' is missing"    if ( not defined $arg{'element'} );
    die "JSNAP not_in: Mandatory parameter 'value' is missing"      if ( not defined $arg{'value'} );
    die "JSNAP not_in: Parameter 'value' has to be a Ref ARRAY"     if ( ref $arg{'value'} ne 'ARRAY' );
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
    
    my %results = init_result_hash();
   
    foreach my $item ( $xp->findnodes( $arg{'iterate_on'} ) ) {
        my $ret = clean_string( $item->findvalue( $arg{'element'} ) );
        
        foreach my $value ( @{$arg{'value'}} ) {
            next if( $ret ne $value );
        
            ## If Ret is equal
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
            last;
        }

        $results{'nbr_match'}++; 
    }
 
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( defined $arg{'min'} && $arg{'min'} > $results{'nbr_match'} );
    return ( FALSE, \%results ) if ( defined $arg{'max'} && $arg{'max'} < $results{'nbr_match'} );
    
    return ( TRUE,  \%results );
}

sub in_range {
    my %arg  = ( 
                xml         => undef,   ## mandatory
                iterate_on  => undef,   ## mandatory
                element     => undef,   ## mandatory, XML element to test
                value       => undef,   ## optional
                output      => [],      ## optional
                startrange  => undef,   ## Mandatory
                endrange    => undef,   ## Mandatory
                min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
                max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
                @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP in_range: Mandatory parameter 'xml' is missing"          if ( not defined $arg{'xml'} );
    die "JSNAP in_range: Mandatory parameter 'iterate_on' is missing"   if ( not defined $arg{'iterate_on'} );
    die "JSNAP in_range: Mandatory parameter 'element' is missing"      if ( not defined $arg{'element'} );
    die "JSNAP in_range: Mandatory parameter 'value' is missing"        if ( not defined $arg{'value'} );
    die "JSNAP in_range: Parameter 'Value' must have a size of 2"       if ( scalar @{$arg{'value'}} != 2 );
    
    my $start_range = get_numeric_part($arg{'value'}[0]);
    my $end_range   = get_numeric_part($arg{'value'}[1]);
    die "JSNAP not_in_range: Start range must be numeric"               if ( not defined $start_range );
    die "JSNAP not_in_range: End range must be numeric"                 if ( not defined $end_range );
     
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});

    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    my $nodeset = $xp->find($arg{'iterate_on'}); 
  
    foreach my $item ($nodeset->get_nodelist) {
        my $value   = clean_string( $item->findvalue( $arg{'element'} ) );
        my $number  = get_numeric_part( $value );
        
        ## Check if value is defined and if value has a number
        next if ( not defined $number );
        
        unless (( $value > $start_range ) and ( $value < $end_range )) {
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        
        $results{'nbr_match'}++;
    } 

    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );
}

sub not_in_range {
 my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## mandatory
            output      => [],      ## optional
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP not_in_range: Mandatory parameter 'xml' is missing"          if ( not defined $arg{'xml'} );
    die "JSNAP not_in_range: Mandatory parameter 'iterate_on' is missing"   if ( not defined $arg{'iterate_on'} );
    die "JSNAP not_in_range: Mandatory parameter 'element' is missing"      if ( not defined $arg{'element'} );
    die "JSNAP not_in_range: Mandatory parameter 'value' is missing"        if ( not defined $arg{'value'} );
    die "JSNAP not_in_range: Parameter 'value' must have a size of 2"       if ( scalar @{$arg{'value'}} != 2 );
    
    my $start_range = get_numeric_part($arg{'value'}[0]);
    my $end_range   = get_numeric_part($arg{'value'}[1]);
    die "JSNAP not_in_range: Start range must be numeric"                   if ( not defined $start_range );
    die "JSNAP not_in_range: End range must be numeric"                     if ( not defined $end_range );
    
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    my $nodeset = $xp->find($arg{'iterate_on'}); 
    
    foreach my $item ($nodeset->get_nodelist) {
  
        my $value   = clean_string( $item->findvalue( $arg{'element'} ) );
        my $number  = get_numeric_part( $value );
        
        ## Check if value is defined and if value has a number
        next if ( not defined $number );
        
        if ( ( $number > $start_range ) and ( $number < $end_range )) {
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        
        $results{'nbr_match'}++;
    } 

    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );

} 

sub greater_than {
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => undef,   ## mandatory
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP greater_than: Mandatory parameter 'xml' is missing"              if ( not defined $arg{'xml'} );
    die "JSNAP greater_than: Mandatory parameter 'iterate_on' is missing"       if ( not defined $arg{'iterate_on'} );
    die "JSNAP greater_than: Mandatory parameter 'element' is missing"          if ( not defined $arg{'element'} );
    die "JSNAP greater_than: Mandatory parameter 'value' is missing"            if ( not defined $arg{'value'} );
    die "JSNAP greater_than: Parameter 'value' has to be a Ref ARRAY"           if ( ref $arg{'value'} ne 'ARRAY' );
    die "JSNAP greater_than: Parameter 'value' size has to be one"              if ( scalar @{$arg{'value'}} != 1 );
    
    $arg{'value'} = get_numeric_part($arg{'value'}[0]);      
    die "JSNAP greater_than: Parameter 'value' must be numeric : $arg{'value'}" if ( not defined $arg{'value'} );
    
    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});

    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    my $nodeset = $xp->find($arg{'iterate_on'}); 

    foreach my $item ($nodeset->get_nodelist) {  
        my $value   = clean_string( $item->findvalue( $arg{'element'} ) );
        my $number  = get_numeric_part( $value );
        
        ## Check if value is defined and if value has a number
        next if ( not defined $number );

        if( $number < $arg{'value'} ) {         
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        $results{'nbr_match'}++;
    } 

    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );
} 

sub less_than { 
    my %arg  = ( 
            xml         => undef,   ## mandatory
            iterate_on  => undef,   ## mandatory
            element     => undef,   ## mandatory, XML element to test
            value       => [],      ## mandatory
            output      => [],      ## optional, String or Array of values to pass as an output if it failed
            min         => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP less_than: Mandatory parameter 'xml' is missing"                 if ( not defined $arg{'xml'} );
    die "JSNAP less_than: Mandatory parameter 'iterate_on' is missing"          if ( not defined $arg{'iterate_on'} );
    die "JSNAP less_than: Mandatory parameter 'element' is missing"             if ( not defined $arg{'element'} );
    die "JSNAP less_than: Mandatory parameter 'value' is missing"               if ( not defined $arg{'value'} );
    die "JSNAP not_equal: Parameter 'value' has to be a Ref ARRAY"              if ( ref $arg{'value'} ne 'ARRAY' );
    die "JSNAP not_equal: Parameter 'value' size has to be one"                 if ( scalar @{$arg{'value'}} != 1 );
    
    $arg{'value'} = get_numeric_part($arg{'value'}[0]);    
    die "JSNAP greater_than: Parameter 'value' must be numeric : $arg{'value'}" if ( not defined $arg{'value'} );

    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'} );
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash(); 
   
    my $nodeset = $xp->find( $arg{'iterate_on'} ); # find all paragraphs

    foreach my $item ( $nodeset->get_nodelist ) {
        my $value   = clean_string( $item->findvalue( $arg{'element'} ) ) ;
        my $number  = get_numeric_part( $value );
    
        ## Check if value is defined and if value has a number
        next if ( not defined $number );

        if ( $number > $arg{'value'} ) {
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }
        
        $results{'nbr_match'}++;
    } 

    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    return ( TRUE,  \%results );
} 

sub all_same {
    my %arg  = ( 
            xml         => undef,       ## mandatory
            iterate_on  => undef,       ## mandatory
            element     => undef,       ## mandatory, XML element to test
            value       => [],          ## optional, other xml element with value like interface-name=ae19.0
            output      => [],          ## optional, String or Array of values to pass as an output if it failed
            min         => 1,           ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,       ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP all_same: Mandatory parameter 'xml' is missing"        if ( ! defined $arg{'xml'} );
    die "JSNAP all_same: Mandatory parameter 'iterate_on' is missing" if ( ! defined $arg{'iterate_on'} );
    die "JSNAP all_same: Mandatory parameter 'element' is missing"    if ( ! defined $arg{'element'} );

    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    my %results = init_result_hash();
    
    my $base_value  = undef;
    my $is_numeric  = undef;
    
    ## If value is defined, use it to defined the base VALUE
    if( scalar @{$arg{'value'}} ) {
        my $base_xpath  = $arg{'iterate_on'}.$arg{'value'}[0].'/'.$arg{'element'};
        $base_value     = clean_string( $xp->findvalue( $base_xpath ) );
        $is_numeric     = 1 if ( defined get_numeric_part( $base_value ) );
    }

    foreach my $item ($xp->findnodes($arg{'iterate_on'})) {
        my $element = clean_string( $item->findvalue( $arg{'element'} ) );
        $results{'nbr_match'}++;
        
        if ( not defined $base_value ) {
            $base_value = $element;
            $is_numeric = 1 if ( defined get_numeric_part( $base_value ) );
            next;
        }

        my $do_fail = undef;
        
        if ( $is_numeric ) {
            $do_fail = 1    if ( get_numeric_part($element) != get_numeric_part($base_value) );
        }
        else {
            $do_fail = 1   if ( uc($element) ne uc($base_value) );
        }
       
        ## if present, then collect all output information
        if ( $do_fail ) {
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        }             
    }  
           
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    return ( TRUE,  \%results );
} 

sub same_nbr {
    my %arg  = ( 
            xml         => undef,       ## mandatory
            iterate_on  => undef,       ## mandatory
            element     => undef,       ## mandatory, XML element to test
            value       => [],          ## optional, other xml element with value like interface-name=ae19.0
            output      => [],          ## optional, String or Array of values to pass as an output if it failed
            min         => 1,           ## optional, define a minimum number of results expected, will failed if not match
            max         => undef,       ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP same_nbr: Mandatory parameter 'xml' is missing"        if ( ! defined $arg{'xml'} );
    die "JSNAP same_nbr: Mandatory parameter 'iterate_on' is missing" if ( ! defined $arg{'iterate_on'} );
    die "JSNAP same_nbr: Mandatory parameter 'element' is missing"    if ( ! defined $arg{'element'} );

    my $xp = get_xpath_obj_or_die( (caller(0))[3], $arg{'xml'});
	
    my %results = init_result_hash();
    
    my $nbr_child   = undef;
    
    ## If value is defined, use it to defined the number of match expected
    $nbr_child = $arg{'value'}[0] if ( scalar @{$arg{'value'}} );
    
    foreach my $item ($xp->findnodes( $arg{'iterate_on'} )) {
        my @entries     = $item->findnodes( $arg{'element'} );    
        my $nbr_entries = scalar @entries;
        
        $results{'nbr_match'}++;
        
        if ( not defined $nbr_child ) {
            $nbr_child = $nbr_entries;
            next;
        }
        
        ## if number don't match, then collect all output information
        if ( $nbr_entries != $nbr_child ) {
            push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
            $results{'nbr_failed'}++;
        } 
    }  
           
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    return ( TRUE,  \%results );
} 

#### Operator by comparison, Two XML needed #### 

sub list_not_less {
    
    my %arg  = ( 
            xml            => undef,   #mandatory,xml of the first file
            xml2            => undef,   #mandatory,xml of the second file
            iterate_on      => undef,   ## mandatory
            id              => undef,      ## mandatory, Examples like name of the interface or ospf interface-name etc.,
            output          => [],      ## optional, String or Array of values to pass as an output if it failed
            min             => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max             => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

	#print Dumper \%arg;
    ## make sure that all mandatory parameter are present
    die "JSNAP list_not_less : Mandatory parameter 'xml1' is missing"          if ( ! defined $arg{'xml'} );
    die "JSNAP list_not_less : Mandatory parameter 'xml2' is missing"          if ( ! defined $arg{'xml2'} );
    die "JSNAP list_not_less : Mandatory parameter 'iterate_on' is missing"    if ( ! defined $arg{'iterate_on'} );
    die "JSNAP list_not_less : Mandatory parameter 'id' is missing"            if ( ! defined $arg{'id'} );
    
    my $xp1 = undef;
    
    try {	
        $xp1 = XML::XPath->new( xml => clean_xml_response( $arg{'xml'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml1 data provided";
    };
	
    my $xp2 = undef;
    
    try {
        $xp2 = XML::XPath->new( xml => clean_xml_response( $arg{'xml2'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml2 data provided";
    };
	
	## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    my $idret = "";
	
    foreach my $item ( $xp1->findnodes( $arg{'iterate_on'} ) ) { 
        $idret = $item->find( $arg{'id'} )->to_literal; 
        $results{'nbr_match'}++;
        
        if( $idret ) {
		
		     my $xpath2expr =  $arg{'iterate_on'}."[".$arg{'id'}."="."'".$idret."']" ;
			
			if ( not $xp2->find($xpath2expr) ) {                            
			    #my $temp = $xp2->find($xpath2expr);
				#print $temp;
                push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
                $results{'nbr_failed'}++;
            }

		}           
        
	}
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    return ( TRUE,  \%results );
}

sub list_not_more {

my %arg  = ( 
            xml            => undef,   #mandatory,xml of the first file
            xml2            => undef,   #mandatory,xml of the second file
            iterate_on      => undef,   ## mandatory
            id              => undef,      ## mandatory, Examples like name of the interface or ospf interface-name etc.,
            output          => [],      ## optional, String or Array of values to pass as an output if it failed
            min             => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max             => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP list_not_more: Mandatory parameter 'xml1' is missing"           if ( ! defined $arg{'xml'} );
    die "JSNAP list_not_more: Mandatory parameter 'xml2' is missing"          if ( ! defined $arg{'xml2'} );
    die "JSNAP list_not_more: Mandatory parameter 'iterate_on' is missing"    if ( ! defined $arg{'iterate_on'} );
    die "JSNAP list_not_more: Mandatory parameter 'id' is missing"            if ( ! defined $arg{'id'} );
    
    my $xp1 = undef;
    
    try {
        $xp1 = XML::XPath->new( xml => clean_xml_response( $arg{'xml'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml1 data provided";
    };
	
    my $xp2 = undef;
    
    try {
        $xp2 = XML::XPath->new( xml => clean_xml_response( $arg{'xml2'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml2 data provided";
    };
	
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
    
    my $idret = "";
    foreach my $item ( $xp2->findnodes( $arg{'iterate_on'} ) ) { 
        $idret = $item->find( $arg{'id'} )->to_literal; 
    
        $results{'nbr_match'}++;
 
        if( $idret ) {
		
		     my $xpath1expr =  $arg{'iterate_on'}."[".$arg{'id'}."="."'".$idret."']" ;
			
			if ( not $xp1->find($xpath1expr) ) {                            
                push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
                $results{'nbr_failed'}++;
            }

		}           
        
	}
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );
    return ( TRUE,  \%results );
    
} 

sub no_diff {

    my %arg  = ( 
            xml             => undef,   #mandatory,xml of the first file
            xml2            => undef,   #mandatory,xml of the second file
            iterate_on      => undef,   ## mandatory
            id              => undef,   ## mandatory, Examples like name of the interface or ospf interface-name etc.,
            element_array   => [],      ## mandatory, XML elements whose values that need to be finally checked in both the snapshots
            output          => [],      ## optional, String or Array of values to pass as an output if it failed
            min             => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max             => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );

    ## make sure that all mandatory parameter are present
    die "JSNAP no_diff: Mandatory parameter 'xml1' is missing"          if ( ! defined $arg{'xml'} );
    die "JSNAP no_diff: Mandatory parameter 'xml2' is missing"          if ( ! defined $arg{'xml2'} );
    die "JSNAP no_diff: Mandatory parameter 'iterate_on' is missing"    if ( ! defined $arg{'iterate_on'} );
    die "JSNAP no_diff: Mandatory parameter 'id' is missing"            if ( ! defined $arg{'id'} );
    die "JSNAP no_diff: Mandatory parameter 'element_array' is missing" if ( ! defined $arg{'element_array'}->[0] );
    
    my $xp1 = undef;
    
    try {
        $xp1 = XML::XPath->new( xml => clean_xml_response( $arg{'xml'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml1 data provided";
    };
	
    my $xp2 = undef;
    
    try {
        $xp2 = XML::XPath->new( xml => clean_xml_response( $arg{'xml2'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml2 data provided";
    };
	
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
   
    my @elements = @{$arg{'element_array'}}; 
   
    my $arrin = 0;
    my $arrlen = @elements;
   

    my $idret = "";
    foreach my $item ( $xp1->findnodes( $arg{'iterate_on'} ) ) { 
        $idret = $item->find( $arg{'id'} )->to_literal; 
    
        $results{'nbr_match'}++;
 
        if( $idret ) {
           
            for( $arrin=0;$arrin < $arrlen;$arrin++) {
                my $ret = $item->find( $elements[$arrin] )->to_literal;
				print $$ret; print"\n";
                     
                if($ret) {
                         
                    my $xpath2expr =  $arg{'iterate_on'}."[".$arg{'id'}."="."'".$idret."'"." and ".$elements[$arrin]."="."'".$ret."'"."]"."/".$elements[$arrin];
                      
                    my $f2elevalue = $xp2->findvalue($xpath2expr)->to_literal; 
                                             
                    if ($ret ne $f2elevalue){
					                                 
                        push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
                        $results{'nbr_failed'}++;
                    }           
                }
            } 
        }
    }       
                               
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );
}

sub delta {

my %arg  = ( 
            xml              => undef,   #mandatory,xml of the first file
            xml2             => undef,   #mandatory,xml of the second file
            iterate_on       => undef,   ## mandatory
            id               => undef,   ## mandatory, Examples like name of the interface or ospf interface-name etc.,
            element_array    => [],      ## mandatory, XML elements whose values that need to be finally checked in both the snapshots
			delta_value      => undef,   ## mandatory, Delta value.
			output           => [],      ## optional, String or Array of values to pass as an output if it failed
            min              => 1,       ## optional, define a minimum number of results expected, will failed if not match
            max              => undef,   ## optional, define a maximum number of results expected, will failed if exceed
            @_ );
			
	
    
    ## make sure that all mandatory parameter are present
    die "JSNAP delta: Mandatory parameter 'xml1' is missing"          if ( ! defined $arg{'xml'} );
    die "JSNAP delta: Mandatory parameter 'xml2' is missing"          if ( ! defined $arg{'xml2'} );
    die "JSNAP delta: Mandatory parameter 'iterate_on' is missing"    if ( ! defined $arg{'iterate_on'} );
    die "JSNAP delta: Mandatory parameter 'id' is missing"            if ( ! defined $arg{'id'} );
    die "JSNAP delta: Mandatory parameter 'element_array' is missing" if ( ! defined $arg{'element_array'}->[0] );
	die "JSNAP delta: Mandatory parameter 'id' is missing"            if ( ! defined $arg{'delta_value'} );
    
    my $xp1 = undef;
    
    try {
        $xp1 = XML::XPath->new( xml => clean_xml_response( $arg{'xml'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml1 data provided";
    };
	
    my $xp2 = undef;
    
    try {
        $xp2 = XML::XPath->new( xml => clean_xml_response( $arg{'xml2'} ) ); 
    }
    catch {
        die "JSNAP no_diff: Unable to process the xml2 data provided";
    };
	
	
    ## Initiate the structure that will be returned
    my %results = init_result_hash();
   
    my @elements = @{$arg{'element_array'}}; 
   
    my $arrin = 0;
	my $arrlen = @elements;
	my $temp = 0;
	
    	
    my $idret = "";
    foreach my $item ( $xp1->findnodes( $arg{'iterate_on'} ) ) { 
        $idret = $item->find( $arg{'id'} )->string_value; 
		print Dumper $idret;
        
         
        $results{'nbr_match'}++;
 
        if( $idret ) {
           
		   for( $arrin=0;$arrin < $arrlen;$arrin++) {
		        my $ret = $item->find( $elements[$arrin] )->string_value;
								                     
                if($ret) {
                    			
					my $xpath1expr =  $arg{'iterate_on'}."[".$arg{'id'}."="."'".$idret."']/".$elements[$arrin] ;
					my $f2elevalue = $xp2->findvalue($xpath1expr)->string_value;
					
					 if ( $arg{'delta_value'} =~ /%/ ) {
                       
	                   my $delta_per = get_numeric_part_delta( $arg{'delta_value'} );  
					   my $ret =  (($ret * $delta_per)/100);
					   					   
                    }
	                                    
                    if ( $arg{'delta_value'} =~ /\+/ ) {
                      
                         
						 my $delta_plus = get_numeric_part_delta( $arg{'delta_value'} );
						 					 
                         if ( $f2elevalue >  ( $ret + $delta_plus )){
                             $temp ++;                              
                            }
					}	
                    elsif( $arg{'delta_value'} =~ /-/ ) {
					    						 
					     my $delta_minus = get_numeric_part_delta( $arg{'delta_value'} );
                         if ( $f2elevalue <  ( $ret - $delta_minus ) ){
                             $temp++;  
                            } 
					     
					}
                    else {
					       				   
                          if ( ( $f2elevalue >  ($ret + $arg{'delta_value'} ) ) || ( $f2elevalue < ( $ret - $arg{'delta_value'} ))) {
                             print "abc1";						  
                             $temp++;
                            }                            
                    }
                     if ( $temp ) {
                         
                         		push @{$results{'failed'}}, collect_output_on_fail( index => $results{'nbr_match'}, item => $item, output => $arg{'output'} );
                                $results{'nbr_failed'}++;				 
                     }        
                 }   							 
                
            } 
        }
    }       
                               
    return ( FALSE, \%results ) if ( $results{'nbr_failed'} != 0 );
    return ( FALSE, \%results ) if ( (defined $arg{'min'}) && ( $arg{'min'} > $results{'nbr_match'} ) );
    return ( FALSE, \%results ) if ( (defined $arg{'max'}) && ( $arg{'max'} < $results{'nbr_match'} ) );

    return ( TRUE,  \%results );
} 

#############################

sub get_xpath_obj_or_die {
    my $subroutine  = shift;
    my $xml         = shift;
    
    ## Check if XML is already an XML::Xpath obj or not
    my $type = ref $xml; 
    return $xml if ( $type eq 'XML::XPath' );
    
    my $xp;
    
    try {
        $xp = XML::XPath->new( xml => clean_xml_response( $xml ) ); 
    }
    catch {
        die "$subroutine: Unable to process the xml data provided";
    };
    
    return $xp;
}

sub clean_xml_response {
    my $xml = shift;
    
    (my $before1, my $after1) = split(/\<\/rpc-reply\>/, $xml);
    $xml = $before1.'</rpc-reply>'; 
    
    (my $before2, my $after2) = split(/\<rpc-reply/, $xml);
    $xml = '<rpc-reply'.$after2;
   
    return $xml;
}

sub clean_string {
    my $str = shift;

    ## Remove All Carriage return
    $str =~ s/\r|\n//g;
   
    ## Remove Unused Space  Before and After
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    
    return $str;

}

sub collect_output_on_fail {
    my %arg     = ( index => undef, item => undef, output => [],  @_ );
    
    my @item_output_info;
    
    @item_output_info = $arg{'index'};
    
    ## For each variable name in the output array
    foreach  my $output ( @{ $arg{'output'} } ) {
        my $value =  $arg{'item'}->find( $output );
        
        if ( $value ) { push @item_output_info, clean_string ( $value->string_value) }
        else {          push @item_output_info, 'Not Found'  }
    }
            
    return \@item_output_info;
}

sub get_numeric_part {
    my $number  = shift; 
    
    return undef if ( not defined $number );
	return undef if ( $number !~ /^[0-9]+(?:\.[0-9]+)?/ );
   
    my ( $first_match )  = $number =~ m/^[0-9]+(?:\.[0-9]+)?/sg;
    
    return $first_match ;
}

sub get_numeric_part_delta {
    my $number  = shift; 
    
    return undef if ( not defined $number );
	     
    my ( $first_match )  = $number =~ m/(\d+)/;
	#print $first_match;
	print"\n";
    return $first_match ;
}

#############################  

sub load_conf_file {
    my $conf_file   = shift;
    my $deep        = shift; 
   
    ## Try if the configuration file exist
    unless (-e $conf_file) {
        print "WARN, Unable to access configuration $conf_file, File Doesn't Exist!\n";
        return {};
    }
    
    ## Identify location of the file
    my $dirname = dirname($conf_file);
    my $conf    = LoadFile( $conf_file );

    ## Keep control of how deep the recursion is for this file
    # $deep = 1 unless defined $deep; 
    
    ## Search for any Import section
    if( defined $conf->{'import'} ) {
          
        foreach my $c ( @{$conf->{'import'}} ) {
        
            # die "A loop of Import have been detected" if ( $deep >= 5 );
            my $import = JSNAP::load_conf_file( $dirname.'/'.$c );
 
            ## Merged imported config into main config
            my %merged; 
            %merged = ( %{$conf}, %{$import} ); 
            $conf   = \%merged;
        }

        delete $conf->{'import'};
    }
    
    return $conf;
}

sub get_list_commands {
    my %arg     = ( conf => undef, @_ );
    
    my @commands;
    
    ## For each section, except 'do'
    foreach my $section ( keys %{$arg{conf}} ) {      
        next if ( $section eq 'do' );
        next if ( defined $arg{conf}->{do} and ( not defined $arg{conf}->{do}{$section} ) );
        next if ( defined $arg{conf}->{do} and ( $arg{conf}->{do}{$section} !~ /true/i ) );
        
        ## Collect command for each section
        push @commands, JSNAP::find_command_in_section( section => $arg{conf}->{$section} );
    }
    
    return \@commands;
}

sub get_list_commands_with_each {
    my %arg     = ( 
        conf    => undef, 
        results     => undef, 
        @_ );
    
    my @commands;
    
    ## For each section, except 'do' and chech if the section is set as TRUE in 'do'
    foreach my $section ( keys %{$arg{conf}} ) {      
        next if ( $section eq 'do' );
        next if ( defined $arg{conf}->{do} and ( not defined $arg{conf}->{do}{$section} ) );
        next if ( defined $arg{conf}->{do} and ( $arg{conf}->{do}{$section} !~ /true/i ) );
        
        ## Look for entry that have 'with-each'
        foreach my $entry ( @{$arg{conf}->{$section}} ) {
            next if ( not defined $entry->{'with-each'} );
            
            my @values;
            ## - Search for the initial cmd in the conf file
            my $init_cmd        =  JSNAP::find_command_in_section( section => $arg{conf}->{$section} );
            my $new_cmd_base    =  JSNAP::find_command_in_section( section => $entry->{'with-each'} );
            
            ## Quick check
            if ( not defined $new_cmd_base ) {
                print "WARN - Unable to command in section 'with-each' under $init_cmd\n";
                next;
            }
            
            ## - Search for the result of this command 
            ## -- if defined, extract values of the iterate input
            if ( defined $arg{results}->{$init_cmd} ) {
              
                my $xml         = $arg{results}->{$init_cmd}; 
                my $nodevalues  = $xml->find($entry->{'iterate'}); 
                
                foreach my $nodevalue ( $nodevalues->get_nodelist ) {
                    my $value = $nodevalue->string_value;
                    
                    ## Replace %s in the string by this value and store the new command
                    my $tmp_cmd = $new_cmd_base; 
                    $tmp_cmd    =~ s/\%s/$value/g; 
                    
                    ## Store commands to be return
                    push @commands, $tmp_cmd;
                }
            }
            else {
                print "WARN - Unable to find results for $init_cmd\n"
            }
        }
    }
    
    return \@commands;
}

sub find_command_in_section { 
    my %arg     = ( 
        sectiom    => undef, 
        @_ );
    
    my $command;
    
    foreach my $entry ( @{$arg{section}} ) {
        next if ( not defined $entry->{command} );    
        $command = $entry->{command};
    }
    
    return $command;
}

sub retrieve_commands_remote {
    my %arg     = (
        snapname    => undef,
        commands    => undef, 
        handle      => undef, 
        @_ );
        
    my %results; 
    
    foreach my $command ( @{$arg{commands}} ) {
        print "Executing: $command ..\n";   
        $results{$command} = JSNAP::execute_cli_cmd( $arg{handle}, $command ); 
    }

    return \%results;
}

sub retrieve_commands_local {
    my %arg     = (
        target      => undef,
        snapname    => undef,
        commands    => undef, 
        @_ );
        
    my %results;

    foreach my $command ( @{$arg{commands}} ) {
        ## Do some cleanup on the string
        my $cmd = cleanup_cmd_name( $command );
        
        ## Build the name of the file
        ## TARGET_JSNAP_CMD
        my $file_name = $JSNAP::dir.'/'.$arg{target}.'_'.$arg{snapname}.'_'.$cmd.'.xml';
        
        ## Check if file exist, if it exist delete it
        unless ( -f $file_name ){
            print "WARN | Unable to find local saved result for TARGET:$arg{target}, SNAP:$arg{snapname}, COMMAND:$command SKIPPING ..\n ";
            next; 
        }
        
        ## Read the file and create a XPATH object
        my $xml = XML::XPath->new( filename => $file_name );
        $results{$command} = $xml; 
    }
    
    return \%results;
}

sub save_commands_local {
    my %arg     = (
        target      => undef,
        snapname    => undef,
        results     => undef, 
        @_ );

    ## Get the directory name through CLI opt, Env Var, Default
    
    
    ## Check if the Directory exist  
    ## If not Create it    
    unless ( -d $JSNAP::dir ) {
        `mkdir $JSNAP::dir`;
        print "Directory $JSNAP::dir created\n";
    }
    
    print "Saving: Commands output to $JSNAP::dir .. \n";
    
    ## Create One XML File per command
    foreach ( keys %{$arg{results}} ) {
        
        ## Do some cleanup on the string
        my $cmd = cleanup_cmd_name( $_ );
        
        ## Build the name of the file
        ## TARGET_JSNAP_CMD
        my $file_name = $JSNAP::dir.'/'.$arg{target}.'_'.$arg{snapname}.'_'.$cmd.'.xml';
        
        ## Check if file exist, if it exist delete it
        if ( -f $file_name ){
            `rm -f  $file_name`;
            ## print "WARN | File $file_name already exist, will delete it\n";
        }
        
        ## Write result to file
        open my $CF, '>', $file_name;
            print $CF $arg{results}{$_}->{_xml};
        close $CF;
        
        ## print "Command: $cmd output, has been saved in $file_name\n";
    }    
        
        
    return 1;
        
        
}

sub cleanup_cmd_name {
    my $cmd = shift; 
    
    $cmd    =~ s/\s+/_/g;    ## Replace space by _
    
    return $cmd;
}

sub validate_operator_name {
    my $operator = shift;
    
    return 'element_exists'     if ( ( $operator eq 'exists' )      or ( $operator eq 'element_exists' ) );
    return 'not_exists'         if ( ( $operator eq 'not-exists' )  or ( $operator eq 'not_exists' ) );
    
    return 'is_equal'           if ( ( $operator eq 'is-equal' )    or ( $operator eq 'is_equal' ) );
    return 'not_equal'          if ( ( $operator eq 'not-equal' )   or ( $operator eq 'not_equal' ) );
    
    return 'is_in'              if ( ( $operator eq 'is-in' )       or ( $operator eq 'is_in' ) );
    return 'not_in'             if ( ( $operator eq 'not-in' )      or ( $operator eq 'not_in' ) );
    
    return 'in_range'           if ( ( $operator eq 'in-range' )     or ( $operator eq 'in_range' ) );
    return 'not_in_range'       if ( ( $operator eq 'not-in-range' ) or ( $operator eq 'not_in_range' ) );
    
    return 'greater_than'       if ( ( $operator eq 'greater-than' ) or ( $operator eq 'greater_than' ) );
    return 'less_than'          if ( ( $operator eq 'less-than' )    or ( $operator eq 'less_than' ) );
    
    return 'contains'           if ( $operator eq 'contains' );
    return 'all_same'           if ( ( $operator eq 'all-same' )    or ( $operator eq 'all_same' ) );
    
    return 'same_nbr'           if ( ( $operator eq 'same-nbr' )    or ( $operator eq 'same_nbr' ) );
    
    return undef;
}

sub build_failed_msg_list {
	my $fail_msg    = shift;        ## String representing message to print in case of failure with %s for each value to replace
	my $fail_res    = shift;        ## Array of Array, first array is per failure, second array is per value to replace in the string 
    
    return ['build_failed_msg_list : Unable to build the list of error message, "message" not valid' ]  if ( not defined $fail_msg );
    return ['build_failed_msg_list : Unable to build the list of error message, "list" not valid' ]     if ( not defined $fail_res or ( ref $fail_res ne 'ARRAY' ));
    
    my @failed_msg_list;
    
    ## Build custom error messages for each failed results
    my @str_failed_splt  = split "%s", $fail_msg;

    foreach my $fail ( @{$fail_res} ) {
        
        ## Check first that the variable is a ARRAYREF as expected.
        if ( ref $fail ne 'ARRAY' ) {
            push @failed_msg_list, 'build_failed_msg_list : Unable to build the error message for this entry, "list of value" not valid';
            next;
        }
        
        my $str_failed  = '';  
        my $idx         = 1;
        my $nbr_entries = scalar @{$fail};
        
        foreach my $sub_str ( @str_failed_splt ) {
            $str_failed = $str_failed.$sub_str;
            $str_failed = $str_failed.$fail->[$idx] if ( $idx < $nbr_entries );
            $idx++;
        }
        
        push @failed_msg_list, $str_failed;
    }
    
    return @failed_msg_list;
}

sub execute_cli_cmd {
	my $jnx = shift; 
	my $cmd	= shift;
	
	my $rpc    	= "<rpc><command>$cmd</command></rpc>";
	my $res 	= $jnx->send_and_recv_rpc( $rpc );
	my $xml  	= XML::XPath->new( xml => $res );
	 
	return $xml;
}

sub whoami  { 
    my @splitted_name = split('::', (caller(1))[3]);
    return $splitted_name[-1];
} 
sub whowasi { 
    my @splitted_name = split('::', (caller(2))[3]);
    return $splitted_name[-1];
} 

sub init_result_hash {
    my %results;
    
    $results{'nbr_match'}   = 0;
    $results{'nbr_failed'}  = 0;
    $results{'failed'}      = [];  
    $results{'operator'}    = whowasi;
    
    return %results;
}

1; 

