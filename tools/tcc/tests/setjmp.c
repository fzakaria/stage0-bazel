/* Checks that longjmp returns to its caller with the caller's frame intact.

   mes-libc's x86-64 longjmp restored the wrong registers: %rbp got setjmp's
   own frame base rather than the caller's, and %rsp got the caller's frame
   base rather than the word past setjmp's. The caller therefore resumed with
   every local at the wrong offset and with the stack pointer above its own
   frame, so it read rubbish and then crashed on return. longjmp also never
   set %rax, which left setjmp's return value to chance.

   tinycc reports every compile error by longjmp-ing out of arbitrary depth,
   so this decided whether the compiler survived its own error path -- which
   is what a ./configure script exercises, repeatedly and by design.

   The test checks all three things the old implementation got wrong: the
   value setjmp returns, that a local written before setjmp still reads back
   correctly afterwards, and that the function can return normally. */

#include <stdio.h>
#include <setjmp.h>

static jmp_buf env;

/* A value distinguishable from both 0 and 1, so a longjmp that forgets to
   set the return value cannot pass by accident. */
#define JUMP_VALUE 42

/* Recurse before jumping, so the frame longjmp unwinds is not the one that
   called setjmp. */
#define JUMP_DEPTH 5

static void
deep (int depth)
{
  /* Padding so each frame is big enough that a wrong %rbp lands somewhere
     visibly different rather than by luck on the right slot. */
  char pad[64];
  pad[0] = (char) depth;

  if (depth > 0)
    {
      deep (depth - 1);
      return;
    }
  longjmp (env, JUMP_VALUE);
}

int
main ()
{
  int sentinel = 1;
  int value;

  value = setjmp (env);
  if (value == 0)
    {
      deep (JUMP_DEPTH);
      printf ("longjmp did not return\n");
      return 1;
    }

  if (value != JUMP_VALUE)
    {
      printf ("setjmp returned %d\n", value);
      return 1;
    }
  printf ("value ok\n");

  /* Written before setjmp, read after the jump: this is what a wrong %rbp
     corrupts. */
  if (sentinel != 1)
    {
      printf ("frame corrupt: %d\n", sentinel);
      return 1;
    }
  printf ("frame ok\n");

  /* Returning normally is what a wrong %rsp turns into a crash. */
  return 0;
}
