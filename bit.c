/* Bit-Serial CPU simulator
 * LICENSE: MIT
 * AUTHOR:  Richard James Howe
 * EMAIL:   howe.r.j.89@gmail.com
 * GIT:     https://github.com/howerj/bit-serial */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <stdarg.h>
#include <limits.h>

#define MSIZE       (8192u)
#define ESCAPE      (27)
#define SLEEP_EVERY (1024ul*1024ul)

typedef uint16_t mw_t; /* machine word */

typedef struct {
	mw_t pc, acc, flg, m[MSIZE];
	FILE *in, *out;
	mw_t ch, leds, switches;
	int done, sleep_ms;
} bcpu_t;

enum { fCy, fZ, fNg, fR, fHLT, };

#ifdef __unix__ /* unix junk... */
#include <sys/select.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#define __USE_POSIX199309
#define _POSIX_C_SOURCE 199309L
#include <time.h>

static int os_term_save(const int fd, struct termios *oldattr, struct termios *newattr) {
	if (tcgetattr(fd, oldattr) < 0)
		return -1;
	*newattr = *oldattr;
	newattr->c_iflag &= ~(ICRNL);
	newattr->c_lflag &= ~(ICANON | ECHO);
	if (tcsetattr(fd, TCSANOW, newattr) < 0)
		return -2;
	return 0;
}


static int os_term_restore(const int fd, struct termios *oldattr) {
	return tcsetattr(fd, TCSANOW, oldattr) < 0 ? -2 : 0;
}

static int os_getch(bcpu_t *b) {
	assert(b);
	const int fd = STDIN_FILENO;
	struct termios oldattr, newattr;
	if (!isatty(fd))
		return fgetc(stdin);
	if (os_term_save(fd, &oldattr, &newattr) < 0)
		return -1;
	const int ch = getchar();
	if (os_term_restore(fd, &oldattr) < 0)
		return -2;
	return ch;
}

static void sleep_us(unsigned long microseconds) {
	struct timespec ts = {
		.tv_sec  = microseconds / 1000000ul,
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
	const int fd = STDIN_FILENO;
	if (!isatty(fd))
		return 1;
	struct termios oldattr, newattr;
	if (os_term_save(fd, &oldattr, &newattr) < 0)
		return -1;
	sleep_us(1000);
	int bytes = 0;
	ioctl(fd, FIONREAD, &bytes);
	if (os_term_restore(fd, &oldattr) < 0)
		return -2;
	return !!bytes;
}
#else
#ifdef _WIN32
#include <windows.h>
extern int getch(void);
extern int kbhit(void);
static int os_getch(bcpu_t *b) { assert(b); return getch(); }
static int os_kbhit(bcpu_t *b) { assert(b); Sleep(1); return kbhit(); }
static void os_sleep_ms(bcpu_t *b, unsigned ms) { assert(b); Sleep(ms); }
#else
static int os_kbhit(bcpu_t *b) { assert(b); return 1; }
static int os_getch(bcpu_t *b) { assert(b); return getchar(); }
static void os_sleep_ms(bcpu_t *b, unsigned ms) { assert(b); (void)ms; }
#endif
#endif /** __unix__ **/

static int wrap_getch(bcpu_t *b) {
	assert(b);
	const int ch = b->in ? fgetc(b->in) : os_getch(b);
	if ((ch == ESCAPE) || (ch < 0))
		b->done = 1;
	return ch;
}

static int wrap_putch(bcpu_t *b, const int ch) {
	assert(b);
	FILE *out = b->out ? b->out : stdout;
	const int r = fputc(ch, out);
	if (fflush(out) < 0)
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
		if ((count % SLEEP_EVERY) == 0 && b->sleep_ms > 0)
			os_sleep_ms(b, b->sleep_ms);

		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;

		if (flg & (1u << fHLT))
			goto halt;
		if (flg & (1u << fR)) {
			pc = 0;
			acc = 0;
			flg = 0;
			continue;
		}

		flg &= ~((1u << fZ) | (1u << fNg));
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */

		const mw_t lop = (cmd & 0x8) ? op1 : bload(b, op1);

		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                                 break; /* OR      */
		case 0x1: acc &= lop;                                 break; /* AND     */
		case 0x2: acc ^= lop;                                 break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);                  break; /* ADD     */

		case 0x4: acc <<= bits(lop);                          break; /* LSHIFT  */
		case 0x5: acc >>= bits(lop);                          break; /* RSHIFT  */
		case 0x6: acc = bload(b, lop);                        break; /* LOAD    */
		case 0x7: bstore(b, lop, acc);                        break; /* STORE   */

		case 0x8: acc = bload(b, op1);                        break; /* LOAD-C  */
		case 0x9: bstore(b, op1, acc);                        break; /* STORE-C */
		case 0xA: acc = op1;                                  break; /* LITERAL */
		case 0xB:                                             break; /* UNUSED  */

		case 0xC: pc = op1;                                   break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;                         break; /* JUMPZ   */
		case 0xE: if (op1 & 1) flg = acc; else pc = acc;      break; /* SET     */
		case 0xF: if (op1 & 1) acc = flg; else acc = pc - 1u; break; /* GET     */
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
	static bcpu_t b = { .flg = 1u << fZ, .sleep_ms = 5, };
	if (argc != 2)
		return 1;
	setbuf(stdin,  NULL);
	setbuf(stdout, NULL);
	FILE *in = fopen(argv[1], "rb");
	if (!in)
		return 2;
	for (size_t i = 0; i < MSIZE; i++) {
		unsigned pc = 0;
		if (fscanf(in, "%x", &pc) != 1)
			break;
		b.m[i] = pc;
	}
	return bcpu(&b) < 0 ? 3 : 0;
}

