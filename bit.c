#define BIT_PROJECT "Bit-Serial CPU Simulator"
#define BIT_AUTHOR  "Richard James Howe"
#define BIT_EMAIL   "howe.r.j.89@gmail.com"
#define BIT_REPO    "https://github.com/howerj/bit-serial"
#define BIT_LICENSE "MIT"
#ifdef __unix__
#include <sys/select.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#define __USE_POSIX199309
#define _POSIX_C_SOURCE 199309L
#endif
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MSIZE (8192u)
#define ESCAPE (27)

#ifndef CONFIG_BIT_SLEEP_EVERY_X_CYCLES
#define CONFIG_BIT_SLEEP_EVERY_X_CYCLES /*(64 * 1024)*/(0)
#endif

#ifndef CONFIG_BIT_SLEEP_PERIOD_MS
#define CONFIG_BIT_SLEEP_PERIOD_MS (5)
#endif

#ifndef CONFIG_BIT_INCLUDE_DEFAULT_IMAGE
#define CONFIG_BIT_INCLUDE_DEFAULT_IMAGE (1)
#endif

typedef uint16_t mw_t; /* machine word */

typedef struct {
	mw_t pc, acc, flg, m[MSIZE];
	FILE *in, *out, *err;
	mw_t ch, leds, switches;
	long done, bp1, sleep_ms, sleep_every;
	int error, blocking, command, debug, tron, step;
#ifdef __unix__
	struct termios newattr, oldattr; /* ugly, but needed for Unix only */
#endif
} bcpu_t;

enum { fCy, fZ, fNg, fR, fHLT, };

static int handler(bcpu_t *b, int code) {
	if (b->error == 0)
		b->error = code;
	return b->error;
}

#define error(B) handler((B), -__LINE__)

#ifdef __unix__ /* unix junk... */
extern int fileno(FILE *file);

static int os_getch(bcpu_t *b) {
	assert(b);
	return fgetc(b->in);
}

static void sleep_us(const unsigned long microseconds) {
	struct timespec ts = {
		.tv_sec  = (microseconds / 1000000ul),
		.tv_nsec = (microseconds % 1000000ul) * 1000ul,
	};
	nanosleep(&ts, NULL);
}

static void os_sleep_ms(bcpu_t *b, unsigned ms) {
	assert(b);
	sleep_us(ms * 1000ul);
}

static int unix_nonblocking_off(bcpu_t *b) {
	assert(b);
	assert(b->in);
	const int fd = fileno(b->in);
	return b->blocking || !isatty(fd);
}

static int os_kbhit(bcpu_t *b) {
	assert(b);
	const int fd = fileno(b->in);
	if (unix_nonblocking_off(b))
		return 1;
	if (b->sleep_ms)
		os_sleep_ms(b, b->sleep_ms);
	int bytes = 0;
	ioctl(fd, FIONREAD, &bytes);
	return !!bytes;
}

static int os_init(bcpu_t *b) {
	assert(b);
	const int fd = fileno(b->in);
	if (unix_nonblocking_off(b))
		return 0;
	if (tcgetattr(fd, &b->oldattr) < 0)
		return error(b);
	b->newattr = b->oldattr;
	b->newattr.c_iflag &= ~(ICRNL);
	b->newattr.c_lflag &= ~(ICANON | ECHO);
	if (tcsetattr(fd, TCSANOW, &b->newattr) < 0)
		return error(b);
	return 0;
}

static int os_raw(bcpu_t *b) { 
	assert(b); 
	if (unix_nonblocking_off(b))
		return 0;
	return tcsetattr(fileno(b->in), TCSANOW, &b->newattr) < 0 ? -1 : 0;
}

static int os_cooked(bcpu_t *b) { 
	assert(b); 
	if (unix_nonblocking_off(b))
		return 0;
	return tcsetattr(fileno(b->in), TCSANOW, &b->oldattr) < 0 ? -1 : 0;
}

static int os_deinit(bcpu_t *b) {
	assert(b);
	return os_cooked(b);
}
#else
#ifdef _WIN32
#include <windows.h>
#include <io.h>
extern int getch(void);
extern int kbhit(void);
/*extern int _isatty(int fd);*/
extern int _fileno(FILE *stream);
static int os_getch(bcpu_t *b) { assert(b); return b->in == stdin && _isatty(_fileno(b->in)) ? getch() : fgetc(b->in); }
static int os_kbhit(bcpu_t *b) { assert(b); Sleep(1); return _isatty(_fileno(b->in)) ? kbhit() : 1; } /* WTF? */
static void os_sleep_ms(bcpu_t *b, unsigned ms) { assert(b); Sleep(ms); }
static int os_init(bcpu_t *b) { assert(b); return 0; }
static int os_deinit(bcpu_t *b) { assert(b); return 0; }
static int os_raw(bcpu_t *b) { assert(b); return 0; }
static int os_cooked(bcpu_t *b) { assert(b); return 0; }

#else
static int os_kbhit(bcpu_t *b) { assert(b); return 1; }
static int os_getch(bcpu_t *b) { assert(b); return fgetc(b->in); }
static void os_sleep_ms(bcpu_t *b, unsigned ms) { assert(b); (void)ms; }
static int os_init(bcpu_t *b) { assert(b); return 0; }
static int os_deinit(bcpu_t *b) { assert(b); return 0; }
static int os_raw(bcpu_t *b) { assert(b); return 0; }
static int os_cooked(bcpu_t *b) { assert(b); return 0; }
#endif
#endif /** __unix__ **/

static int wrap_getch(bcpu_t *b) {
	assert(b);
	const int ch = os_getch(b);
	if (ch == ESCAPE) {
		if (b->debug) {
			b->command = 1;
			return ch; /* cannot eliminate returned char... */
		} else {
			b->done = 1;
		}
	} else if (ch < 0) {
		b->done = 1;
	}
	return ch;
}

static int wrap_putch(bcpu_t *b, const int ch) {
	assert(b);
	const int r = fputc(ch, b->out);
	if (fflush(b->out) < 0)
		return error(b);
	return r;
}

static inline unsigned bits(unsigned b) {
	unsigned r = 0;
	do if (b & 1) r++; while (b >>= 1);
	return r;
}

static inline mw_t add(mw_t a, mw_t b, mw_t *carry) {
	assert(carry);
	const mw_t r = a + b;
	*carry &= ~(1u << fCy);
	if (r < a && r < b)
		*carry |= (1u << fCy);
	return r;
}

static inline mw_t bload(bcpu_t *b, mw_t addr) {
	assert(b);
	if (!(0x4000ul & addr))
		return b->m[addr % MSIZE];
	switch (addr & 0x7) {
	case 0: return b->switches;
	case 1: return (!os_kbhit(b) << 8ul) | (b->ch & 0xFF);
	}
	return 0;
}

static inline void bstore(bcpu_t *b, mw_t addr, mw_t val) {
	assert(b);
	if (!(0x4000ul & addr)) {
		if (addr >= MSIZE)
			return;
		b->m[addr % MSIZE] = val;
		return;
	}
	switch (addr & 0x7) {
	case 0: b->leds = val; break;
	case 1: if (val & (1u << 13)) {
			wrap_putch(b, val & 0xFFu);
			fflush(b->out);
		}
		if (val & (1u << 10))
			b->ch = wrap_getch(b);
		break;
	case 2: /* TX control */ break;
	case 3: /* RX control */ break;
	case 4: /* UART control */ break;
	}
}

static inline void rload(bcpu_t *b, uint16_t *pc, uint16_t *acc, uint16_t *flg) {
	assert(b);
	assert(pc);
	assert(acc);
	assert(flg);
	*pc = b->pc;
	*acc = b->acc;
	*flg = b->flg;
}

static inline void rsave(bcpu_t *b, uint16_t pc, uint16_t acc, uint16_t flg) {
	assert(b);
	b->pc = pc;
	b->acc = acc;
	b->flg = flg;
}

static const char *dis(const uint16_t instr) {
	uint16_t cmd = instr >> 12;
	const char *r = NULL;
	switch (cmd) {
	case 0x0: r = " OR"; break; case 0x1: r = "AND"; break;
	case 0x2: r = "XOR"; break; case 0x3: r = "ADD"; break;
	case 0x4: r = "LSH"; break; case 0x5: r = "RSH"; break;
	case 0x6: r = "LDI"; break; case 0x7: r = "STI"; break;
	case 0x8: r = "LDC"; break; case 0x9: r = "STC"; break;
	case 0xA: r = "LIT"; break; case 0xB: r = "XXX"; break;
	case 0xC: r = "JMP"; break; case 0xD: r = "JPZ"; break;
	case 0xE: r = instr & 1 ? "SFG" : "SPC"; break; 
	case 0xF: r = instr & 1 ? "GFG" : "GPC"; break;
	}
	assert(r);
	return r;
}

static char *flags(uint16_t flg, char buf[static 16 + 1]) {
	const char off = '-';
	buf[0] = flg & (1 << fHLT) ? 'H' : off;
	buf[1] = flg & (1 << fR)   ? 'R' : off;
	buf[2] = flg & (1 << fNg)  ? 'N' : off;
	buf[3] = flg & (1 << fZ)   ? 'Z' : off;
	buf[4] = flg & (1 << fCy)  ? 'C' : off;
	buf[5] = 0;
	return buf;
}

static int command(bcpu_t *b, uint16_t *pc, uint16_t *acc, uint16_t *flg) {
	assert(b);
	assert(pc);
	assert(acc);
	assert(flg);
	rsave(b, *pc, *acc, *flg);
	static const char *help = "Debug Command Prompt Help\n\n\
\th       : print this help message\n\
\tq       : quit system\n\
\tt       : set tracing on (default = on)\n\
\ts       : set single step on (default = on)\n\
\tb <HEX> : set break point to hex value (single bp only)\n\
\tk       : clear tracing, single step and break point\n\
\tc       : continue\n\
\tr       : set reset flag\n\
\tj <HEX> : jump to address\n\
\td <X:Y> : hex dump from `X` for `Y` words\n\
\t?       : print system state\n\
\t@ <HEX> : load *word not byte* address\n\
\t! <X:Y> : store `Y` at *word address not byte address* `X`\n\n";
again: 
	{
	char line[64] = { 0, }, cmd[2] = { 0, };
	long arg1 = 0, arg2 = 0, argc = 0;
	if (os_cooked(b) < 0) 
		return error(b);
	if (b->pc == b->bp1)
		if (fprintf(b->err, "BREAK\r\n") < 0)
			return error(b);
	if (feof(b->in)) {
		b->done = 1;
		return 0;
	}
	if (fprintf(b->err, "DBG:%04X> ", b->pc) < 0)
		return error(b);
	if (!fgets(line, sizeof(line), b->in))
		return 0;
	if ((argc = sscanf(line, "%1s %lx:%lx", cmd, &arg1, &arg2)) >= 1) {
		switch (cmd[0]) { /* Could add: assemble instructions, save to file,  etcetera, much like DEBUG.COM from MS-DOS */
		case 'h': if (fputs(help, b->err) < 0) return error(b); goto again;
		case 'q': b->done = 1; break;
		case 't': b->tron = 1; goto again;
		case 's': b->step = 1; break;
		case 'b': b->bp1 = argc > 1 ? arg1 : -1; if (fprintf(b->err, " break set: %lX\r\n", b->bp1) < 0) return error(b); goto again;
		case 'k': b->tron = 0; b->step = 0; b->bp1 = -1; goto again;
		case 'c': b->step = 0; break;
		case 'r': b->flg |= 1 << fR; goto again;
		case 'j': b->pc = argc > 1 ? arg1 : 0; goto again;
		case '@': if (fprintf(b->err, "%04X\r\n", bload(b, arg1)) < 0) return error(b); goto again;
		case '!': bstore(b, arg1, arg2); goto again; /* Example: "! 4001:2058" */
		case '?': if (fprintf(b->err, 
				"PC:%04X AC:%04X FL:%04X TRON:%d STEP:%d BLOCK:%d BP:%ld SLEEP-MS:%ld SLEEP-EVERY:%ld SW:%d LED:%d\r\n", 
				b->pc, b->acc, b->flg, b->tron, b->step, b->blocking, b->bp1, b->sleep_ms, b->sleep_every, b->switches, b->leds) < 0)
				return error(b);
			goto again;
		case 'd': {
			const long start = argc < 3 ? b->pc : arg1;
			const long length = argc < 3 ? arg1 : arg2;
			for (long i = 0, j = 0; i < length; i++, j++) {
				if (fprintf(b->err, "%04X ", b->m[(i + start) % MSIZE]) < 0)
					return error(b);
				if (j > 7) {
					if (fprintf(b->err, "\r\n") < 0)
						return error(b);
					j = 0;
				}
			}
			if (fprintf(b->err, "\r\n") < 0)
				return error(b);
		} goto again;
		case '\n': case '\r': case ' ': break;
		default: if (fprintf(b->err, "invalid command '%s'\r\n", cmd) < 0) return error(b); break;
		}
		if (fprintf(b->err, "\r\n") < 0)
			return error(b);
	}
	}
	b->command = b->step;
	if (os_raw(b) < 0) return error(b);
	rload(b, pc, acc, flg);
	return 0;
}

static inline int bcpu(bcpu_t *b) {
	assert(b);
	int r = 0;
	mw_t * const m = b->m, pc = 0, acc = 0, flg = 0;
	rload(b, &pc, &acc, &flg);

	for (unsigned count = 0; b->done == 0; count++) {
		if ((b->sleep_every > 0 && (count % b->sleep_every) == 0) && b->sleep_ms > 0)
			os_sleep_ms(b, b->sleep_ms);

		const mw_t instr = m[pc % MSIZE]; /* This should probably be a `bload` */
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;

		flg &= ~((1u << fZ) | (1u << fNg)); /* clear zero/negative flags */
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */

		if (b->command || pc == b->bp1)
			if (command(b, &pc, &acc, &flg) < 0)
				return error(b);
		if (b->done)
			break;
		if (b->tron)
			if (fprintf(b->err, "PC:%04X AC:%04X %s:%04X %s:%04X\n", pc, acc, dis(instr), instr, flags(flg, (char[17]){0,}), flg) < 0)
				return error(b);

		if (flg & (1u << fHLT))
			goto halt;
		if (flg & (1u << fR)) {
			rsave(b, 0, 0, 0);
			continue;
		}

		const int direct = cmd & 0x8;
		const mw_t lop = direct ? op1 : bload(b, op1);
		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                            break; /* OR      */
		case 0x1: acc &= lop;                            break; /* AND     */
		case 0x2: acc ^= lop;                            break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);             break; /* ADD     */

		case 0x4: acc <<= bits(lop);                     break; /* LSHIFT  */
		case 0x5: acc >>= bits(lop);                     break; /* RSHIFT  */
		case 0x6: acc = bload(b, lop);                   break; /* LOAD    */
		case 0x7: bstore(b, lop, acc);                   break; /* STORE   */

		case 0x8: acc = bload(b, lop);                   break; /* LOAD-C  */
		case 0x9: bstore(b, lop, acc);                   break; /* STORE-C */
		case 0xA: acc = lop;                             break; /* LITERAL */
		case 0xB:                                        break; /* UNUSED  */

		case 0xC: pc = lop;                              break; /* JUMP    */
		case 0xD: if (!acc) pc = lop;                    break; /* JUMPZ   */
		case 0xE: if (lop & 1) flg = acc; else pc = acc; break; /* SET     */
		case 0xF: acc = lop & 1 ? flg : pc - 1;          break; /* GET     */
		default: return error(b);
		}
	}
halt:
	rsave(b, pc, acc, flg);
	return r;
}

int main(int argc, char **argv) {
	static bcpu_t b = { 
		.flg = 1u << fZ, 
		.bp1 = -1,
		.sleep_every = CONFIG_BIT_SLEEP_EVERY_X_CYCLES,
		.m = {
#ifdef CONFIG_BIT_INCLUDE_DEFAULT_IMAGE /* should contain a Forth image */
#include "bit.inc"
#endif
		},
	};
	b.in = stdin;
	b.out = stdout;
	b.err = stderr;
	b.tron = !!getenv("TRACE");  /* Lazy options; instead of `getopt` just use environment variables */
	b.debug = !!getenv("DEBUG");
	b.command = b.debug;
	b.step = b.debug;
	b.tron = b.tron ? b.tron : b.debug;
	b.blocking = !!getenv("BLOCK");
	b.sleep_ms = getenv("WAKE") ? 0 : CONFIG_BIT_SLEEP_PERIOD_MS;
	setbuf(stdin,  NULL);
	setbuf(stdout, NULL);
	setbuf(stderr, NULL);

	if (argc != 2 && (CONFIG_BIT_INCLUDE_DEFAULT_IMAGE && !getenv("DEFAULT"))) {
		const char *fmt = "Usage: %s prog.hex\n\n\
Project: " BIT_PROJECT "\n\
Author:  " BIT_AUTHOR "\n\
Email:   " BIT_EMAIL "\n\
Repo:    " BIT_REPO  "\n\
License: " BIT_LICENSE "\n\n\
This program returns zero on success and non-zero on failure.\n\n\
Environment Variables:\n\n\
\tTRACE   - if set turn tracing on\n\
\tDEBUG   - if set hit escape to enter debug mode ('h' lists commands)\n\
\tBLOCK   - turn blocking input on (default is non-blocking)\n\
\tDEFAULT - use built in default image (run with no arguments)\n\
\tWAKE    - turn sleeping every X cycles off\n\n";
		(void)fprintf(stderr, fmt, argv[0]);
		return 1;
	}
	if (argc > 1) {
		FILE *in = fopen(argv[1], "rb");
		if (!in) {
			(void)fprintf(stderr, "Could not open file '%s' for reading: %s\n", argv[1], strerror(errno));
			return 2;
		}
		for (size_t i = 0; i < MSIZE; i++) {
			unsigned v = 0;
			if (fscanf(in, "%x", &v) != 1)
				break;
			b.m[i] = v;
		}
		if (fclose(in) < 0) return 3;
	}
	if (os_init(&b) < 0)
		return 4;
	const int r = bcpu(&b) < 0 ? 5 : 0;
	if (os_deinit(&b) < 0)
		return 6;
	return r;
}

