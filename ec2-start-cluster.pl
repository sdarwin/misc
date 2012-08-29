#!/usr/bin/perl

use strict;
use JSON::Parse 'json_to_perl';
use Data::Dump  qw(dump);

=comment

#=======================================================
Instructions and comments:
#=======================================================

ec2-start-cluster.pl version 0.1

by Sam Darwin
started 2012-05-18

This script will automatically start a few EC2 instances, and put a hosts file onto all of them.
Good for a small test environment which can be shut down and turned on repeatedly.

Pre-requisites:

Download and install ec2 tools.

Set these variables in your general environment:
for example - 
export EC2_PRIVATE_KEY=/root/pk-.....pem
export EC2_CERT=/root/cert-......pem
export JAVA_HOME=/usr/java/default
export EC2_HOME=/usr/downloads/ec2-api-tools-1.5.3.1

create external json file with this format:
{
                "i-b93ec2" : { "name" : "chef-server",
                                 "login" : "root",
                                 "publicip" : "",
                                 "privateip" : "",
                                 "alias" : "" ,
                                 "osfamily" : "redhat"
                                  },
                "i-1dc366" : { "name" : "chef-client1",
                                 "login" : "root",
                                 "publicip" : "",
                                 "privateip" : "",
                                 "alias" : "" ,
                                 "osfamily" : "redhat"
                                  }
}

Run this program with no parameters, to see the "usage".

todo:
?clear up known_hosts on puppetmaster
?check for the absence of required files
re-write in chef
use augeas on end-nodes

=cut

#===============================================
#Configuration
#===============================================


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

if (!$arg0) {
	print "Usage: ./ec2-start-cluster.pl json-config-file [start|stop]\n";
	exit;
	}

my $json;
open FILE, $arg0 or die "Couldn't open file: $!"; 
while (<FILE>){
 $json .= $_;
}
close FILE;

my $instances = json_to_perl ($json);

my $ec2_home = $ENV{'EC2_HOME'};

if ($arg1 eq "stop") {

	my $COMMAND="ec2-stop-instances";
	my $CPATH="$ec2_home/bin";

        print "Stopping Instances\n";

        my $instance;

	#print "here\n";
        foreach $instance (keys %{$instances}) {
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
	foreach $instance (keys %{$instances}) {
        	my $x = `$CPATH/$COMMAND $instance`;
		print $x;
	}
}

print "Collecting IPs\n";

my $instance;
foreach $instance (keys %{$instances}) {
        my $id = $instance;

	print "id $id name ".$instances->{"$id"}{"name"}."\n";

	#collect public IP
	my $x = `$ec2_home/bin/ec2-describe-instances $id`;
	$x =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
	print $x;
	print "\n";
	print "public ip is $1\n";
	#assign the ip to the array
	$instances->{"$id"}{"publicip"}=$1;

       #collect private IP
        $x =~ /\s(10\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
        print "private ip is $1\n";
	print "\n";
        #assign the ip to the array
        $instances->{"$id"}{"privateip"}=$1;

	}

open FILE, ">augeas.txt" or die $!;

my $x;
my $y=1;
foreach $instance (keys %{$instances}) {
        my $id = $instance;

if ($instances->{$id}{"name"} && $instances->{$id}{"name"} ne "localhost") {
                $x = "rm /files/etc/hosts/*[canonical = '".$instances->{$id}{"name"}."']";
                #print "x is $x\n";
                print FILE "$x\n";
                print FILE "set /files/etc/hosts/0$y/ipaddr ".$instances->{$id}{"publicip"}."\n";
                print FILE "set /files/etc/hosts/0$y/canonical ".$instances->{$id}{"name"}."\n";
                print FILE "set /files/etc/hosts/0$y/alias ".$instances->{$id}{"name"}.".ec2.internal\n";
		if ($instances->{$id}{"alias"}) {
                print FILE "set /files/etc/hosts/0$y/alias[2] ".$instances->{$id}{"alias"}."\n";
		}
                $y++;
                }
        }

print FILE "save\n";

`augtool -f augeas.txt`;

close FILE;

print "Creating hosts file\n";

open FILE, ">hosts" or die $!;

print FILE "127.0.0.1   localhost localhost.localdomain\n";

foreach $instance (keys %{$instances}) {
        my $id = $instance;
        my $name = $instances->{$id}{"name"};
        my $privateip = $instances->{$id}{"privateip"};
        my $alias = $instances->{$id}{"alias"};
	print FILE "$privateip $name $alias\n";
	}

close FILE;

my $sleep=1;
print "sleeping $sleep seconds while hosts start up\n";
sleep $sleep;

if ($copyhostsfile) {
print "Copying hosts file to instances\n";
foreach $instance (keys %{$instances}) {
        my $id = $instance;
        my $name = $instances->{$id}{"name"};
        my $login = $instances->{$id}{"login"};
	my $connecthost = $login.'@'.$name ;
	print "connecthost is $connecthost\n";
	`scp -i /root/.ssh/testmachinekey.pem -o StrictHostKeyChecking=no hosts $connecthost:/etc/`;
	}
}

#fix hostnames
foreach $instance (keys %{$instances}) {
        my $id = $instance;
        my $name = $instances->{$id}{"name"};
        my $login = $instances->{$id}{"login"};
        my $connecthost = $login.'@'.$name ;
        my $osfamily = $instances->{$id}{"osfamily"};
	my $hostname = $name;

	if ($osfamily eq "redhat") {
		my $subst = " \'s/^HOSTNAME=.*\$/HOSTNAME=$hostname/\' ";
		`ssh  -i /root/.ssh/testmachinekey.pem -o StrictHostKeyChecking=no $connecthost \'sed -i $subst /etc/sysconfig/network ; hostname $hostname\' ` ;
		my $subst = " \'s/^SELINUX=.*\$/SELINUX=disabled/\' ";
		`ssh  -i /root/.ssh/testmachinekey.pem -o StrictHostKeyChecking=no $connecthost \'sed -i $subst /etc/selinux/config ; setenforce 0 \' ` ;
		`ssh  -i /root/.ssh/testmachinekey.pem -o StrictHostKeyChecking=no $connecthost \'chkconfig iptables off ; service iptables stop \' ` ;
		}
       if ($osfamily eq "debian") {
                my $subst = " \'s/^HOSTNAME=.*\$/HOSTNAME=$hostname/\' ";
                `ssh  -i /root/.ssh/testmachinekey.pem -o StrictHostKeyChecking=no $connecthost \'echo $hostname > /etc/hostname ; sudo hostname $hostname\' ` ;
                }

        }


} #end of "else" for starting instances

