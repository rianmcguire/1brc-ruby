#include <ruby.h>
#include "ruby/io/buffer.h"

static VALUE
io_buffer_get_string_until(VALUE self, VALUE _offset, VALUE _terminator)
{
    // TODO: handle negative offset?
    size_t offset = NUM2SIZET(_offset);
    unsigned char terminator = FIX2INT(_terminator);

    const void *base;
    size_t size;
    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    if (offset > size) {
        rb_raise(rb_eArgError, "Specified offset is bigger than the buffer size!");
    }

    const char *start = (const char*)base + offset;
    const void *end = memchr(start, terminator, size - offset);

    size_t length;
    if (end) {
        // Include the terminator byte in the string
        length = (const char*)end - start + 1;
    } else {
        // Nothing found - return remainder of buffer
        length = size - offset;
    }

    return rb_str_new(start, length);
}

void
Init_io_buffer_hacks(void)
{
    rb_ext_ractor_safe(true);
    rb_define_method(rb_cIOBuffer, "get_string_until", io_buffer_get_string_until, 2);
}
