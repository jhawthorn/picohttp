# frozen_string_literal: true

require "mkmf"

# Makes all symbols private by default to avoid unintended conflict
# with other gems. To explicitly export symbols you can use RUBY_FUNC_EXPORTED
# selectively, or entirely remove this flag.
append_cflags("-fvisibility=hidden")

# Check for Ractor support
have_func("rb_ext_ractor_safe", "ruby.h")

create_makefile("picohttp/picohttp")
