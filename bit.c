/* PROJECT: Bit-Serial CPU simulator
 * AUTHOR:  Richard James Howe
 * EMAIL:   howe.r.j.89@gmail.com
 * REPO:    https://github.com/howerj/bit-serial
 * LICENSE: MIT */
#ifdef __unix__
#include <sys/select.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#define __USE_POSIX199309
#define _POSIX_C_SOURCE 199309L
#endif
#include <assert.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MSIZE       (8192u)
#define ESCAPE      (27)

typedef uint16_t mw_t; /* machine word */

typedef struct {
	mw_t pc, acc, flg, m[MSIZE];
	FILE *in, *out, *debug;
	mw_t ch, leds, switches;
	long done, sleep_ms, sleep_every;
#ifdef __unix__
	struct termios oldattr; /* ugly, but needed for Unix only */
#endif
} bcpu_t;

enum { fCy, fZ, fNg, fR, fHLT, };

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

static int os_kbhit(bcpu_t *b) {
	assert(b);
	const int fd = fileno(b->in);
	if (!isatty(fd))
		return 1;
	int bytes = 0;
	ioctl(fd, FIONREAD, &bytes);
	return !!bytes;
}

static int os_init(bcpu_t *b) {
	assert(b);
	const int fd = fileno(b->in);
	if (!isatty(fd))
		return 0;
	if (tcgetattr(fd, &b->oldattr) < 0)
		return -1;
	struct termios newattr = b->oldattr;
	newattr.c_iflag &= ~(ICRNL);
	newattr.c_lflag &= ~(ICANON | ECHO);
	if (tcsetattr(fd, TCSANOW, &newattr) < 0)
		return -2;
	return 0;
}

static int os_deinit(bcpu_t *b) {
	assert(b);
	if (!isatty(fileno(b->in)))
		return 0;
	return tcsetattr(fileno(b->in), TCSANOW, &b->oldattr) < 0 ? -1 : 0;
}
#else
#ifdef _WIN32
#include <windows.h>
extern int getch(void);
extern int kbhit(void);
static int os_getch(bcpu_t *b) { assert(b); return b->in == stdin ? getch() : fgetc(b->in); }
static int os_kbhit(bcpu_t *b) { assert(b); Sleep(1); return kbhit(); } /* WTF? */
static void os_sleep_ms(bcpu_t *b, unsigned ms) { assert(b); Sleep(ms); }
static int os_init(bcpu_t *b) { assert(b); return 0; }
static int os_deinit(bcpu_t *b) { assert(b); return 0; }
#else
static int os_kbhit(bcpu_t *b) { assert(b); return 1; }
static int os_getch(bcpu_t *b) { assert(b); return fgetc(b->in); }
static void os_sleep_ms(bcpu_t *b, unsigned ms) { assert(b); (void)ms; }
static int os_init(bcpu_t *b) { assert(b); return 0; }
static int os_deinit(bcpu_t *b) { assert(b); return 0; }
#endif
#endif /** __unix__ **/

static int debug_on(bcpu_t *b) {
	assert(b);
	return b->debug != NULL;
}

static int print_registers(bcpu_t *b, unsigned count, uint16_t pc, uint16_t acc, uint16_t instr, uint16_t flg) {
	assert(b);
	if (!debug_on(b))
		return 0;
	FILE *o = b->debug;
	if (fprintf(o, "CYC:%08X PC=%04X AC=%04X IN=%04X FL=%04X\n", count, pc, acc, instr, flg) < 0)
		return -1;
	return 0;
}

static int wrap_getch(bcpu_t *b) {
	assert(b);
	const int ch = os_getch(b);
	if ((ch == ESCAPE) || (ch < 0))
		b->done = 1;
	return ch;
}

static int wrap_putch(bcpu_t *b, const int ch) {
	assert(b);
	const int r = fputc(ch, b->out);
	if (fflush(b->out) < 0)
		return -1;
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
	case 1:
		if (val & (1u << 13)) {
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

static int bcpu(bcpu_t *b) {
	assert(b);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg;

	for (unsigned count = 0; b->done == 0; count++) {
		if ((b->sleep_every && (count % b->sleep_every) == 0) && b->sleep_ms > 0)
			os_sleep_ms(b, b->sleep_ms);

		const mw_t instr = m[pc++ % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;

		if (print_registers(b, count, pc, acc, instr, flg) < 0) {
			r = -1;
			goto halt;
		}

		if (flg & (1u << fHLT))
			goto halt;
		if (flg & (1u << fR)) {
			pc  = 0;
			acc = 0;
			flg = 0;
			continue;
		}

		flg &= ~((1u << fZ) | (1u << fNg)); /* clear zero/negative flags */
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */

		const int indirect = cmd & 0x8;
		const mw_t lop = indirect ? op1 : bload(b, op1);

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
		default: r = -1; goto halt;
		}
	}
halt:
	b->pc  = pc;
	b->acc = acc;
	b->flg = flg;
	return r;
}

int main(int argc, char **argv) {
	static bcpu_t b = { .flg = 1u << fZ, .sleep_ms = 5, .sleep_every = 64 * 1024, };
	if (argc != 2) {
		(void)fprintf(stderr, "Usage: %s prog.hex\n", argv[0]);
		return 1;
	}
	b.in    = stdin;
	b.out   = stdout;
	/*b.debug = stderr;*/
	FILE *in = fopen(argv[1], "rb");
	if (!in)
		return 2;
	for (size_t i = 0; i < MSIZE; i++) {
		unsigned pc = 0;
		if (fscanf(in, "%x", &pc) != 1)
			break;
		b.m[i] = pc;
	}
	if (os_init(&b) < 0)
		return 3;
	setbuf(stdin,  NULL);
	setbuf(stdout, NULL);
	setbuf(stderr, NULL);
	const int r = bcpu(&b) < 0 ? 4 : 0;
	if (os_deinit(&b) < 0)
		return 5;
	return r;
}

