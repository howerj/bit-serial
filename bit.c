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

#define MSIZE     (4096u)
#define ESCAPE    (27)

typedef uint16_t mw_t; /* machine word */

typedef struct {
	mw_t pc, acc, flg, m[MSIZE];
	FILE *in, *out;
	mw_t ch, leds, switches;
	int done;
} bcpu_t;

enum { fCy, fZ, fNg, fPAR, fROT, fR, fIND, fHLT, };

#ifdef __unix__
#include <unistd.h>
#include <termios.h>
static int getch(void) {
	const int fd = STDIN_FILENO;
	struct termios oldattr, newattr;
	if (!isatty(fd))
		return fgetc(stdin);
	if (tcgetattr(fd, &oldattr) < 0)
		return -2;
	newattr = oldattr;
	newattr.c_iflag &= ~(ICRNL);
	newattr.c_lflag &= ~(ICANON | ECHO);
	if (tcsetattr(fd, TCSANOW, &newattr) < 0)
		return -2;
	const int ch = getchar();
	if (tcsetattr(fd, TCSANOW, &oldattr) < 0)
		return -2;
	return ch;
}

#else
#ifdef _WIN32
extern int getch(void);
extern int putch(int c);
#else
static int getch(void) { return getchar(); }
static int putch(const int c) { return putchar(c); }
#endif
#endif /** __unix__ **/

static int wrap_getch(bcpu_t *b) {
	assert(b);
	const int ch = b->in ? fgetc(b->in) : getch();
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

static inline mw_t rotl(const mw_t value, unsigned shift) {
	shift &= (sizeof(value) * CHAR_BIT) - 1u;
	if (!shift)
		return value;
	return (value << shift) | (value >> ((sizeof(value) * CHAR_BIT) - shift));
}

static inline mw_t rotr(const mw_t value, unsigned shift) {
	shift &= (sizeof(value) * CHAR_BIT) - 1u;
	if (!shift)
		return value;
	return (value >> shift) | (value << ((sizeof(value) * CHAR_BIT) - shift));
}

static inline mw_t shiftl(const int type, const mw_t value, unsigned shift) {
	return type ? rotl(value, shift) : value << shift;
}

static inline mw_t shiftr(const int type, const mw_t value, unsigned shift) {
	return type ? rotr(value, shift) : value >> shift;
}

static inline mw_t add(mw_t a, mw_t b, mw_t *carry) {
	assert(carry);
	const mw_t parry = !!(*carry & 1u);
	const mw_t r = a + b + parry;
	*carry &= ~(1u << fCy);
	if (r < (a + parry) && r < (b + parry))
		*carry |= (1u << fCy);
	return r;
}

static inline mw_t bload(bcpu_t *b, mw_t addr) {
	assert(b);
	if (!(0x4000ul & addr)) {
		if (addr >= MSIZE)
			return 0;
		return b->m[addr % MSIZE];
	}
	switch (addr & 0x7) {
	case 0: return b->switches;
	case 1: return (1u << 11u) | (b->ch & 0xFF);
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
       	unsigned count = 0;
	flg |= (1u << fZ);

	for (;b->done == 0; count++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		const int rot    = !!(flg & (1u << fROT));
		if (flg & (1u << fHLT))
			goto halt;
		if (flg & (1u << fR)) {
			pc = 0;
			acc = 0;
			flg = 0;
			continue;
		}
		flg &= ~((1u << fZ) | (1u << fNg) | (1u << fPAR));
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */
		flg &= ~(1u << fPAR);               /* clear parity flag */
		flg |= ((bits(acc) & 1u)) << fPAR;  /* set parity flag   */

		const int loadit = !(cmd & 0x8) && (flg & (1u << fIND));
		const mw_t lop = loadit ? bload(b, op1) : op1;

		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                                 break; /* OR      */
		case 0x1: acc &= ((loadit ? 0: 0xF000) | lop);        break; /* AND     */
		case 0x2: acc ^= lop;                                 break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);                  break; /* ADD     */

		case 0x4: acc = shiftl(rot, acc, bits(lop));          break; /* LSHIFT  */
		case 0x5: acc = shiftr(rot, acc, bits(lop));          break; /* RSHIFT  */
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
	static bcpu_t b = { .in = NULL };
	if (argc != 2)
		return 1;
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

