#!/usr/bin/perl
use strict;
use Email::MIME;
use IPC::Open2;
#use Data::Dumper;

my $receiver = shift;
my $homedir  = shift;

#open ERR, ">>/tmp/enc.err";
# slurp message
my @msg = <>;
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
        my $pid = open2($out, $in, "/usr/bin/gpg --homedir $homedir -a -e -r $receiver --no-verbose 2>/dev/null" );
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

#print ERR $message;
#print ERR "------\n";
#print ERR $parsed->as_string;
print $parsed->as_string;
print "\n";

__END__

=head1 encrypt.pl 

Transport Filter to encrypt not encrypted email 
(c) Joerg Gollnick
Licence GPL3
