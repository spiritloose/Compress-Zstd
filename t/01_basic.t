use strict;
use warnings;

use Test::More;
use Compress::Zstd;

my $src = 'Hello, World!';
ok my $compressed = compress($src, 42);
isnt $src, $compressed;
ok my $decompressed = decompress($compressed);
is uncompress($compressed), $decompressed, 'alias';
isnt $compressed, $decompressed;
is $decompressed, $src;

is decompress(\compress(\$src)), $src, 'ScalarRef';

decompress("1");

is ZSTD_VERSION_NUMBER, 10100;
is ZSTD_VERSION_STRING, '1.1.0';
is ZSTD_MAX_CLEVEL, 22;

done_testing;
