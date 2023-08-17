/*
 * MessagePack unpacking routine template
 *
 * Copyright (C) 2008-2010 FURUHASHI Sadayuki
 *
 *    Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE_1_0.txt or copy at
 *    http://www.boost.org/LICENSE_1_0.txt)
 */
#ifndef MSGPACK_PACK_DEFINE_H
#define MSGPACK_PACK_DEFINE_H

#include "msgpack/sysdep.h"
/* No <limits.h> so have to define it here */
#undef CHAR_MAX
#define CHAR_MAX    127
#undef CHAR_MIN
#define CHAR_MIN    -128

#ifdef SIZEOF_SHORT
#undef SIZEOF_SHORT
#endif
#ifdef SHRT_MAX
#undef SHRT_MAX
#endif
#ifdef USHRT_MAX
#undef USHRT_MAX
#endif

#ifdef SIZEOF_INT
#undef SIZEOF_INT
#endif
#ifdef INT_MAX
#undef INT_MAX
#endif
#ifdef UINT_MAX
#undef UINT_MAX
#endif

#ifdef SIZEOF_LONG
#undef SIZEOF_LONG
#endif
#ifdef LONG_MAX
#undef LONG_MAX
#endif
#ifdef ULONG_MAX
#undef ULONG_MAX
#endif

#ifdef SIZEOF_LONG_LONG
#undef SIZEOF_LONG_LONG
#endif
#ifdef LLONG_MAX
#undef LLONG_MAX
#endif
#ifdef ULLONG_MAX
#undef ULLONG_MAX
#endif
#include <string.h>

#endif /* msgpack/pack_define.h */

