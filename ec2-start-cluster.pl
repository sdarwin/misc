#!/usr/bin/perl

use strict;

=comment

#=======================================================
Instructions and comments:
#=======================================================

ec2-start-cluster.pl version 0.1

by Sam Darwin
2012-05-18

This script will automatically start a few EC2 instances, and put a hosts file onto all of them.
The way, they can all see each other by "name".   Good for a small test environment
which can be shut down and turned on repeatedly.

Pre-requisites:

Download and install ec2 tools.

Set these variables in your general environment:
for example - 
export EC2_PRIVATE_KEY=/root/pk-.....pem
export EC2_CERT=/root/cert-......pem
export JAVA_HOME=/usr/java/default
export EC2_HOME=/usr/downloads/ec2-api-tools-1.5.3.1

input the ID's and friendly names of your instances into the %instances hash below:

It's a time-saver to use ssh-copy-id onto the instances.

todo:
add host names to new servers
clear up known_hosts on puppetmaster
adjust the username for redhat, ubuntu, amazon
check for the absence of required files
re-write in puppet
use augeas on end-nodes
add stop functionality into this script
perhaps use an external config file
=cut

#===============================================
#Configuration
#===============================================

my %instances = (
		"i-3a0b3242" => { "name" => "puppetserver",
                                        "login" => "root",
                                        "publicip" => "",
                                        "privateip" => "",
                                        "alias" => "puppet" ,
                                        },
		"i-13403b68" => { "name" => "nagios8",
                                        "login" => "root",
                                        "publicip" => "",
                                        "privateip" => "",
                                        "alias" => "" ,
                                        },
		"i-03fa8178" => { "name" => "nagios9",
                                        "login" => "root",
                                        "publicip" => "",
                                        "privateip" => "",
                                        "alias" => "" ,
                                        },
		);
=comment
my %instanceshadoop = ( "i-fa0c7283" => [ "master", "" , "" ],
                  "i-e80d7391" => [ "slave", "" , "" ],
                  "i-ea0d7393" => [ "secondary", "" , "" ]
        );

my %instancesmongo = ( "i-2e307657" => [ "mongo1", "" , "" ],
                  "i-20307659" => [ "mongo2", "" , "" ],
                  "i-2230765b" => [ "mongo3", "" , "" ]
        );
=cut

#you might like to set these in this file, if using cron where the environment is missing.
$ENV{EC2_PRIVATE_KEY}="/root/pk-E7QQZXPQWOAYNED2HE7T3Y5ZJTKLFOVW.pem";
$ENV{EC2_CERT}="/root/cert-E7QQZXPQWOAYNED2HE7T3Y5ZJTKLFOVW.pem";
$ENV{JAVA_HOME}="/usr/java/default";
$ENV{EC2_HOME}="/usr/downloads/ec2-api-tools-1.5.3.1";

#===============================================
#The Code
#===============================================

my $arg0=$ARGV[0];
my $arg1=$ARGV[1];
my $arg2=$ARGV[2];

#print "$arg0 w $arg1 w $arg2\n";

=comment
my %instances;

if ($arg1 eq "mongo") {
	print "using mongo\n";
	%instances = %instancesmongo;
	}

else {
	print "using hadoop\n";
	%instances = %instanceshadoop;
	}
=cut

my $ec2_home = $ENV{'EC2_HOME'};

if ($arg0 eq "stop") {

	my $COMMAND="ec2-stop-instances";
	my $CPATH="$ec2_home/bin";

        print "Stopping Instances\n";

        my $instance;

	print "here and".%instances."\n";
        foreach $instance (keys %instances) {
		print "here2\n";
                my $x = `$CPATH/$COMMAND $instance`;
                print $x;
        	}
	} #end of stop

else { #start instances

`sed -i -e 's/master*//' /root/.ssh/known_hosts`;
`sed -i -e 's/secondary*//' /root/.ssh/known_hosts`;
`sed -i -e 's/slave*//' /root/.ssh/known_hosts`;

my $debuggingstartmachines = 1;
my $copyhostsfile = 1;

my $COMMAND="ec2-start-instances";
my $CPATH="$ec2_home/bin";

if ($debuggingstartmachines) {

	print "Starting Instances\n";

	my $instance;
	foreach $instance (keys %instances) {
        	my $x = `$CPATH/$COMMAND $instance`;
		print $x;
	}
}

print "Collecting IPs\n";

my $instance;
foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}{"name"};
        my $publicip = $instances{$id}{"publicip"};
        my $privateip = $instances{$id}{"privateip"};

	print "id $id name $name\n";

	#collect public IP
	my $x = `$ec2_home/bin/ec2-describe-instances $id`;
	$x =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
	print $x;
	print "\n";
	print "public ip is $1\n";
	#assign the ip to the array
	$instances{"$id"}{"publicip"}=$1;

	#"x" =~ /(x)/;

       #collect private IP
        $x =~ /\s(10\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
        print "private ip is $1\n";
	print "\n";
        #assign the ip to the array
        $instances{"$id"}{"privateip"}=$1;

	}

#Fix local hosts file, here on 'puppetmaster'.

open FILE, ">augeas.txt" or die $!;

my $x;
my $y=1;
foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}{"name"};
        my $publicip = $instances{$id}{"publicip"};
        my $privateip = $instances{$id}{"privateip"};
        my $alias = $instances{$id}{"alias"};
        my $login = $instances{$id}{"login"};

if ($name && $name ne "localhost") {
                $x = "rm /files/etc/hosts/*[canonical = '$name']";
                #print "x is $x\n";
                print FILE "$x\n";
                print FILE "set /files/etc/hosts/0$y/ipaddr $publicip\n";
                print FILE "set /files/etc/hosts/0$y/canonical $name\n";
                print FILE "set /files/etc/hosts/0$y/alias $name.ec2.internal\n";
                print FILE "set /files/etc/hosts/0$y/alias[2] $alias\n";
                $y++;
                }
        }

print FILE "save\n";

`augtool -f augeas.txt`;

close FILE;

print "Creating hosts file\n";

open FILE, ">hosts" or die $!;

print FILE "127.0.0.1   localhost localhost.localdomain\n";

foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}{"name"};
        my $publicip = $instances{$id}{"publicip"};
        my $privateip = $instances{$id}{"privateip"};
        my $alias = $instances{$id}{"alias"};
        my $login = $instances{$id}{"login"};
	print FILE "$privateip $name $name.ec2.internal $alias\n";
	}

close FILE;

my $sleep=1;
print "sleeping $sleep seconds while hosts start up\n";
sleep $sleep;

if ($copyhostsfile) {
print "Copying hosts file to instances\n";
foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}{"name"};
        my $publicip = $instances{$id}{"publicip"};
        my $privateip = $instances{$id}{"privateip"};
        my $alias = $instances{$id}{"alias"};
        my $login = $instances{$id}{"login"};
	my $connecthost = $login.'@'.$name ;
	print "connecthost is $connecthost\n";
	`scp -i /root/.ssh/testmachinekey.pem -o StrictHostKeyChecking=no hosts $connecthost:/etc/`;
	}
}

} #end of "else" for starting instances

