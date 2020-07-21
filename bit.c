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
#define NELEM(X)  (sizeof(X)/sizeof(X[0]))
#define UNUSED(X) ((void)(X))
#define BACKSPACE (8)
#define ESCAPE    (27)
#define DELETE    (127)

typedef uint16_t mw_t; /* machine word */

typedef struct { 
	mw_t pc, acc, flg, m[MSIZE]; 
	/* io */ 
	FILE *in, *out; 
	mw_t ch, leds, switches;
	/* options */
	unsigned long cycles;
	int forever;
	FILE *trace;
} bcpu_t;

enum { fCy, fZ, fNg, fPAR, fROT, fR, fIND, fHLT, };

#ifdef _WIN32 /* Making standard input streams on Windows binary */
#include <windows.h>
#include <io.h>
#include <fcntl.h>
extern int _fileno(FILE *stream);
static void binary(FILE *f) { _setmode(_fileno(f), _O_BINARY); }
#else
static inline void binary(FILE *f) { UNUSED(f); }
#endif

#ifdef __unix__
#include <unistd.h>
#include <termios.h>
static int getch(void) {
	struct termios oldattr, newattr;
	if (tcgetattr(STDIN_FILENO, &oldattr) < 0) /* Use 'fileno(b->in)'? */
		return -2;
	newattr = oldattr;
	newattr.c_iflag &= ~(ICRNL);
	newattr.c_lflag &= ~(ICANON | ECHO);
	if (tcsetattr(STDIN_FILENO, TCSANOW, &newattr) < 0)
		return -2;
	const int ch = getchar();
	if (tcsetattr(STDIN_FILENO, TCSANOW, &oldattr) < 0)
		return -2;
	return ch;
}

static int putch(int c) {
	const int r = putchar(c);
	if (fflush(stdout) < 0)
		return -1;
	return r;
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
	if (b->in != stdin)
		return fgetc(b->in);
	const int ch = getch();
	if (ch == ESCAPE) {
		(void)fprintf(stderr, "escape hit -- exiting\n");
		exit(EXIT_SUCCESS);
	}
	return ch == DELETE ? BACKSPACE : ch;
}

static int wrap_putch(bcpu_t *b, const int ch) {
	assert(b);
	if (b->out != stdout) {
		const int r = fputc(ch, b->out);
		if (fflush(b->out) < 0)
			return -1;
		return r;
	}
	const int r = putch(ch);
	if (fflush(stdout) < 0)
		return -1;
	return r;
}

static void die(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	(void)vfprintf(stderr, fmt, ap);
	(void)fputc('\n', stderr);
	(void)fflush(stderr);
	va_end(ap);
	exit(EXIT_FAILURE);
}

static int debug(bcpu_t *b, const char *fmt, ...) {
	assert(b);
	assert(fmt);
	if (!(b->trace))
		return 0;
	va_list ap;
	va_start(ap, fmt);
	const int r1 = vfprintf(b->trace, fmt, ap);
	const int r2 = fputc('\n', b->trace);
	const int r3 = fflush(b->trace);
	va_end(ap);
	return r1 < 0 || r2 < 0 || r3 < 0 ? -1 : r1 + 1;
}

static int yn(bcpu_t *b, int idx, char ch, unsigned flg) {
	assert(b);
	char s[3] = { 1u << idx & flg ? ch : '-', ' ', '\0'};
	return fputs(s, b->trace) < 0 ? -1 : 0;
}

static int trace(bcpu_t *b, 
		const unsigned cycles, const unsigned pc, const unsigned flg, 
		const unsigned acc, const unsigned op1, const unsigned cmd) {
	assert(b);
	(void)(cycles);
	if (!(b->trace))
		return 0;
	static const char *commands[] = { 
		"ior",     "iand",    "ixor",     "iadd",  
		"ilshift", "irshift", "iload",    "istore",
		"iloadc",  "istorec", "iliteral", "iunused",
		"ijump",   "ijumpz",  "iset",     "iget",
	};
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	if (fprintf(b->trace, "%04X: %s\t%04X %04X %04X ", pc, commands[cmd], acc, op1, flg) < 0)
		return -1;
	if (yn(b, fCy,  'C', flg) < 0) return -1;
	if (yn(b, fZ,   'Z', flg) < 0) return -1;
	if (yn(b, fNg,  'N', flg) < 0) return -1;
	if (yn(b, fPAR, 'P', flg) < 0) return -1;
	if (yn(b, fROT, 'S', flg) < 0) return -1;
	if (yn(b, fR,   'R', flg) < 0) return -1;
	if (yn(b, fIND, 'I', flg) < 0) return -1;
	if (yn(b, fHLT, 'H', flg) < 0) return -1;
	return fputc('\n', b->trace) < 0 ? -1 : 0;
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
	if (!(0x8000ul & addr)) {
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
	if (!(0x8000ul & addr)) {
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

static int bcpu(bcpu_t *b, const unsigned cycles, const int forever) {
	assert(b);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg;
       	unsigned count = 0;
	flg |= (1u << fZ);

	for (; count < cycles || forever; count++) {
		if (pc >= MSIZE)
			if (debug(b, "{INVALID PC: %u}", (unsigned)pc) < 0) {
				r = -1;
				goto halt;
			}
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		const int rot    = !!(flg & (1u << fROT));
		if (flg & (1u << fHLT)) { /* HALT */
			if (debug(b, "{HALT}") < 0)
				r = -1;
			goto halt;
		}

		if (flg & (1u << fR)) { /* RESET */
			if (debug(b, "{RESET}") < 0) {
				r = -1;
				goto halt;
			}
			pc = 0;
			acc = 0;
			flg = 0;
			continue;
		}
		flg &= ~((1u << fZ) | (1u << fNg) | (1u << fPAR));
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */
		flg &= ~(1u << fPAR);
		flg |= ((bits(acc) & 1u)) << fPAR;  /* set parity bit    */

		const int loadit = !(cmd & 0x8) && (flg & (1u << fIND));
		const mw_t lop = loadit ? bload(b, op1) : op1; 

		if (trace(b, count, pc, flg, acc, lop, cmd) < 0) {
			r = -1;
			goto halt;
		}
		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                            break; /* OR      */
		case 0x1: acc &= ((loadit ? 0: 0xF000) | lop);   break; /* AND     */
		case 0x2: acc ^= lop;                            break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);             break; /* ADD     */

		case 0x4: acc = shiftl(rot, acc, bits(lop));     break; /* LSHIFT  */
		case 0x5: acc = shiftr(rot, acc, bits(lop));     break; /* RSHIFT  */
		case 0x6: acc = bload(b, lop);                   break; /* LOAD    */
		case 0x7: bstore(b, lop, acc);                   break; /* STORE   */

		case 0x8: acc = bload(b, op1);                   break; /* LOAD-C  */
		case 0x9: bstore(b, op1, acc);                   break; /* STORE-C  */
		case 0xA: acc = op1;                             break; /* LITERAL */
		case 0xB:                                        break; /* UNUSED  */

		case 0xC: pc = op1;                              break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;                    break; /* JUMPZ   */
		case 0xE:                                               /* SET     */
			if (op1 & 0x0800) { bstore(b, 0x8000u | op1, acc); } 
			else { if (op1 & 1) flg = acc; else pc = acc; } 
			break;
		case 0xF:                                               /* GET */
			if (op1 & 0x0800) { acc = bload(b, 0x8000u | op1); } 
			else { if (op1 & 1) acc = flg; else acc = pc - 1u; } 
			break;
		default: r = -1; goto halt;
		}

	}
halt:
	b->pc  = pc;
	b->acc = acc;
	b->flg = flg;
	return r;
}

static int load(bcpu_t *b, FILE *input) {
	assert(b);
	assert(input);
	for (size_t i = 0; i < MSIZE; i++) {
		int pc = 0;
		if (fscanf(input, "%x", &pc) != 1)
			break;
		b->m[i] = pc;
	}
	return 0;
}

static int save(bcpu_t *b, FILE *output) {
	assert(b);
	assert(output);
	for (size_t i = 0; i < MSIZE; i++) /* option to save the rest of bcpu_t? */
		if (fprintf(output, "%04x\n", (unsigned)(b->m[i])) < 0)
			return -1;
	return 0;
}

static FILE *fopen_or_die(const char *file, const char *mode) {
	assert(file);
	assert(mode);
	FILE *r = fopen(file, mode);
	if (!r)
		die("unable to open file \"%s\" (mode = %s)", file, mode);
	return r;
}

/* Because of the limitations of the VHDL test bench configuration items
 * are identified by their position in the file */
static int configure(bcpu_t *b, const char *file, FILE *tfile) {
	assert(b);
	assert(file);
	assert(tfile);
	int d = 0;
	FILE *cfg = fopen_or_die(file, "rb");
	b->forever = 1;
	b->cycles  = 10000; /* VHDL simulation uses clock cycles, this is an instruction count */
	b->trace   = NULL;
	if (fscanf(cfg, "%lu", &b->cycles) < 0)  goto done;
	if (fscanf(cfg, "%d",  &b->forever) < 0) goto done;
	if (fscanf(cfg, "%d",  &d) < 0)          goto done;
done:
	b->trace = d ? tfile : NULL;
	if (fclose(cfg) < 0)
		return 0;
	return 0;
}

int main(int argc, char **argv) {
	int cycles = 0x1000, i = 1, forever = 1;
	static bcpu_t b = { .in = NULL };
	binary(stdin);
	binary(stdout);
	binary(stderr);
	b.in    = stdin;
	b.out   = stdout;
	FILE *file = stdin, *hex = NULL, *tfile = stderr;
	if (i < argc)
		if (configure(&b, argv[i++], tfile) < 0)
			return 1;
	if (i < argc)
		file = fopen_or_die(argv[i++], "rb");
	if (i < argc)
		hex  = fopen_or_die(argv[i++], "wb");
	if (load(&b, file) < 0)
		die("loading hex file failed");
	if (bcpu(&b, cycles, forever) < 0)
		die("running failed");
	if (hex && save(&b, hex) < 0)
		die("saving file failed");
	return 0; /* dying cleans everything up */
}

