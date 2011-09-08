#!/usr/bin/perl
use strict;
use Email::MIME;
use IPC::Open2;
use Data::Dumper;

my $receiver = $ARGV[0];

# slurp message
my @msg = <STDIN>;
# build message string
my $message = join( "", @msg );
# parse message to get parts
my $parsed = Email::MIME->new($message);
# walk through the parts
$parsed->walk_parts(sub {
    # this part
    my ($part) = @_; 
    # multipart
    return if $part->parts > 1;
    if ( $part->content_type =~ m[text/plain;] ) {
	return if $part->body =~ m[-----BEGIN PGP MESSAGE-----];
        # encrypt part inline 
        my($out, $in); # open filedescriptors for pipe
        # converter as pipe
        my $pid = open2($out, $in, "/usr/bin/gpg --batch --no-verbose -a -e -r $receiver" );
        # feed body in the pipe
        print $in $part->body;
	close $in;

        # collect the result
	$/=undef;
	my $new_body= <$out>;
        # set the new body (encrypted data)
        $part->body_set( $new_body );
        # wait for the forked child (open2)
        waitpid( $pid, 0 );
    }
});

print $parsed->as_string;





__END__

=head1 encrypt.pl 

Transport Filter to encrypt not encrypted email 
(c) Joerg Gollnick
Licence GPL3
