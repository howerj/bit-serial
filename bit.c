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

#define CONFIG_TRACER_ON (1)
#define MSIZE            (4096u)
#define MAX_VARS         (256u)
#define NELEM(X)         (sizeof(X)/sizeof(X[0]))
typedef uint16_t mw_t; /* machine word */
typedef struct { mw_t pc, acc, flg, m[MSIZE]; } bcpu_t;
typedef struct { FILE *in, *out; mw_t ch, leds, switches; } bcpu_io_t;
typedef struct { char name[32]; int type; mw_t value; } var_t;
typedef struct { char name[32]; const char *start, *end; int params; } macro_t;
typedef struct { var_t vs[MAX_VARS], unknown[MAX_VARS]; macro_t macros[MAX_VARS]; unsigned long used, data; } assembler_t;
enum { TYPE_VAR, TYPE_LABEL, TYPE_CONST, TYPE_MACRO };
enum { fCy, fZ, fNg, fPAR, fROT, fR, fIND, fHLT, };

static const char *commands[] = { 
	"or",     "and",    "xor",     "add",  
	"lshift", "rshift", "load",    "store",
	"in",     "out",    "literal", "flags",
	"jump",   "jumpz",  "jumpi",   "pc",
};

static int instruction(const char *c) {
	assert(c);
	for (size_t i = 0; i < sizeof(commands) / sizeof(commands[0]); i++) {
		if (!strcmp(commands[i], c))
			return i;
	}
	return -1;
}

static var_t *lookup(var_t *vs, size_t length, const char *var) {
	assert(vs);
	assert(var);
	for (size_t i = 0; i < length; i++) {
		var_t *v = &vs[i];
		if (vs->name[0] == 0)
			return NULL;
		if (!strcmp(v->name, var))
			return v;
	}
	return NULL;
}

static int reference(var_t *vs, size_t length, const char *name, int type, mw_t value, int unique) {
	assert(vs);
	assert(name);
	if (unique && lookup(vs, length, name))
		return -1;
	for (size_t i = 0; i < length; i++) {
		var_t *v = &vs[i];
		if (v->name[0] == 0) {
			strncpy(v->name, name, sizeof v->name);
			v->name[sizeof(v->name) - 1] = 0;
			v->type = type;
			v->value = value;
			return 0;
		}
	}
	return -2;
}

/* return unknown name on failure, NULL on success */
static char *patch(bcpu_t *b, var_t *labels, size_t llength, var_t *patches, size_t plength) {
	assert(b);
	assert(patches);
	assert(labels);
	for (size_t i = 0; i < plength; i++) {
		var_t *patch = &patches[i];
		if (patch->name[0] == 0)
			return NULL; /* success */
		var_t *label = lookup(labels, llength, patch->name);
		if (!label || label->type != TYPE_LABEL)
			return &patch->name[0]; /* failure */
		b->m[patch->value] = (b->m[patch->value] & 0xF000u) | (label->value & 0x0FFFu);
	}
	return NULL; /* success */
}

static int skip(char *line) {
	assert(line);
	for (size_t i = 0; line[i]; i++)
		if (line[i] == ';' || line[i] == '#') {
			line[i] = '\0';
			return 1;
		}
	return 0;
}

static int println(FILE *out, const char *fmt, va_list ap) {
	assert(out);
	assert(fmt);
	const int r1 = vfprintf(out, fmt, ap);
	const int r2 = fputc('\n', out);
	const int r3 = fflush(out);
	return r1 > 0 && r2 > 0 && r3 > 0 ? r1 + 1 : -1;
}

static int error(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	println(stderr, fmt, ap);
	va_end(ap);
	return -1;
}

static void die(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	println(stderr, fmt, ap);
	va_end(ap);
	exit(EXIT_FAILURE);
}

static char *sgets(char *line, size_t length, const char **input) {
	assert(line);
	assert(input && *input);
	int ch = 0;
	size_t i = 0;
	const char *in = *input;
	if (length == 0)
		return NULL;
	if (length == 1) {
		line[0] = '\0';
		return line;
	}
	
	for (i = 0; (i < (length - 1)) && (ch = in[i]); i++) {
		line[i] = ch;
		if (ch == '\n')
			break;
	}
	if (!i && !ch)
		return NULL;
	line[i + 1] = '\0';
	*input = in + i + 1;
	return line;
}


static int macro(macro_t *m, size_t length, const char *arg1, const char **input) {
	assert(m);
	assert(input && *input);
	assert(arg1);
	size_t i = 0;
	for (i = 0; i < length; i++)
		if (m->name[0])
			m++;
		else
			break;
	if (i >= length)
		return -1;
	memset(m->name, 0, sizeof(m->name));
	strncpy(m->name, arg1, sizeof(m->name) - 1);
	const char *in = *input;
	const char terminator[] = ".end";
	const char *end = strstr(in, terminator);
	if (!end)
		return -2;
	m->start = in;
	m->end = end;
	*input = m->end + (sizeof(terminator) - 1);
	return 0;
}

static const macro_t *get(macro_t *m, size_t length, const char *name) {
	assert(m);
	assert(name);
	size_t i = 0;
	for (i = 0; i < length; i++)
		if (!strcmp(m->name, name))
			return m;
		else
			m++;
	return NULL;
}

static int assemble(bcpu_t *b, assembler_t *a, const char *input) { /* super lazy assembler */
	assert(b);
	assert(input);
	for (char line[256] = { 0 }; sgets(line, sizeof line, &input); memset(line, 0, sizeof line)) {
		char command[80] = { 0 }, arg1[80] = { 0 }, arg2[80] = { 0 };
		skip(line);
		unsigned op0 = 0, op1 = 0, op2 = 0;
		const int args = sscanf(line, "%79s %79s %79s", command, arg1, arg2);
		const int arg0num = sscanf(command, "$%x", &op0) == 1;
		const int arg1num = sscanf(arg1,    "$%x", &op1) == 1;
		const int arg2num = sscanf(arg2,    "$%x", &op2) == 1;

		if (a->used >= a->data) {
			error("program space full");
			goto fail;
		}
		if (args <= 0) {
			/* do nothing */
		} else if (args == 1) {
			if (arg0num) {
				b->m[a->used++] = op0;
			} else if (!strcmp(command, "jumpi")) {
				assert(a->used < MSIZE);
				b->m[a->used++] = (instruction("jumpi") << 12u) | 0;
			} else if (!strcmp(command, "pc")) {
				assert(a->used < MSIZE);
				b->m[a->used++] = (instruction("pc") << 12u) | 0;
			} else {
				var_t *v = lookup(a->vs, NELEM(a->vs), command);
				if (!v) {
					const macro_t *m = get(a->macros, NELEM(a->macros), command);
					if (!m) {
						error("invalid command: %s", line);
						goto fail;
					}
					const size_t l = m->end - m->start;
					char *eval = malloc(l + 1);
					if (!eval) {
						error("out of memory");
						goto fail;
					}
					memcpy(eval, m->start, l);
					eval[l] = '\0';
					const int r = assemble(b, a, eval);
					free(eval);
					if (r < 0) {
						error("macro eval failed: %d", r);
						goto fail;
					}
				} else {
					b->m[a->used++] = v->value;
				}
			}
		} else if (args == 2) {
			if (arg1num && op1 > 0x0FFFu) {
				error("operand too big: %x", op1);
				goto fail;
			}
			const int inst = instruction(command);
			if (inst < 0) {
				if (!strcmp(command, ".allocate")) {
					if (!arg1num) {
						error("invalid allocate: %s", arg1);
						goto fail;
					}
					a->data -= op1;
				} else if (!strcmp(command, ".variable")) {
					const int added = reference(a->vs, NELEM(a->vs), arg1, TYPE_VAR, a->data--, 1);
					if (added < 0) {
						error("variable? %d/%s", added, arg1);
						goto fail;
					}
				} else if (!strcmp(command, ".label")) {
					const int added = reference(a->vs, NELEM(a->vs), arg1, TYPE_LABEL, a->used, 1);
					if (added < 0) {
						error("label? %d/%s", added, arg1);
						goto fail;
					}
				} else if (!strcmp(command, ".macro")) {
					const int mac = macro(a->macros, NELEM(a->macros), arg1, &input);
					if (mac < 0) {
						error("macro? %d/%s", mac, arg1);
						goto fail;
					}
				} else {
					error("unknown command: %s", command);
					goto fail;
				}
			} else {
				if (!arg1num) {
					var_t *v = lookup(a->vs, NELEM(a->vs), arg1);
					if (!v) {
						const int added = reference(a->unknown, NELEM(a->unknown), arg1, TYPE_LABEL, a->used, 0);
						if (added < 0) {
							error("forward reference? %d/%s", added, arg1);
							goto fail;
						}
						op1 = 0; // patch later
					} else {
						op1 = v->value;
					}
				}
				assert(a->used < MSIZE);
				b->m[a->used++] = (((mw_t)inst) << 12) | op1;
			}
		} else if (args == 3) {
			if (!strcmp(command, ".set")) {
				if (!arg1num) {
					var_t *v = lookup(a->vs, NELEM(a->vs), arg1);
					if (!v) {
						error("unknown variable: %s", arg1);
						goto fail;
					}
					op1 = v->value;
				}
				if (op1 > 0x0FFF) {
					error("operand too big: %x", op1);
					goto fail;
				}

				if (!arg2num) {
					var_t *v = lookup(a->vs, NELEM(a->vs), arg2);
					if (!v) {
						error("unknown variable: %s", arg2);
						goto fail;
					}
					op2 = v->value;
				}
				assert(op1 < MSIZE);
				b->m[op1] = op2;
			} else if (!strcmp(command, ".constant")) {
				if (!arg2num) { /* TODO: evaluate simple expressions */
					error("not a number: %s", arg2);
					goto fail;
				}
				const int added = reference(a->vs, NELEM(a->vs), arg1, TYPE_CONST, op2, 0);
				if (added < 0) {
					error("constant? %d/%s", added, arg1);
					goto fail;
				}
			} else {
				error("unknown command: %s", command);
				goto fail;
			}
		} else {
			error("invalid command: \"%s\"", line);
			goto fail;
		}
	}
	const char *unknown_label = patch(b, a->vs, NELEM(a->vs), a->unknown, NELEM(a->unknown));
	if (unknown_label) {
		error("invalid reference: %s", unknown_label);
		goto fail;
	}
	return 0;
fail:
	return -1;
}


static int assembler(bcpu_t *b, assembler_t *a, const char *input) {
	assert(a);
	assert(b);
	assert(input);
	b->pc = 0;
	b->acc = 0;
	memset(b->m, 0, sizeof b->m);
	a->used = 0; 
	a->data = MSIZE - 1;
	return assemble(b, a, input);
}

static inline int trace(bcpu_t *b, bcpu_io_t *io, FILE *tracer, 
		unsigned cycles, const mw_t pc, const mw_t flg, 
		const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	assert(io);
	if (!tracer)
		return 0;
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	char cbuf[9] = { 0 };
	snprintf(cbuf, sizeof cbuf - 1, "%s       ", commands[cmd]);
	return fprintf(tracer, "%4x: %4x %2x:%s %4x %4x %4x %4x\n", 
			cycles, (unsigned)pc, (unsigned)cmd, cbuf, 
			(unsigned)acc, (unsigned)op1, (unsigned)flg, 
			(unsigned)io->leds);
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

/*static inline mw_t sub(mw_t a, mw_t b, mw_t *under) {
	assert(under);
	const mw_t r = a - b;
	*under &= ~2u;
	*under |= b > a;
	return r;
}*/

static inline mw_t bload(bcpu_t *b, bcpu_io_t *io, int is_io, mw_t addr) {
	assert(b);
	assert(io);
	addr &= 0x0FFFu;
	addr |= ((mw_t)!!is_io) << 15;
	if (addr & 0x8000u) { /* io */
		switch (addr & 0x7) {
		case 0: return io->switches;
		case 1: return (1u << 11u) | (io->ch & 0xFF);
		}
		return 0;
	}
	return b->m[addr % MSIZE];
}

static inline void bstore(bcpu_t *b, bcpu_io_t *io, int is_io, mw_t addr, mw_t val) {
	assert(b);
	assert(io);
	addr &= 0x0FFFu;
	addr |= ((mw_t)!!is_io) << 15;
	if (addr & 0x8000u) { /* io */
		switch (addr & 0x7) {
		case 0: io->leds = val; break;
		case 1: 
			if (val & (1u << 13)) {
				fputc(val & 0xFFu, io->out);
				fflush(io->out);
			}
			if (val & (1u << 10))
				io->ch = fgetc(io->in);
			break;
		case 2: /* TX control */ break;
		case 3: /* RX control */ break;
		case 4: /* UART control */ break;
		}
	} else {
		b->m[addr % MSIZE] = val;
	}
}

static int bcpu(bcpu_t *b, bcpu_io_t *io, FILE *tracer, const unsigned cycles) {
	assert(b);
	assert(io);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg, t = 0;
	const unsigned forever = cycles == 0;
       	unsigned count = 0;
	for (; count < cycles || forever; count++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		const int rot    = !!(flg & (1u << fROT));
		if (CONFIG_TRACER_ON)
			trace(b, io, tracer, count, pc, flg, acc, op1, cmd);
		if (flg & (1u << fHLT)) /* HALT */
			goto halt;
		if (flg & (1u << fR)) { /* RESET */
			pc = 0;
			acc = 0;
			flg = 0;
		}
		flg &= ~((1u << fZ) | (1u << fNg) | (1u << fPAR));
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */
		flg |= (!(bits(acc) & 1u)) << fPAR; /* set parity bit    */

		const mw_t lop = !(cmd & 0x8) && (flg & (1u << fIND)) ? bload(b, io, 0, op1) : op1; 
		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                        break; /* OR      */
		case 0x1: acc &= (0xF000 | lop);             break; /* AND     */
		case 0x2: acc ^= lop;                        break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);         break; /* ADD     */

		case 0x4: acc = shiftl(rot, acc, bits(lop)); break; /* LSHIFT  */
		case 0x5: acc = shiftr(rot, acc, bits(lop)); break; /* RSHIFT  */
		case 0x6: acc = bload(b, io, 0, lop);        break; /* LOAD    */
		case 0x7: bstore(b, io, 0, lop, acc);        break; /* STORE   */

		case 0x8: acc = bload(b, io, 1, op1);        break; /* IN      */
		case 0x9: bstore(b, io, 1, op1, acc);        break; /* OUT     */
		case 0xA: acc = op1;                         break; /* LITERAL */
		case 0xB: t = flg; flg= (~op1 & acc) | (op1 & flg); acc = t; break; /* FLAGS   */

		case 0xC: pc = op1;                          break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;                break; /* JUMPZ   */
		case 0xE: pc = acc;                          break; /* JUMPI   */
		case 0xF: acc = pc;                          break; /* PC      */

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

int main(int argc, char **argv) {
	int compile = 0, run = 0, cycles = 0x1000;
	static bcpu_t b = { 0, 0, 0, { 0 } };
	static assembler_t a;
	bcpu_io_t io = { .in = stdin, .out = stdout };
	FILE *file = stdin, *trace = stderr, *hex = NULL;
	if (argc < 2)
		die("usage: %s -trashf input? out.hex?", argv[0]);
	if (argc >= 3)
		file = fopen_or_die(argv[2], "rb");
	if (argc >= 4)
		hex     = fopen_or_die(argv[3], "wb");
	for (size_t i = 0; argv[1][i]; i++)
		switch (argv[1][i]) {
		case '-':                   break;
		case 't': trace   = stderr; break;
		case 'r': run     = 1;      break;
		case 'a': compile = 1;      break;
		case 's': trace   = NULL;   break;
		case 'h': compile = 0;      break;
		case 'f': cycles  = 0;      break;
		default:  die("invalid option -- %c", argv[1][i]);
		}
	if (compile) {
		static char program[128*1024] = { 0 };
		program[fread(program, 1, sizeof program, file)] = '\0';
		if (assembler(&b, &a, program) < 0)
			die("assembling file failed");
	} else {
		if (load(&b, file) < 0)
			die("loading hex file failed");
	}

	if (hex && save(&b, hex) < 0)
		die("saving file failed");
	if (run && bcpu(&b, &io, trace, cycles) < 0)
		die("running failed");
	return 0; /* dying cleans everything up */
}

