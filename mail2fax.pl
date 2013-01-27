#!/usr/bin/perl -w

use strict;
use Email::MIME;
use IPC::Open2;
use File::Temp;

# autoflush
$| = 1;

my $number  = shift;
my $ident   = shift;
my $channel = shift;

my $fromfax = $ident;
$ident   =~ s/_/ /g;
$fromfax =~ s/^[+]\d+_/0/;
$fromfax =~ s/_//g;

# read complete message 
$/=undef;
my $message = <>;

# parse message to get parts
my $parsed = Email::MIME->new($message);

# walk through the parts
$parsed->walk_parts(sub {
    # this part
    my ($part) = @_; 
    # multipart
    return if $part->parts > 1;
    # pdf Attachment
    if ( $part->content_type =~ m[application/pdf] || 
         $part->content_type =~ m[application/PostScript] ) {

        # get a safe tempnam
        my $tmptiff = File::Temp->new( SUFFIX => '.tiff' );
        my $tmpnametiff = $tmptiff->filename();

        my($out, $in); # open filedescriptors for pipe
        # tiff converter as pipe
        my $pid = open2($out, $in, "/usr/bin/gs -q -dNOPAUSE -dBATCH -dSAFER=true -dFIXEDMEDIA -sPAPERSIZE=a4 -r204x196 -sDEVICE=tiffg3 -sOutputFile=$tmpnametiff -" );
        # feed body in the pipe
        print $in $part->body;
        close $in;

        # collect the result
        $/=undef;
        my $tiffconv = <$out>;
        close $out;
        
        # wait for the forked child (open2)
        waitpid( $pid, 0 );
         
        # send fax
        $pid = open2($out, $in, "/usr/bin/capifax -header \"mail2fax\" -ident \"$ident\" -send $tmpnametiff $channel $fromfax $number" );
        close $in;
        # collect the result
        $/=undef;
        my $capireport = <$out>;
        close $out;

        # wait for the forked child (open2)
        waitpid( $pid, 0 );

        my $tmppdf = File::Temp->new( SUFFIX => '.pdf' );
        my $tmpnamepdf = $tmppdf->filename();

	$pid = open2($out, $in, "/usr/bin/a2ps -q -1 -M A4 -R --stdin=\"fax report\" -o- | ps2pdf -sPAPERSIZE=a4 - $tmpnamepdf");
        print $in $capireport;
	print $in "$ident\n$fromfax\n$channel\n";
        close $in;

        close $out;

        # wait for the forked child (open2)
        waitpid( $pid, 0 );

        $pid = open2($out, $in, "/usr/bin/mailx -a $tmpnamepdf -a $tmpnametiff -s \"fax report\" $ENV{SENDER}" ); 
        print $in "$capireport\n";
        close $in;

        close $out;

        # wait for the forked child (open2)
        waitpid( $pid, 0 );

        close $tmptiff;
	close $tmppdf;
    }
  });

exit 0;
