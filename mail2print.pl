#!/usr/bin/perl -w

use strict;
use Email::MIME;
use IPC::Open2;
use File::Temp;

# autoflush
$| = 1;

my $queue  = shift;

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

	my($out, $in); # open filedescriptors for pipe
        # print file
        my $pid = open2($out, $in, "/usr/bin/lpr -P $queue" );
        # feed body in the pipe
        print $in $part->body;
        close $in;
        # collect the result
        $/=undef;
        close $out;

        # wait for the forked child (open2)
        waitpid( $pid, 0 );
    }
  });

exit 0;
