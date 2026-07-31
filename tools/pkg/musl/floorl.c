/* floorl for x86-64, replacing musl's.

   musl's portable ld80 floorl works by picking the long double apart through
   a union and clearing mantissa bits below the binary point. tinycc gets that
   wrong here: floorl(5.7) returns 4 rather than 5.

   That single result is what blocked GCC. musl's printf generates digits with
   floorl, so every floating-point conversion came out roughly 9.6e6 times too
   small -- printf("%g", 5.0) gave 5.21541e-07. gawk stores all numbers as
   doubles, so gawk 5.3.2 printed 1 for every numeric expression and gawk
   3.0.6 wrote `(1 << 2.08617e-07)` into GCC's options.h. See
   tools/tcc/musl/tests/printf_float.c.

   This implementation avoids bit manipulation entirely. A long double on
   x86-64 has a 64-bit mantissa, so any value of magnitude 2**63 or greater is
   already an integer and is returned untouched; everything smaller fits in a
   long long, and truncation toward zero differs from flooring only for
   negative values with a fractional part. */

/* 2**63. At or above this magnitude an ld80 value has no fractional part,
   and the conversion below would overflow. */
#define LDBL_INTEGRAL_THRESHOLD 9223372036854775808.0L

long double
floorl (long double x)
{
  long long truncated;
  long double result;

  /* NaN compares false against everything, so test it before the range
     check rather than relying on one. */
  if (x != x)
    return x;

  if (x >= LDBL_INTEGRAL_THRESHOLD || x <= -LDBL_INTEGRAL_THRESHOLD)
    return x;

  truncated = (long long) x;
  result = (long double) truncated;

  /* Truncation rounds toward zero, so a negative value with a fractional
     part has been rounded up and needs one subtracted. */
  if (result > x)
    result -= 1.0L;

  return result;
}
