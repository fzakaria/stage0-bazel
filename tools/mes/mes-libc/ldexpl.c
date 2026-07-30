/* ldexpl for the mes C library.

   tinycc calls this when it parses a floating point literal, and mes-libc
   does not provide it. nixpkgs' minimal-bootstrap takes a copy from an
   unreleased branch of mes; that file is not fetchable from anywhere stable,
   so this is a fresh implementation rather than a vendored one -- which also
   keeps it inside the audited graph as ordinary source.

   Scaling by a power of two is exact in binary floating point, so repeated
   multiplication gives the same answer as manipulating the exponent field
   directly, without needing to know the layout of a long double. The loop is
   linear in the exponent, but the only caller is a compiler reading a literal
   and the values involved are small. */

long double
ldexpl (long double x, int exponent)
{
  long double result = x;
  int i;

  if (exponent > 0)
    {
      for (i = 0; i < exponent; i = i + 1)
        {
          result = result * 2.0;
        }
      return result;
    }

  for (i = 0; i < -exponent; i = i + 1)
    {
      result = result / 2.0;
    }

  return result;
}
