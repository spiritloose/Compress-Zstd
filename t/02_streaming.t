use strict;
use warnings;

use Test::More;
use Compress::Zstd;
use Compress::Zstd::Compressor qw(ZSTD_CSTREAM_IN_SIZE);
use Compress::Zstd::Decompressor qw(ZSTD_DSTREAM_IN_SIZE);

cmp_ok ZSTD_CSTREAM_IN_SIZE, '>', 0;
cmp_ok ZSTD_DSTREAM_IN_SIZE, '>', 0;

my $compressor = Compress::Zstd::Compressor->new;
isa_ok $compressor, 'Compress::Zstd::Compressor';
is $compressor->status(), 0;
my $output = '';
$output .= $compressor->compress('a');
$output .= $compressor->compress('b');
$output .= $compressor->compress('c');
$output .= $compressor->flush;
$output .= $compressor->end;
ok $output;

my $decompressor = Compress::Zstd::Decompressor->new;
isa_ok $decompressor, 'Compress::Zstd::Decompressor';
is $decompressor->status(), 0;
my $result = '';
$result .= $decompressor->decompress(substr($output, 0, 3));
isnt $decompressor->status(), 0;
ok ! $decompressor->isEndFrame();

$result .= $decompressor->decompress(substr($output, 3));
is $result, 'abc';
is $decompressor->status(), 0;
ok $decompressor->isEndFrame();


is decompress($output), 'abc';

{
    # Check can uncompress empty zstd buffer
    my $empty = "\x28\xb5\x2f\xfd\x24\x00\x01\x00\x00\x99\xe9\xd8\x51";

    my $decompressor = Compress::Zstd::Decompressor->new;
    isa_ok $decompressor, 'Compress::Zstd::Decompressor';
    my $result = '';
    $result .= $decompressor->decompress(substr($empty, 0, 3));
    isnt $decompressor->status(), 0;
    ok ! $decompressor->isEndFrame();

    $result .= $decompressor->decompress(substr($empty, 3));

    is $decompressor->status(), 0;
    ok $decompressor->isEndFrame();

    is $result, '';

    is decompress($empty), '';    
}

done_testing;
