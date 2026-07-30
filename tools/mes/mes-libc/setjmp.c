/* setjmp and longjmp for x86-64, replacing mes-libc's.

   Upstream's lib/x86_64-mes-gcc/setjmp.c saves the right three words and then
   restores them into the wrong registers:

       mov 0x00(%rdi),%rbp     // setjmp's own frame base
       mov 0x08(%rdi),%rbx     // the return address
       mov 0x10(%rdi),%rsp     // the caller's frame base
       jmp *%rbx

   %rbp has to come back as the *caller's* frame base, not setjmp's, or every
   local in the caller is addressed at the wrong offset. %rsp has to come back
   as the word past setjmp's frame, not as the caller's frame base, or the
   stack pointer sits above the caller's own locals and returning pops
   rubbish. Upstream also never loads %rax, so the value setjmp appears to
   return is whatever the last expression happened to leave there.

   tinycc reports every compile error by longjmp-ing out of arbitrary depth,
   which makes this the difference between a compiler that survives a failed
   ./configure check and one that segfaults on it.

   The saved layout is unchanged, so this stays compatible with anything else
   in the library that reads a jmp_buf:

       __bp  setjmp's frame base           (%rbp inside setjmp)
       __pc  the return address into the caller
       __sp  the caller's frame base       (the saved %rbp)

   longjmp does its work in one asm block with no C before it, so that the
   incoming arguments are still in %rdi and %esi where the System V ABI put
   them. That is the same assumption upstream makes. */

#include <setjmp.h>
#include <stdlib.h>

void
longjmp (jmp_buf env, int val)
{
  // *INDENT-OFF*
  asm (
       /* setjmp must never appear to return 0, so a val of 0 becomes 1. */
       "testl  %esi,%esi\n\t"
       "jnz    .Lmes_longjmp_value\n\t"
       "movl   $1,%esi\n\t"
       ".Lmes_longjmp_value:\n\t"
       /* The value setjmp returns. Loaded before %rsp and %rbp move, while
          the arguments are still reachable. */
       "movl   %esi,%eax\n\t"

       "mov    0x10(%rdi),%rbp\n\t"     /* env->__sp: the caller's frame */
       "mov    0x08(%rdi),%rbx\n\t"     /* env->__pc: the return address */
       "mov    0x00(%rdi),%rsp\n\t"     /* env->__bp: setjmp's frame base */
       /* Step over the saved %rbp and the return address that frame base
          points at, leaving %rsp where it was just after setjmp returned. */
       "add    $0x10,%rsp\n\t"
       "jmp    *%rbx\n\t"
       );
  // *INDENT-ON*
  /* Not reached: the jump above does not come back. */
  exit (42);
}

int
setjmp (jmp_buf env)
{
  long *p;

  /* %rbp addresses this frame: p[0] is the caller's saved %rbp and p[1] is
     the address to return to inside the caller. */
  // *INDENT-OFF*
  asm ("mov    %%rbp,%0"
       : "=r" (p)
       : /* no inputs */
       );
  // *INDENT-ON*
  env[0].__bp = (long) p;
  env[0].__pc = p[1];
  env[0].__sp = p[0];
  return 0;
}
