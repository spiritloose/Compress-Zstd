#ifdef __cplusplus
extern "C" {
#endif
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#define NEED_sv_2pvbyte
#define NEED_newCONSTSUB
#include "ppport.h"
#include "zstd.h"
#include "compress/zstdmt_compress.h"

typedef struct Compress__Zstd__Compressor_s {
    ZSTD_CStream* stream;
    char* buf;
    size_t bufsize;
    size_t status ;
}* Compress__Zstd__Compressor;

typedef struct Compress__Zstd__Decompressor_s {
    ZSTD_DStream* stream;
    char* buf;
    size_t bufsize;
    size_t status ;
}* Compress__Zstd__Decompressor;

static SV*
decompress_using_streaming(pTHX_ const char* src, size_t srcSize)
{
    char* buf;
    size_t bufsize;
    SV* output;
    ZSTD_inBuffer inbuf = { src, srcSize, 0 };
    int iserror = 0;

    ZSTD_DStream* stream = ZSTD_createDStream();
    if (stream == NULL) {
        croak("Failed to call ZSTD_createDStream()");
    }
    ZSTD_initDStream(stream);

    bufsize = ZSTD_DStreamOutSize();
    Newx(buf, bufsize, char);

    output = newSVpv("", 0);
    while (inbuf.pos < inbuf.size) {
        ZSTD_outBuffer outbuf = { buf, bufsize, 0 };
        size_t ret = ZSTD_decompressStream(stream, &outbuf, &inbuf);
        if (ZSTD_isError(ret)) {
            iserror = 1;
            break;
        }
        sv_catpvn(output, outbuf.dst, outbuf.pos);
    }
    Safefree(buf);
    ZSTD_freeDStream(stream);
    if (iserror != 0) {
        SvREFCNT_dec(output);
        return NULL;
    }
    return output;
}

MODULE = Compress::Zstd PACKAGE = Compress::Zstd

BOOT:
{
    HV* stash = gv_stashpv("Compress::Zstd", 1);
    newCONSTSUB(stash, "ZSTD_VERSION_NUMBER", newSViv(ZSTD_VERSION_NUMBER));
    newCONSTSUB(stash, "ZSTD_VERSION_STRING", newSVpvs(ZSTD_VERSION_STRING));
    newCONSTSUB(stash, "ZSTD_MAX_CLEVEL", newSViv(ZSTD_maxCLevel()));
}

PROTOTYPES: DISABLE

void
compress(source, level = 1)
    SV* source;
    int level;
PREINIT:
    const char* src;
    STRLEN src_len;
    SV* dest;
    char* dst;
    size_t bound, ret;
PPCODE:
    if (SvROK(source)) {
        source = SvRV(source);
    }
    if (!SvOK(source)) {
        XSRETURN_UNDEF;
    }
    src = SvPVbyte(source, src_len);
    bound = ZSTD_compressBound(src_len);
    dest = sv_2mortal(newSV(bound + 1));
    dst = SvPVX(dest);
    ret = ZSTD_compress(dst, bound + 1, src, src_len, level);
    if (ZSTD_isError(ret)) {
        XSRETURN_UNDEF;
    }
    dst[ret] = '\0';
    SvCUR_set(dest, ret);
    SvPOK_on(dest);
    EXTEND(SP, 1);
    PUSHs(dest);

void
compress_mt(source, nbThreads, level = 1)
    SV* source;
    unsigned int nbThreads;
    int level;
PREINIT:
    const char* src;
    STRLEN src_len;
    SV* dest;
    char* dst;
    size_t bound, ret;
    ZSTDMT_CCtx* cctx;
PPCODE:
    if (SvROK(source)) {
        source = SvRV(source);
    }
    if (!SvOK(source)) {
        XSRETURN_UNDEF;
    }
    cctx = ZSTDMT_createCCtx(nbThreads);
    src = SvPVbyte(source, src_len);
    bound = ZSTD_compressBound(src_len);
    dest = sv_2mortal(newSV(bound + 1));
    dst = SvPVX(dest);
    ret = ZSTDMT_compressCCtx(cctx, dst, bound + 1, src, src_len, level);
    ZSTDMT_freeCCtx(cctx);
    if (ZSTD_isError(ret)) {
        XSRETURN_UNDEF;
    }
    dst[ret] = '\0';
    SvCUR_set(dest, ret);
    SvPOK_on(dest);
    EXTEND(SP, 1);
    PUSHs(dest);

void
decompress(source)
    SV* source;
ALIAS:
    uncompress = 1
PREINIT:
    const char* src;
    STRLEN src_len;
    unsigned long long dest_len;
    SV* dest;
    char* dst;
    size_t ret;
PPCODE:
    if (SvROK(source)) {
        source = SvRV(source);
    }
    if (!SvOK(source)) {
        XSRETURN_UNDEF;
    }
    src = SvPVbyte(source, src_len);
    dest_len = ZSTD_getFrameContentSize(src, src_len);
    if (dest_len == ZSTD_CONTENTSIZE_UNKNOWN) {
        SV* output = decompress_using_streaming(aTHX_ src, src_len);
        if (output == NULL) {
            XSRETURN_UNDEF;
        }
        EXTEND(SP, 1);
        mPUSHs(output);
        XSRETURN(1);
    }
    if (dest_len == ULLONG_MAX || ZSTD_isError(dest_len)) {
        XSRETURN_UNDEF;
    }
    dest = sv_2mortal(newSV(dest_len + 1));
    dst = SvPVX(dest);
    ret = ZSTD_decompress(dst, dest_len + 1, src, src_len);
    if (ZSTD_isError(ret)) {
        XSRETURN_UNDEF;
    }
    dst[ret] = '\0';
    SvCUR_set(dest, ret);
    SvPOK_on(dest);
    EXTEND(SP, 1);
    PUSHs(dest);
    XSRETURN(1);

MODULE = Compress::Zstd PACKAGE = Compress::Zstd::Compressor

PROTOTYPES: DISABLE

BOOT:
{
    HV* stash = gv_stashpv("Compress::Zstd::Compressor", 1);
    newCONSTSUB(stash, "ZSTD_CSTREAM_IN_SIZE", newSViv(ZSTD_CStreamInSize()));
}

Compress::Zstd::Compressor
new(klass, level = 1)
    const char* klass;
    int level;
PREINIT:
    Compress__Zstd__Compressor self;
    char* buf;
    size_t bufsize;
CODE:
    ZSTD_CStream* stream = ZSTD_createCStream();
    if (stream == NULL) {
        croak("Failed to call ZSTD_createCStream()");
    }
    ZSTD_initCStream(stream, level);

    Newx(self, sizeof(struct Compress__Zstd__Compressor_s), struct Compress__Zstd__Compressor_s);
    self->stream = stream;
    bufsize = ZSTD_CStreamOutSize();
    Newx(buf, bufsize, char);
    self->buf = buf;
    self->bufsize = bufsize;
    RETVAL = self;
OUTPUT:
    RETVAL

void
init(self, level = 1)
    Compress::Zstd::Compressor self;
    int level;
CODE:
    ZSTD_initCStream(self->stream, level);

SV*
compress(self, input)
    Compress::Zstd::Compressor self;
    SV* input;
PREINIT:
    STRLEN len;
    SV* output;
CODE:
    const char* in = SvPVbyte(input, len);
    ZSTD_inBuffer inbuf = { in, len, 0 };
    output = newSVpv("", 0);
    while (inbuf.pos < inbuf.size) {
        ZSTD_outBuffer outbuf = { self->buf, self->bufsize, 0 };
        size_t toread = self->status = ZSTD_compressStream(self->stream, &outbuf, &inbuf);
        if (ZSTD_isError(toread)) {
            croak("%s", ZSTD_getErrorName(toread));
        }
        sv_catpvn(output, outbuf.dst, outbuf.pos);
    }
    RETVAL = output;
OUTPUT:
    RETVAL

SV*
flush(self)
    Compress::Zstd::Compressor self;
PREINIT:
    SV* output;
    size_t ret;
CODE:
    output = newSVpv("", 0);
    do {
        ZSTD_outBuffer outbuf = { self->buf, self->bufsize, 0 };
        ret = self->status = ZSTD_flushStream(self->stream, &outbuf);
        if (ZSTD_isError(ret)) {
            croak("%s", ZSTD_getErrorName(ret));
        }
        sv_catpvn(output, outbuf.dst, outbuf.pos);
    } while (ret > 0);
    RETVAL = output;
OUTPUT:
    RETVAL

SV*
end(self)
    Compress::Zstd::Compressor self;
PREINIT:
    SV* output;
    size_t ret;
CODE:
    output = newSVpv("", 0);
    do {
        ZSTD_outBuffer outbuf = { self->buf, self->bufsize, 0 };
        ret = self->status = ZSTD_endStream(self->stream, &outbuf);
        if (ZSTD_isError(ret)) {
            croak("%s", ZSTD_getErrorName(ret));
        }
        sv_catpvn(output, outbuf.dst, outbuf.pos);
    } while (ret > 0);
    RETVAL = output;
OUTPUT:
    RETVAL


size_t
status(self)
    Compress::Zstd::Compressor self;
CODE:
    RETVAL = self->status;
OUTPUT:
    RETVAL

unsigned
isError(self)
    Compress::Zstd::Compressor self;
CODE:
    RETVAL = ZSTD_isError(self->status);
OUTPUT:
    RETVAL


const char *
getErrorName(self)
    Compress::Zstd::Compressor self;
CODE:
    RETVAL = ZSTD_getErrorName(self->status);
OUTPUT:
    RETVAL

void
DESTROY(self)
    Compress::Zstd::Compressor self;
CODE:
    ZSTD_freeCStream(self->stream);
    Safefree(self->buf);
    Safefree(self);

MODULE = Compress::Zstd PACKAGE = Compress::Zstd::Decompressor

PROTOTYPES: DISABLE

BOOT:
{
    HV* stash = gv_stashpv("Compress::Zstd::Decompressor", 1);
    newCONSTSUB(stash, "ZSTD_DSTREAM_IN_SIZE", newSViv(ZSTD_DStreamInSize()));
}

Compress::Zstd::Decompressor
new(klass)
    const char* klass;
PREINIT:
    Compress__Zstd__Decompressor self;
    char* buf;
    size_t bufsize;
CODE:
    ZSTD_DStream* stream = ZSTD_createDStream();
    if (stream == NULL) {
        croak("Failed to call ZSTD_createDStream()");
    }
    ZSTD_initDStream(stream);

    Newx(self, sizeof(struct Compress__Zstd__Decompressor_s), struct Compress__Zstd__Decompressor_s);
    self->stream = stream;
    bufsize = ZSTD_DStreamOutSize();
    Newx(buf, bufsize, char);
    self->buf = buf;
    self->bufsize = bufsize;
    RETVAL = self;
OUTPUT:
    RETVAL

void
init(self)
    Compress::Zstd::Decompressor self;
CODE:
    ZSTD_initDStream(self->stream);

SV*
decompress(self, input)
    Compress::Zstd::Decompressor self;
    SV* input;
PREINIT:
    STRLEN len;
    SV* output;
CODE:
    const char* in = SvPVbyte(input, len);
    ZSTD_inBuffer inbuf = { in, len, 0 };
    output = newSVpv("", 0);
    while (inbuf.pos < inbuf.size) {
        ZSTD_outBuffer outbuf = { self->buf, self->bufsize, 0 };
        size_t ret = self->status = ZSTD_decompressStream(self->stream, &outbuf, &inbuf);
        if (ZSTD_isError(ret)) {
            croak("%s", ZSTD_getErrorName(ret));
        }
        sv_catpvn(output, outbuf.dst, outbuf.pos);
    }
    RETVAL = output;
OUTPUT:
    RETVAL

size_t
status(self)
    Compress::Zstd::Decompressor self;
CODE:
    RETVAL = self->status;
OUTPUT:
    RETVAL

unsigned
isError(self)
    Compress::Zstd::Decompressor self;
CODE:
    RETVAL = ZSTD_isError(self->status);
OUTPUT:
    RETVAL

unsigned
isEndFrame(self)
    Compress::Zstd::Decompressor self;
CODE:
    RETVAL = self->status == 0;
OUTPUT:
    RETVAL

const char *
getErrorName(self)
    Compress::Zstd::Decompressor self;
CODE:
    RETVAL = ZSTD_getErrorName(self->status);
OUTPUT:
    RETVAL

void
DESTROY(self)
    Compress::Zstd::Decompressor self;
CODE:
    ZSTD_freeDStream(self->stream);
    Safefree(self->buf);
    Safefree(self);
