#!/usr/bin/perl
use strict;
use Email::MIME;
use IPC::Open2;

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
    # wav attachment
    if ( $part->content_type =~ m[audio/x-wav] ) {

	# build new filename
	my $new_filename = $part->filename;
	$new_filename =~ s/wav$/ogg/;
	$part->filename_set( $new_filename ); 
	
	# set new cotent type
	$part->content_type_set( 'audio/x-vorbis+ogg' );

	# convert attachment 
	my($out, $in); # open filedescriptors for pipe
	# converter as pipe
	my $pid = open2($out, $in, 'sox -t wav - -t ogg -' );
	# feed body in the pipe
	print $in $part->body;
	# collect the result
	my @ogg_data = <$out>;
	# build string
	my $new_body = join( "", @ogg_data );
	# set the new body (ogg data)
	$part->body_set( $new_body );
	# wait for the forked child (open2)
	waitpid( $pid, 0 );
      }
  });
# give back the string
print $parsed->as_string;

__END__

=head1 replacewavogg.pl

Licence GPL3



