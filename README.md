Perl version of Junos Snapshot Administrator
==========
Inspired by https://github.com/Juniper/junos-snapshot-administrator

It provide a very powerful way to do some health check at scale.


Original documentation
======================
Configuration file : http://www.juniper.net/techpubs/en_US/junos-snapshot1.0/topics/topic-map/automation-junos-snapshot-configuration-file-creating.html
Test operators :   http://www.juniper.net/techpubs/en_US/junos-snapshot1.0/topics/reference/general/automation-junos-snapshot-operators-summary.html
User manual : http://www.juniper.net/techpubs/en_US/junos-snapshot1.0/topics/task/configuration/automation-junos-snapshot-using-on-single-device.html
Administrator guide [pdf] (all) : http://www.juniper.net/techpubs/en_US/junos-snapshot1.0/information-products/pathway-pages/junos-snapshot.pdf


TODO List
=========



Disclaimer
==========

This library is still in active development
Right now the .pl file is still specific to my personal use but it should works for anyone anyway
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
