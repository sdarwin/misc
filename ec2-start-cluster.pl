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

#you must set these:
my %instances = ( "i-3b49f85d" => [ "master", "" , "" ],
		  "i-8b49f8ed" => [ "slave", "" , "" ],
		  "i-4f67ec29" => [ "secondary", "" , "" ]
	);	

#you might like to set these in this file, if using cron where the environment is missing.
#export EC2_PRIVATE_KEY=/root/pk-.....pem
#export EC2_CERT=/root/cert-......pem
#export JAVA_HOME=/usr/java/default
#export EC2_HOME=/usr/downloads/ec2-api-tools-1.5.3.1

#===============================================
#The Code
#===============================================

my $startmachines = 1;
my $copyhostsfile = 1;

my $ec2_home = $ENV{'EC2_HOME'};

my $COMMAND="ec2-start-instances";
my $CPATH="$ec2_home/bin";

if ($startmachines) {

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
        my $name = $instances{$id}[0];
        my $publicip = $instances{$id}[1];
        my $privateip = $instances{$id}[2];

	print "id $id name $name\n";

	#collect public IP
	my $x = `$ec2_home/bin/ec2-describe-instances $id`;
	$x =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
	print $x;
	print "\n";
	print "public ip is $1\n";
	#assign the ip to the array
	$instances{"$id"}[1]=$1;

	#"x" =~ /(x)/;

       #collect private IP
        $x =~ /\s(10\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
        print "private ip is $1\n";
	print "\n";
        #assign the ip to the array
        $instances{"$id"}[2]=$1;

	}

print "Creating hosts file\n";

open FILE, ">hosts" or die $!;

print FILE "127.0.0.1   localhost localhost.localdomain\n";

foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}[0];
        my $publicip = $instances{$id}[1];
        my $privateip = $instances{$id}[2];
	print FILE "$privateip $name\n";
	}

close FILE;

if ($copyhostsfile) {
print "Copying hosts file to instances\n";
foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}[0];
        my $publicip = $instances{$id}[1];
        my $privateip = $instances{$id}[2];

	`scp hosts $publicip:/etc/`;
	}
}

#Fix local hosts file, here on 'puppetmaster'.

open FILE, ">augeas.txt" or die $!;

my $x;
my $y=1;
foreach $instance (keys %instances) {
        my $id = $instance;
        my $name = $instances{$id}[0];
        my $publicip = $instances{$id}[1];
        my $privateip = $instances{$id}[2];
	if ($name && $name ne "localhost") {
		$x = "rm /files/etc/hosts/*[canonical = '$name']";
		print "x is $x\n";
		print FILE "$x\n"; 
		print FILE "set /files/etc/hosts/0$y/ipaddr $publicip\n";
		print FILE "set /files/etc/hosts/0$y/canonical $name\n";
		$y++;
		}
	}

print FILE "save\n";

`augtool -f augeas.txt`;

close FILE;


