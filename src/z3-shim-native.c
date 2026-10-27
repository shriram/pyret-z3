/* Small C helper linked into the Z3 WebAssembly module.
 *
 * Z3's default C-API error handler prints a message and calls exit(), which
 * would tear down the Emscripten runtime inside the Pyret process. We install
 * a handler that does nothing; the shim then reads Z3_get_error_code and
 * Z3_get_error_msg after each call and raises a Pyret error instead.
 */
#include "z3.h"

#ifdef __cplusplus
extern "C" {
#endif

static void z3shim_noop_error_handler(Z3_context c, Z3_error_code e) {
  (void)c;
  (void)e;
}

void z3shim_install_error_handler(Z3_context c) {
  Z3_set_error_handler(c, z3shim_noop_error_handler);
}

#ifdef __cplusplus
}
#endif
