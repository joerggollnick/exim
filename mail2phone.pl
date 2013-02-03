#!/usr/bin/perl -w

use strict;
use Email::MIME;
use IPC::Open2;
use File::Temp;

# autoflush
$| = 1;

my $receiver  = shift;
my $own_msg_id = shift;
my $sipDomain = shift;
my $sipUser   = shift;
my $sipPasswd = shift;

my ( $number, $vqueue ) = split( /[+]/, $receiver);

# delete all message for vqueue
my %id;

open(QUEUE,"/usr/sbin/exim -bpu |") or die("Error openning pipe: $!\n");
while(<QUEUE>) {
    chomp();
    my $line = $_;
    #Should be 1st line of record, if not error.
    if ($line =~ /^\s*(\w+)\s+((?:\d+(?:\.\d+)?[A-Z]?)?)\s*(\w{6}-\w{6}-\w{2})\s+(<.*?>)/) {
        my $msg = $3;
        $id{$msg}{from} = $4;
        $id{$msg}{match} = 0;
        while(<QUEUE> =~ /\s+(.*?\@.*)$/) {
	    push(@{$id{$msg}{rcpt}},$1);
        }
    }
}
close(QUEUE) or die("Error closing pipe: $!\n");

my $removeout = "";
# read complete multi line message or output
$/=undef;
my $message = <>;

my @queueelems;
if ( defined $vqueue )
{
    foreach my $msg (keys %id) {
        next if ( "$msg"  eq "$own_msg_id" );
        @queueelems = grep( /$vqueue/i, @{$id{$msg}{rcpt}} );
        $id{$msg}{match} = @queueelems;
        if( $id{$msg}{match} > 0 ) {
	    open(REMOVE,"/usr/sbin/exim -Mrm $msg |") or die("Error openning pipe: $!\n");
            $removeout .= <REMOVE>;
            close(REMOVE) or die("Error closing pipe: $!\n");
        }
    }
}

open(QUEUE,"/usr/sbin/exim -bpu |") or die("Error openning pipe: $!\n");
my $eximout = <QUEUE>;
close(QUEUE) or die("Error closing pipe: $!\n");

# return code
my $return_code = 75;
# parse message to get parts
my $parsed = Email::MIME->new($message);
my $subject = $parsed->header( 'Subject' );
my $date    = $parsed->header( 'Date' );
my $language = 'mb-de6';
$language = $1 if $subject =~ /\[(\w+)\]/;
my $dtmf = 'N';
$dtmf = $1 if $subject =~ /\!(\d)\!/;
# walk through the parts
$parsed->walk_parts(sub {
    # this part
    my ($part) = @_; 
    # multipart
    return if $part->parts > 1;
    # text file Attachment
    if ( $part->content_type =~ m[text/plain] ) {

        # get a safe tempnam
        my $tmp = File::Temp->new( SUFFIX => '.wav' );
        my $tmpname = $tmp->filename();

        my($out, $in); # open filedescriptors for pipe
        # espeak converter as pipe
        my $pid = open2($out, $in, "/usr/bin/espeak -v $language -s 120 -p 55 -a 200 -w $tmpname --stdin 2>\&1" );
        # feed subject and body in the pipe
        $subject =~ s/\[(\w+)\]//; 
        $subject =~ s/\!(\d)\!//; 
        print $in $subject;
	print $in $part->body;
        close $in;

        # collect the result
        $/=undef;
        my $espeakreport = <$out>;
        close $out;
        
        # wait for the forked child (open2)
        waitpid( $pid, 0 );
         
        close $tmp;
    
        $pid = open2($out, $in, "/etc/scripts/sendwav2phone.py $number\@$sipDomain $tmpname $dtmf $sipDomain $sipUser $sipPasswd  2>/dev/null" ); 

	close $in;
	
        # collect the result
        $/=undef;
        my $pjreport = <$out>;
        close $out;

        # wait for the forked child (open2)
        waitpid( $pid, 0 );
       
	if ( $pjreport =~ /Accepted/ ) { 
		$return_code = 0; 

		$pid = open2($out, $in, "mailx -s \"Report $subject $date\" $ENV{SENDER}" );
                
                $vqueue = "No queue" if ( !defined $vqueue );
	
		print $in "$espeakreport\n$pjreport\n$eximout\n$removeout\n$own_msg_id $receiver $number\n";
		close $in;

		close $out;
	
        	# wait for the forked child (open2)
        	waitpid( $pid, 0 );
    	}
     }
  });

exit $return_code;
