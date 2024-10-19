#!/usr/bin/env -S ruby --yjit-disable --yjit-call-threshold=1
#!/usr/bin/env -S ruby --yjit-disable --yjit-call-threshold=1 --yjit-dump-disasm
#!/usr/bin/env -S ruby

# frozen_string_literal: true

def allocations
    x = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - x
end

$stations = {"ell" => 100}

def foo(buffer)
    $stations[buffer.byteslice(1, 3)]
end

RubyVM::YJIT.enable

puts RubyVM::InstructionSequence.of(method(:foo)).disasm
puts

# Warm up
allocations { foo("Hello world!") }

puts "Result:"
p foo("Hello world!")

puts "Allocations:"
p allocations { foo("Hello world!") }
