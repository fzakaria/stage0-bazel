/* printf's floating-point conversions, which are wrong in this toolchain.

   This is the reproducer for the fault that blocks GCC. Integers and strings
   format correctly; every floating-point conversion returns a value roughly
   9.6e6 times too small:

       printf ("%g", 5.0)   ->  5.21541e-07     (expected 5)
       printf ("%g", 1.5)   ->  1.56463e-07     (expected 1.5)
       printf ("%d", 42)    ->  42              (correct)

   Two packages fail through it, and both failures looked like something
   else until this was found.

   gawk stores every number as a double, so gawk 5.3.2 prints 1 for every
   numeric expression -- `print 2+3` gives 1 -- which made it look as though
   length() were broken. gawk 3.0.6 writes GCC's options.h, and emitted

       #define OPTION_MASK_ISA_64BIT (1 << 2.08617e-07)

   a float where a bit index belongs, which stopped the GCC build at
   gcc/config/i386/i386.h with "invalid constant in preprocessor
   expression". Neither gawk is at fault.

   musl's printf converts through long double and leans on frexpl, floorl
   and fmodl. tools/pkg/musl removes src/math/x86_64 because tinycc cannot
   assemble the x87 routines there or compile their SSE-constrained C
   companions, which leaves the portable ld80 implementations in src/math.
   Those, or tinycc's own x87 long double arithmetic, are where to look.

   The scale factor is suspiciously close to a power of two -- 5 divided by
   5.21541e-07 is about 9.587e6, near 2**23.2 -- which points at an exponent
   being handled wrongly rather than at arithmetic noise. */

#include <stdio.h>

int
main ()
{
  /* Integers first, to show the fault is specific to floating point. */
  printf ("int %d\n", 42);
  printf ("long %ld\n", 42L);
  printf ("string %s\n", "ok");

  printf ("g %g\n", 5.0);
  printf ("e %e\n", 5.0);
  printf ("f %f\n", 5.0);
  printf ("long double %Lg\n", (long double) 5.0);
  return 0;
}
