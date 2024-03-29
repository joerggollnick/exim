#!/usr/bin/perl -w

use strict;
use utf8;
use English;
use Email::MIME;
use IPC::Open2;
use File::Temp;
use File::Slurp;
use Date::Manip;
use Data::Dumper;
use Mail::Sender;
use Mail::Sender::CType::Ext;

Date_Init( 'Language=German');

# configure Mail::Sender 
$Mail::Sender::NO_X_MAILER = 1;

# autoflush
$| = 1;

my $old = $/;

# read complete message 
$/=undef;
my $message = <>;

# parse message to get parts
my $parsed = Email::MIME->new($message);
my $string = $parsed->body;
$string =~ s/\r\n/\n/g;
$string =~ s/\%/ Prozent/g;
$string =~ s/_/\\_/g;
#$string =~ s/€/\\EUR\{\}/g;

# empty structure
my $meta    = {};
my $vertrag = {};
my $werte   = {};
my @lines   = undef;
my $section = undef;
my $key     = undef;
my $value   = undef;
my $name_for_file = undef;

# mark keys
$string =~ s/\n(.*?)\n\t\t/\n=== $1 ===\n/gu;
# replace three or more lines
$string =~ s/(\n){3,}/\n\n/gu;
# make lines
@lines = split( /\n/, $string);
# iterate
foreach my $line (@lines) {
    chomp $line;
    if( $line =~ /====== (.*?) ======/ ) {
	$section = $1;
	$section =~ s/ /_/g;
	$werte->{$section}->{'parsed'} = 1;
	$key = undef;
    } elsif ( $line =~  /=== (.*?) ===/ ) {
 	$key = $1;
	$key =~ s/ /_/g;
    } elsif ( defined $key ) {
	$werte->{$section}->{$key} .= "$line\n";
    }
}

$meta->{'Name'}  = lc($werte->{'erster_Mieter'}->{'Name'});
$meta->{'Haus'}  = $werte->{'Wohnung'}->{'Haus'};
$meta->{'Etage'} = $werte->{'Wohnung'}->{'Etage'};
$meta->{'Lage'}  = $werte->{'Wohnung'}->{'Lage'};

$meta->{'Haus'}  =~ s/Burgstr\. /burg/; 
$meta->{'Etage'} =~ s/EG/0/;
$meta->{'Lage'}  =~ s/Links/1/;
$meta->{'Lage'}  =~ s/Mitte/2/;
$meta->{'Lage'}  =~ s/Rechts/3/;

foreach my $k (keys $meta) {
    $meta->{$k}  =~ s/\n//g;
}

$name_for_file = $meta->{'Name'};
$name_for_file =~ s/[ ]/_/g;

$meta->{'filename'} = "$meta->{'Haus'}\-$meta->{'Etage'}$meta->{'Lage'}\-" .
    "$name_for_file";

$meta->{'masterfilename'} = "mietvertrag\-$meta->{'filename'}";

my $final = $werte->{'Verwaltung'}->{'Finale_Version_des_Vertrages?'};

if( defined $final ) {
    $meta->{'masterfilename'} .= "-final";
}
$meta->{'receiverlist'} = $werte->{'Verwaltung'}->{'Vertragsempfaenger'};
$meta->{'receiverlist'} =~ s/[,\;]/ /g;
$meta->{'receiverlist'} =~ s/\n//g;


$vertrag->{'Kautionsfaktor'} = 
    $werte->{'Kaution'}->{'Monatsmieten'};

$vertrag->{'Mieterdebitor'}  = 
    $werte->{'Kaution'}->{'DKB_Mietkautionsdebitor'};

$vertrag->{'Mietername'}  = 
    $werte->{'erster_Mieter'}->{'Anrede'} . 
    $werte->{'erster_Mieter'}->{'Vorname'} . 
    $werte->{'erster_Mieter'}->{'Name'};

$vertrag->{'Mieteranschrift'}  = 
    $werte->{'erster_Mieter'}->{'Strasse'} . 
    $werte->{'erster_Mieter'}->{'Hausnummer'};

$vertrag->{'Mieterort'}  = 
    $werte->{'erster_Mieter'}->{'Postleitzahl'} . 
    $werte->{'erster_Mieter'}->{'Wohnort'};

$vertrag->{'Personen'}  =
    $werte->{'erster_Mieter'}->{'Anzahl_Personen'};

my $tel = $werte->{'erster_Mieter'}->{'Telefon'};
if( defined $tel ) { $vertrag->{'Mietertelefon'}  = $tel };
my $mobil = $werte->{'erster_Mieter'}->{'Mobil'};
if( defined $mobil ) { $vertrag->{'Mietermobil'}  = $mobil };
my $mail = $werte->{'erster_Mieter'}->{'Email'};
if( defined $mail ) { $vertrag->{'Mieteremail'}  = $mail };

$vertrag->{'Personen'}  =
    $werte->{'erster_Mieter'}->{'Anzahl_Personen'};

if( defined $werte->{'zweiter_Mieter'}->{'Postleitzahl'} ) {
$vertrag->{'Mieterzweiname'}  = 
    $werte->{'zweiter_Mieter'}->{'Anrede'} . 
    $werte->{'zweiter_Mieter'}->{'Vorname'} . 
    $werte->{'zweiter_Mieter'}->{'Name'};

$vertrag->{'Mieterzweianschrift'}  = 
    $werte->{'zweiter_Mieter'}->{'Strasse'} . 
    $werte->{'zweiter_Mieter'}->{'Hausnummer'};

$vertrag->{'Mieterzweiort'}  = 
    $werte->{'zweiter_Mieter'}->{'Postleitzahl'} . 
    $werte->{'zweiter_Mieter'}->{'Wohnort'};
}

$vertrag->{'MieteStabil'}  =  
    $werte->{'Miete'}->{'Miete_Monate_stabil'};
$vertrag->{'KaltMiete'}  =  
    $werte->{'Miete'}->{'Kaltmiete'};
$vertrag->{'Nebenkosten'}  =  
    $werte->{'Miete'}->{'Nebenkosten'};

my $heizkosten = $werte->{'Miete'}->{'Heizkosten'};

if( defined $heizkosten && $heizkosten > 0 ) { $vertrag->{'Heizkosten'}  =  $heizkosten; }

my $tier = $werte->{'Tierhaltung'}->{'Haustier_(Die_Haltung_..._ist_gestattet.)'};

if( defined $tier ) { $vertrag->{'Tierhaltung'}  =  $tier; }

$vertrag->{'Start'}  =  
    $werte->{'Miete'}->{'Mietbeginn_YYYY-MM-DD'};

foreach my $k (keys $vertrag) {
    $vertrag->{$k} =~ s/\n{1,}/ /g;
    $vertrag->{$k} =~ s/(.*)\s{1,}$/$1/g;
}

# set Date in right format
my $start = ParseDate( $vertrag->{'Start'} );
$vertrag->{'Start'} = UnixDate( $start, "%d.%m.%Y" );

# define additional text
my $zusatz = $werte->{'Zusatz'}->{'Zusatzvereinbarungen_(eine_Leerzeile_nach_jedem_Unterpunkt)'};
if( defined $zusatz ) {
    chomp $zusatz;
    $vertrag->{'Zusatz'} = $zusatz;
}

# Write LaTeX files
open( my $master, ">", "/home/fax/mieter/$meta->{'masterfilename'}.tex"); 
print $master "\%per convention\n\\input{mietvertrag/master.tex}\n";
close( $master );

open( my $mieter, ">", "/home/fax/mieter/$meta->{'filename'}.tex"); 
print $mieter "\%generated by mail\n";
foreach my $element (sort keys $vertrag) {
    print $mieter "\\newcommand{\\$element}\t\t{$vertrag->{$element}}\n";
}
close( $mieter );


system("cd /home/fax/mieter;pdflatex $meta->{'masterfilename'}.tex >/dev/null 2>/dev/null;pdflatex $meta->{'masterfilename'}.tex >/dev/null 2>/dev/null");

$/=$old;
# send mail with result
my $anhang  = "/home/fax/mieter/$meta->{'masterfilename'}.pdf";
my $sender  = Mail::Sender->new();
my $mailout = $sender->MailFile(
    {to   => $meta->{'receiverlist'},
     cc   => 'mietvertrag@burgstr-wr.de',
     from => 'mietvertrag@burgstr-wr.de',
     smtp => 'localhost',
     subject => 'Mietvertrag',
     msg  => "Im Anhang findet sich der Mietvertrag.",
     file => $anhang,
    });
$mailout->Close();

system("cd /home/fax/mieter;hg add $meta->{'masterfilename'}.tex $meta->{'filename'}.tex >/dev/null 2>/dev/null;hg commit -m'auto by mail2mietvertrag.pl' >/dev/null 2>/dev/null;hg status -in0 | xargs -0 rm;cd - >/dev/null 2>/dev/null");

exit 0;
