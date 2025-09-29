#include "picohttp.h"

VALUE rb_mPicohttp;

RUBY_FUNC_EXPORTED void
Init_picohttp(void)
{
  rb_mPicohttp = rb_define_module("Picohttp");
}
