jsnap-perl
==========

Perl version of Junos Snapshot Administrator



TODO List
=========
       1. Implement local results caching to be able to compare 2 snapshots
       2. Complete the TODO list

Disclaimer
==========

This library is still in active development
Right now the .pl file is still specify to my personal use but it should works for anyone anyway
I'll clear it up later.

Prerequisites
==============

    JSNAP.pm
    --------
       1. Try::Tiny
       2. Data::Dumper
       3. Storable
       4. XML::XPath and XML::XPath::XMLParser 
       5. YAML::Syck
    
    JSNAP.pl
    ---------
       1. Getopt::Long
       2. Data::Dumper
       3. File::Basename
       4. Net::Netconf::Manager -> https://github.com/Juniper/netconf-perl
       5. JSNAP :)
