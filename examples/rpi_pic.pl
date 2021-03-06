#!/usr/bin/perl
use v5.12;
use warnings;
use GStreamer1;
use Glib qw( TRUE FALSE );

# Get a jpeg image from the Raspberry Pi camera.  This requires the rpicamsrc 
# gst plugin, which you can download and compile from:
#
# https://github.com/thaytan/gst-rpicamsrc
#
# Duplicates this command line:
#
# gst-launch-1.0 rpicamsrc ! h264parse ! 'video/x-h264,width=800,height=600' \
#    ! avdec_h264 ! jpegenc quality=50 ! filesink location=output.jpg
#
# Except that we use an appsink to get the jpeg and then save it.
#

my $OUT_FILE = shift || die "Need file to save to\n";


sub dump_to_file
{
    my ($output_file, $jpeg_data) = @_;
    my @jpeg_bytes = @$jpeg_data;
    say "Got jpeg, saving " . scalar(@jpeg_bytes) . " bytes . . . ";

    open( my $fh, '>', $output_file ) or die "Can't open '$output_file': $!\n";
    binmode $fh;
    print $fh pack( 'C*', @jpeg_bytes );
    close $fh;

    say "Saved jpeg to $output_file (size: " . (-s $output_file) . ")";
    return 1;
}

sub get_catch_sample_callback
{
    my ($appsink, $pipeline) = @_;
    return sub {
        my $jpeg_sample = $appsink->pull_sample;

warn "Got sample\n";
        my $jpeg_buf = $jpeg_sample->get_buffer;
        my $size = $jpeg_buf->get_size;
        my $buf = $jpeg_buf->extract_dup( 0, $size, undef, $size );
        dump_to_file( $OUT_FILE, $buf );

        $pipeline->set_state( 'null' );
        return 1;
    };
}

sub get_catch_handoff_callback
{
    my ($pipeline, $loop) = @_;
    return sub {
        my ($sink, $data_buf, $pad) = @_;
        my $size = $data_buf->get_size;
        my $buf = $data_buf->extract_dup( 0, $size, undef, $size );
        dump_to_file( $OUT_FILE, $buf );

        $pipeline->set_state( 'null' );
        $loop->quit;
        return 1;
    };
}

sub bus_watch
{
    my ($bus, $msg) = @_;
    warn "Got bus message: " . $msg . "\n";
    return 1;
}


GStreamer1::init([ $0, @ARGV ]);
my $loop = Glib::MainLoop->new( undef, FALSE );
my $pipeline = GStreamer1::Pipeline->new( 'pipeline' );

my $rpi        = GStreamer1::ElementFactory::make( rpicamsrc => 'and_who' );
my $h264parse  = GStreamer1::ElementFactory::make( h264parse => 'are_you' );
my $capsfilter = GStreamer1::ElementFactory::make(
    capsfilter => 'the_proud_lord_said' );
my $avdec_h264 = GStreamer1::ElementFactory::make(
    avdec_h264 => 'that_i_should_bow_so_low' );
my $jpegenc    = GStreamer1::ElementFactory::make( jpegenc => 'only_a_cat' );
my $sink  = GStreamer1::ElementFactory::make(
    fakesink => 'of_a_different_coat' );

my $caps = GStreamer1::Caps::Simple->new( 'video/x-h264',
    width  => 'Glib::Int' => 800,
    height => 'Glib::Int' => 600,
);
$capsfilter->set( caps => $caps );

$sink->set( 'signal-handoffs' => TRUE );
$sink->signal_connect(
    $_ => get_catch_handoff_callback( $pipeline, $loop ),
) for 'handoff', 'preroll-handoff';


my @link = ( $rpi, $h264parse, $capsfilter, $avdec_h264, $jpegenc, $sink );
$pipeline->add( $_ ) for @link;
foreach my $i (0 .. $#link) {
    last if ! exists $link[$i+1];
    my $this = $link[$i];
    my $next = $link[$i+1];
    $this->link( $next );
}

warn "Starting pipeline . . . \n";
$pipeline->set_state( "playing" );
$loop->run;
