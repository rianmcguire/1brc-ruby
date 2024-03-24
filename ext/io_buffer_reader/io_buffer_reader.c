#include <ruby.h>
#include "ruby/io/buffer.h"

struct io_buffer_reader {
    void *base;
    size_t size;
    size_t offset;
};

size_t
io_buffer_reader_type_size(const void *_reader)
{
    return sizeof(struct io_buffer_reader);
}

static const rb_data_type_t io_buffer_reader_type = {
    .wrap_struct_name = "IO::Buffer::Reader",
    .function = {
        .dsize = io_buffer_reader_type_size,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE,
};

static inline struct io_buffer_reader *
io_buffer_reader_validate_state(VALUE self)
{
    struct io_buffer_reader *reader = NULL;
    TypedData_Get_Struct(self, struct io_buffer_reader, &io_buffer_reader_type, reader);

    if (reader->offset >= reader->size) {
        rb_raise(rb_eEOFError, "End of buffer");
    }

    return reader;
}

VALUE
io_buffer_reader_type_allocate(VALUE self)
{
    struct io_buffer_reader *reader = NULL;
    VALUE instance = TypedData_Make_Struct(self, struct io_buffer_reader, &io_buffer_reader_type, reader);

    return instance;
}

VALUE
io_buffer_reader_initialize(VALUE self, VALUE buffer, VALUE _offset)
{
    struct io_buffer_reader *reader = NULL;
    TypedData_Get_Struct(self, struct io_buffer_reader, &io_buffer_reader_type, reader);

    enum rb_io_buffer_flags flags = rb_io_buffer_get_bytes(buffer, &reader->base, &reader->size);
    if (!(flags & RB_IO_BUFFER_LOCKED)) {
        rb_raise(rb_eArgError, "buffer must be locked");
    }

    reader->offset = NUM2SIZET(_offset);

    return Qnil;
}

VALUE
io_buffer_reader_string_until(VALUE self, VALUE _terminator)
{
    struct io_buffer_reader *reader = io_buffer_reader_validate_state(self);

    char terminator = FIX2INT(_terminator);

    size_t max_length = reader->size - reader->offset;
    const char *start = (const char*)reader->base + reader->offset;
    const void *end = memchr(start, terminator, max_length);

    size_t length;
    if (end) {
        length = (const char*)end - start + 1;
    } else {
        length = max_length;
    }
    reader->offset += length;

    return rb_str_new(start, length);
}

VALUE
io_buffer_reader_parse_decimal_to_i(VALUE self)
{
    struct io_buffer_reader *reader = io_buffer_reader_validate_state(self);

    const char *base = (const char*)reader->base;

    bool neg = false;
    long value = 0;

    size_t i = reader->offset;
    if (base[i] == '-') {
        neg = true;
        i++;
    }
    for (; i < reader->size; i++) {
        char b = base[i];

        if (b >= '0' && b <= '9') {
            value *= 10;
            value += b - '0';
        } else if (b != '.') {
            break;
        }
    }

    if (neg) value *= -1;

    // Skip over terminating character
    reader->offset = i + 1;

    return INT2FIX(value);
}

VALUE
io_buffer_reader_offset(VALUE self)
{
    struct io_buffer_reader *reader = NULL;
    TypedData_Get_Struct(self, struct io_buffer_reader, &io_buffer_reader_type, reader);

    return INT2FIX(reader->offset);
}

void
Init_io_buffer_reader(void)
{
    VALUE cReader = rb_define_class_under(rb_cIOBuffer, "Reader", rb_cObject);
    rb_define_alloc_func(cReader, io_buffer_reader_type_allocate);

    rb_define_method(cReader, "initialize", io_buffer_reader_initialize, 2);
    rb_define_method(cReader, "string_until", io_buffer_reader_string_until, 1);
    rb_define_method(cReader, "parse_decimal_to_i", io_buffer_reader_parse_decimal_to_i, 0);
    rb_define_method(cReader, "offset", io_buffer_reader_offset, 0);
}
